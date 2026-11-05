import AppKit
import CompanionCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let baseDir = CompanionStore.baseDirectory()
    private lazy var touchBar = TouchBarController(
        icon: NSImage(contentsOf: baseDir.appendingPathComponent("icon.png")))
    private var statusItem: NSStatusItem?
    private var directorySource: DispatchSourceFileSystemObject?
    private var expiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        touchBar.onTap = { [weak self] index, requestId in
            guard let self else { return }
            ActionResponder.perform(index: index, expectedRequestId: requestId, baseDir: baseDir)
            reload()
        }
        touchBar.install()

        watchStateDirectory()
        reload()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "CC"
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Touch Bar Companion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
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
        touchBar.render(state)

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
