import AppKit

/// Undocumented Touch Bar APIs (same ones MTMR / Pock use) that let a background app
/// show a system-wide Touch Bar and put an item in the Control Strip.
/// Resolved at runtime, so nothing links against the private framework.
enum PrivateTouchBar {
    private typealias SetPresenceFn = @convention(c) (NSString, Bool) -> Void

    private static let setControlStripPresence: SetPresenceFn? = {
        let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        guard
            let handle = dlopen(path, RTLD_LAZY),
            let symbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier")
        else { return nil }
        return unsafeBitCast(symbol, to: SetPresenceFn.self)
    }()

    static func addToControlStrip(_ item: NSTouchBarItem) {
        callClassMethod(on: NSTouchBarItem.self, "addSystemTrayItem:", item)
        setControlStripPresence?(item.identifier.rawValue as NSString, true)
    }

    static func removeFromControlStrip(_ item: NSTouchBarItem) {
        setControlStripPresence?(item.identifier.rawValue as NSString, false)
        callClassMethod(on: NSTouchBarItem.self, "removeSystemTrayItem:", item)
    }

    static func present(_ touchBar: NSTouchBar, trayIdentifier: NSTouchBarItem.Identifier) {
        callClassMethod(
            on: NSTouchBar.self,
            "presentSystemModalTouchBar:systemTrayItemIdentifier:",
            touchBar,
            trayIdentifier.rawValue as NSString
        )
    }

    static func minimize(_ touchBar: NSTouchBar) {
        callClassMethod(on: NSTouchBar.self, "minimizeSystemModalTouchBar:", touchBar)
    }

    private static func callClassMethod(
        on cls: AnyClass, _ name: String, _ first: Any, _ second: Any? = nil
    ) {
        let selector = NSSelectorFromString(name)
        guard let object = cls as AnyObject as? NSObjectProtocol, object.responds(to: selector)
        else {
            NSLog("TouchBarCompanion: private API \(name) unavailable")
            return
        }
        if let second {
            _ = object.perform(selector, with: first, with: second)
        } else {
            _ = object.perform(selector, with: first)
        }
    }
}
