import AppKit
import CompanionCore

final class AppDelegate: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        reload()
        // Usage sectors, reset countdowns and staleness move with the clock.
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.reload()
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
        menu.addItem(accountUsageMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Touch Bar Companion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
