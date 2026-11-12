import AppKit
import CompanionCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let baseDir = CompanionStore.baseDirectory()
    private lazy var touchBar = TouchBarController(
        icon: NSImage(contentsOf: baseDir.appendingPathComponent("icon.png")))
    private var statusItem: NSStatusItem?
    private var directorySource: DispatchSourceFileSystemObject?
    private var expiryTimer: Timer?
    private var minuteTimer: Timer?
    private lazy var accountUsage = AccountUsageFetcher(baseDir: baseDir)
    private let accountUsageMenuItem = NSMenuItem(
        title: "Fetch Usage from Claude Account", action: #selector(toggleAccountUsage), keyEquivalent: "")

    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // launchd and `pkill` stop the app with SIGTERM, which skips applicationWillTerminate.
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        setUpStatusItem()

        touchBar.onTap = { [weak self] index, requestId in
            guard let self else { return }
            ActionResponder.perform(index: index, expectedRequestId: requestId, baseDir: baseDir)
            reload()
        }
        touchBar.onTrayTap = { [weak self] in self?.accountUsage.fetch(ifOlderThan: 30) }
        touchBar.install()
        accountUsage.start()

        watchStateDirectory()
        recordFrontmostApp(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            self?.recordFrontmostApp(
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            self?.touchBar.reassertControlStrip()
        }
        reload()
        // Usage sectors, reset countdowns and staleness move with the clock.
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.reload()
            self?.touchBar.reassertControlStrip()
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "CC"
        let menu = NSMenu()
        accountUsageMenuItem.target = self
        accountUsageMenuItem.state = accountUsage.isEnabled ? .on : .off
        accountUsageMenuItem.toolTip =
            "Reads Claude Code's sign-in token from your keychain to check 5h / 7d usage every 5 minutes."
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt each time the menu opens, from the same files the Touch Bar reads.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let state = CompanionStore.activeState(in: baseDir)
        let waiting = ["PermissionRequest", "NextStepQuestion"].contains(state?.kind ?? "")
        menu.addItem(infoItem((waiting ? "Waiting for you: " : "") + (state?.context ?? "CC Ready"), primary: true))
        let lastEvent = (try? FileManager.default.attributesOfItem(
            atPath: baseDir.appendingPathComponent("last-event.json").path))?[.modificationDate] as? Date
        menu.addItem(infoItem(lastEvent.map { "Last hook event \(Self.ago($0))" }
            ?? "No hook events yet. Check the hook setup."))

        menu.addItem(.separator())
        menu.addItem(infoItem("Usage"))
        if let usage = UsageStore.load(in: baseDir) {
            for window in [usage.fiveHour, usage.sevenDay].compactMap({ $0 }) {
                let reset = window.kind == .fiveHour
                    ? "resets in \(UsageRenderer.resetText(window))" : "resets \(UsageRenderer.resetText(window))"
                let item = infoItem(
                    "\(window.kind.label)  \(UsageRenderer.remaining(window))% left · \(reset)", primary: true)
                item.image = UsageRenderer.batteryImage(window, stale: usage.isStale)
                menu.addItem(item)
            }
            if usage.isStale { menu.addItem(infoItem("Not updated for over 30 minutes")) }
        } else {
            menu.addItem(infoItem("No usage data yet"))
        }

        menu.addItem(.separator())
        menu.addItem(infoItem("Recent Touch Bar answers"))
        let recent = RecentActions.load(in: baseDir, limit: 3)
        for action in recent {
            let at = Date(timeIntervalSince1970: TimeInterval(action.clickedAt) / 1000)
            let context = action.context.count > 40 ? action.context.prefix(39) + "…" : action.context
            menu.addItem(infoItem("\(context) → \(action.label) · \(Self.ago(at))", primary: true))
        }
        if recent.isEmpty { menu.addItem(infoItem("None yet")) }

        menu.addItem(.separator())
        menu.addItem(accountUsageMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Touch Bar Companion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// A read-only row. Disabled items would gray out, so the color is set explicitly.
    private func infoItem(_ title: String, primary: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: primary ? 0 : NSFont.smallSystemFontSize),
            .foregroundColor: primary ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ])
        return item
    }

    private static func ago(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: min(date, Date()), relativeTo: Date())
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBar.uninstall()
    }

    /// Written on launch and on every app switch. The hook uses `app_pid` to check that this app
    /// is running before it puts Claude desktop's end-of-turn question on the Touch Bar.
    private func recordFrontmostApp(_ app: NSRunningApplication?) {
        let row: [String: Any] = [
            "bundle_id": app?.bundleIdentifier ?? "",
            "app_pid": ProcessInfo.processInfo.processIdentifier,
            "updated_at": nowMs(),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: row, options: .sortedKeys) {
            try? data.write(to: baseDir.appendingPathComponent("frontmost.json"), options: .atomic)
        }
    }

    @objc private func toggleAccountUsage() {
        accountUsage.isEnabled.toggle()
        accountUsageMenuItem.state = accountUsage.isEnabled ? .on : .off
    }

    /// The hook replaces state.json atomically (new inode), so watch the directory
    /// rather than the file itself.
    private func watchStateDirectory() {
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let fd = open(baseDir.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("TouchBarCompanion: cannot watch \(baseDir.path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        directorySource = source
    }

    private func reload() {
        let state = CompanionStore.activeState(in: baseDir)
        touchBar.render(state, usage: UsageStore.load(in: baseDir))

        // Fall back to "CC Ready" as soon as the state expires, even if no file changes.
        expiryTimer?.invalidate()
        if let state, state.expiresAt > 0 {
            let delay = max(0, Double(state.expiresAt - nowMs()) / 1000) + 0.05
            expiryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) {
                [weak self] _ in self?.reload()
            }
        }
    }
}

// Only one copy may own the Touch Bar. A second launch (say, a manual run while launchd
// keeps one alive) exits quietly. The lock is released automatically when the process ends.
let lockDirectory = CompanionStore.baseDirectory()
try? FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
let lockDescriptor = open(lockDirectory.appendingPathComponent("app.lock").path, O_CREAT | O_RDWR, 0o644)
if lockDescriptor < 0 || flock(lockDescriptor, LOCK_EX | LOCK_NB) != 0 {
    FileHandle.standardError.write(Data("TouchBarCompanion is already running.\n".utf8))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
