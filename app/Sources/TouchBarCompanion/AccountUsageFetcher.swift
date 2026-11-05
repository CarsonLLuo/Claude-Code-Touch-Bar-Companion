import Foundation
import CompanionCore

/// Opt-in: polls the endpoint behind Claude Code's `/usage` with the OAuth token Claude Code
/// keeps in the login keychain, and records the result like the status line does.
///
/// - The token is read on every fetch and only kept in memory for that request.
/// - It is never refreshed here: rotating it could sign Claude Code out. When it has expired,
///   fetching pauses until Claude Code refreshes it, and the Touch Bar goes gray as data ages.
/// - The endpoint is undocumented and may change; the status line stays as a fallback.
final class AccountUsageFetcher {
    static let defaultsKey = "fetchUsageFromAccount"
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let pollInterval: TimeInterval = 5 * 60

    private let baseDir: URL
    private var timer: Timer?
    private var inFlight = false
    private var lastAttempt = Date.distantPast

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
    }

    /// Also called when the Control Strip item is tapped, throttled by `ifOlderThan`.
    func fetch(ifOlderThan minimumAge: TimeInterval) {
        guard isEnabled, !inFlight, Date().timeIntervalSince(lastAttempt) >= minimumAge else { return }
        inFlight = true
        lastAttempt = Date()
        let baseDir = baseDir
        DispatchQueue.global(qos: .utility).async { [weak self] in
            if let snapshot = Self.fetchSnapshot() {
                UsageRecorder.record(snapshot, source: "account", in: baseDir)
            }
            DispatchQueue.main.async { self?.inFlight = false }
        }
    }

    private static func fetchSnapshot() -> UsageSnapshot? {
        guard let token = readToken() else { return nil }

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

    /// Reads Claude Code's OAuth token through `/usr/bin/security`, the same way Claude Code
    /// itself accesses the item, so no extra keychain permission is needed for this app.
    private static func readToken() -> String? {
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
            return nil
        }
        return token
    }
}
