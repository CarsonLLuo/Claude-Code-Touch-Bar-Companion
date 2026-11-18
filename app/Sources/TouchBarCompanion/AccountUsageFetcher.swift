import Foundation
import CompanionCore

/// Opt-in: polls the endpoint behind Claude Code's `/usage` with the OAuth token Claude Code
/// keeps in the login keychain, and records the result like the status line does.
///
/// - The token is read on every fetch and only kept in memory for that request.
/// - It is never refreshed here: rotating it could sign Claude Code out. When it has expired,
///   this runs `claude auth status` so Claude Code can refresh it itself; until it does,
///   fetching pauses and the Touch Bar goes gray as data ages.
/// - The endpoint is undocumented and may change; the status line stays as a fallback.
final class AccountUsageFetcher {
    static let defaultsKey = "fetchUsageFromAccount"
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let pollInterval: TimeInterval = 5 * 60
    /// Slightly under the poll interval so every scheduled poll may try once.
    private static let refreshInterval: TimeInterval = 4 * 60
    /// Only touched from the fetch's background work, which `inFlight` keeps to one at a time.
    private static var lastRefreshAttempt = Date.distantPast

    private let baseDir: URL
    private var timer: Timer?
    private var inFlight = false
    private var lastAttempt = Date.distantPast
    /// True while the last fetch was skipped because Claude Code's token had expired.
    private(set) var tokenExpired = false
    var onUpdate: (() -> Void)?

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.defaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.defaultsKey)
            newValue ? start() : stop()
        }
    }

    init(baseDir: URL) {
        self.baseDir = baseDir
    }

    func start() {
        guard isEnabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.fetch(ifOlderThan: 60)
        }
        fetch(ifOlderThan: 0)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tokenExpired = false
    }

    /// Also called when the Control Strip item is tapped, throttled by `ifOlderThan`.
    func fetch(ifOlderThan minimumAge: TimeInterval) {
        guard isEnabled, !inFlight, Date().timeIntervalSince(lastAttempt) >= minimumAge else { return }
        inFlight = true
        lastAttempt = Date()
        let baseDir = baseDir
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var expired = false
            if let snapshot = Self.fetchSnapshot(tokenExpired: &expired) {
                UsageRecorder.record(snapshot, source: "account", in: baseDir)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                if self.tokenExpired != expired {
                    self.tokenExpired = expired
                    self.onUpdate?()
                }
            }
        }
    }

    private static func fetchSnapshot(tokenExpired: inout Bool) -> UsageSnapshot? {
        var token = readToken(expired: &tokenExpired)
        if token == nil, tokenExpired, Date().timeIntervalSince(lastRefreshAttempt) >= refreshInterval {
            lastRefreshAttempt = Date()
            askClaudeCodeToRefresh()
            tokenExpired = false
            token = readToken(expired: &tokenExpired)
            NSLog("TouchBarCompanion: token \(token == nil ? "still expired" : "refreshed") after claude auth status")
        }
        guard let token else { return nil }

        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-touchbar-companion", forHTTPHeaderField: "User-Agent")

        var result: UsageSnapshot?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { done.signal() }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data else {
                NSLog("TouchBarCompanion: usage fetch failed (HTTP \(status)) \(error?.localizedDescription ?? "")")
                return
            }
            result = AccountUsage.parse(data, at: nowMs())
        }.resume()
        done.wait()
        return result
    }

    /// Runs `claude auth status`, which starts no session and calls no model, so Claude Code
    /// can refresh its own token the way it does on launch. Killed after 30 seconds.
    private static func askClaudeCodeToRefresh() {
        guard let claude = claudeExecutable() else {
            NSLog("TouchBarCompanion: claude CLI not found; cannot refresh the token")
            return
        }
        let process = Process()
        process.executableURL = claude
        process.arguments = ["auth", "status"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("TouchBarCompanion: cannot run \(claude.path): \(error.localizedDescription)")
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()
    }

    /// launchd gives no shell PATH, so look where Claude Code is usually installed,
    /// preferring the newest nvm Node version.
    private static func claudeExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        let nodeVersions = ((try? FileManager.default.contentsOfDirectory(atPath: nvm.path)) ?? [])
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        let candidates = [home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude"]
            + nodeVersions.map { nvm.appendingPathComponent("\($0)/bin/claude").path }
            + ["/usr/local/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// Reads Claude Code's OAuth token through `/usr/bin/security`, the same way Claude Code
    /// itself accesses the item, so no extra keychain permission is needed for this app.
    private static func readToken(expired: inout Bool) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard
            process.terminationStatus == 0,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else {
            NSLog("TouchBarCompanion: Claude Code credentials not found in the keychain")
            return nil
        }
        if let expiresAt = (oauth["expiresAt"] as? NSNumber)?.int64Value, expiresAt <= nowMs() + 60_000 {
            NSLog("TouchBarCompanion: Claude Code token expired; waiting for Claude Code to refresh it")
            expired = true
            return nil
        }
        return token
    }
}
