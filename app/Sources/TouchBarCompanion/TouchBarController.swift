import AppKit
import CompanionCore

extension NSTouchBarItem.Identifier {
    static let companionTray = Self("com.claude-touchbar-companion.tray")
    static let companionContext = Self("com.claude-touchbar-companion.context")
    static let companionUsageBadge = Self("com.claude-touchbar-companion.usage.badge")
    static let companionUsageFiveHour = Self("com.claude-touchbar-companion.usage.5h")
    static let companionUsageSevenDay = Self("com.claude-touchbar-companion.usage.7d")
    static func companionAction(_ index: Int) -> Self {
        Self("com.claude-touchbar-companion.action.\(index)")
    }
}

/// Renders `[Context] [Action 1] [Action 2] [Action 3]`, same layout as the BTT setup.
///
/// The bar pops up by itself when a request needs an answer and steps aside again
/// afterwards, so the regular Touch Bar (Esc, etc.) is back the rest of the time.
/// The Control Strip "CC" button opens it manually.
///
/// Usage follows three tiers: the Control Strip always shows the tighter window as a
/// segmented battery; the manually opened bar shows both windows; a permission request
/// only gets a low-battery badge when the 5h window is almost empty.
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let maxActions = 3

    var onTap: ((_ index: Int, _ requestId: String?) -> Void)?
    var onTrayTap: (() -> Void)?

    private let touchBar = NSTouchBar()
    private let contextButton = NSButton(title: "", target: nil, action: nil)
    private let actionButtons: [NSButton]
    private let trayButton = NSButton(title: "CC", target: nil, action: nil)
    private var trayItem: NSCustomTouchBarItem?
    private let fiveHourButton = NSButton(title: "", target: nil, action: nil)
    private let sevenDayButton = NSButton(title: "", target: nil, action: nil)
    private let badgeButton = NSButton(title: "", target: nil, action: nil)
    private lazy var contextMaxWidth = contextButton.widthAnchor.constraint(lessThanOrEqualToConstant: 400)
    private var renderedRequestId: String?
    private var autoPresented = false

    /// - Parameter icon: shown before the context text (the BTT setup used the Claude logo).
    init(icon: NSImage?) {
        actionButtons = (0..<Self.maxActions).map { index in
            let button = NSButton(title: "", target: nil, action: nil)
            button.tag = index
            return button
        }
        super.init()

        icon?.size = NSSize(width: 22, height: 22)
        contextButton.image = icon
        contextButton.imagePosition = .imageLeading
        contextButton.bezelColor = .white
        contextButton.cell?.lineBreakMode = .byTruncatingTail
        contextMaxWidth.isActive = true
        for button in [trayButton, fiveHourButton, sevenDayButton] {
            button.imagePosition = .imageOnly
        }
        badgeButton.bezelColor = UsageRenderer.red
        badgeButton.imagePosition = .imageLeading
        badgeButton.image = NSImage(systemSymbolName: "battery.0", accessibilityDescription: "Low 5h usage left")
        for button in actionButtons {
            button.target = self
            button.action = #selector(actionTapped(_:))
        }

        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [.companionContext]
    }

    func install() {
        let tray = NSCustomTouchBarItem(identifier: .companionTray)
        trayButton.target = self
        trayButton.action = #selector(trayTapped)
        tray.view = trayButton
        PrivateTouchBar.addToControlStrip(tray)
        trayItem = tray
    }

    /// Without this, a killed process can leave a dead `CC` item behind in the Control Strip.
    func uninstall() {
        PrivateTouchBar.minimize(touchBar)
        if let trayItem { PrivateTouchBar.removeFromControlStrip(trayItem) }
        trayItem = nil
    }

    func render(_ state: CompanionState?, usage: UsageSummary?) {
        let actions = Array((state?.actions ?? []).prefix(Self.maxActions))
        let usageItems = renderUsage(usage, requestPending: !actions.isEmpty)

        contextButton.attributedTitle = NSAttributedString(
            string: state?.context ?? "CC Ready",
            attributes: [.foregroundColor: NSColor.black, .font: NSFont.systemFont(ofSize: 15)]
        )
        for (button, action) in zip(actionButtons, actions) {
            button.title = action.label
            button.bezelColor = Self.color(forActionId: action.id)
        }
        // Both usage batteries need the room: shrink the context pill to its logo.
        let logoOnly = actions.isEmpty && !usageItems.isEmpty && contextButton.image != nil
        contextButton.imagePosition = logoOnly ? .imageOnly : .imageLeading
        contextMaxWidth.constant = actions.isEmpty && !usageItems.isEmpty ? 180 : 400
        touchBar.defaultItemIdentifiers =
            [.companionContext] + usageItems + actions.indices.map { .companionAction($0) }

        let previousRequestId = renderedRequestId
        renderedRequestId = state?.requestId

        if !actions.isEmpty {
            if !autoPresented || previousRequestId != renderedRequestId {
                PrivateTouchBar.present(touchBar, trayIdentifier: .companionTray)
                autoPresented = true
            }
        } else if autoPresented {
            PrivateTouchBar.minimize(touchBar)
            autoPresented = false
        }
    }

    /// Updates the Control Strip and returns the usage items to show in the bar.
    private func renderUsage(_ usage: UsageSummary?, requestPending: Bool) -> [NSTouchBarItem.Identifier] {
        guard let usage, let binding = usage.binding else {
            trayButton.image = nil
            trayButton.title = "CC"
            trayButton.imagePosition = .noImage
            return []
        }

        trayButton.title = ""
        trayButton.imagePosition = .imageOnly
        trayButton.image = UsageRenderer.compactImage(
            binding, stale: usage.isStale, charging: !usage.isStale && UsageRenderer.refillsSoon(binding))

        if requestPending {
            guard let fiveHour = usage.fiveHour, fiveHour.severity == .critical, !usage.isStale else { return [] }
            badgeButton.title = "\(UsageRenderer.remaining(fiveHour))%"
            return [.companionUsageBadge]
        }

        var items: [NSTouchBarItem.Identifier] = []
        for (window, button, identifier) in [
            (usage.fiveHour, fiveHourButton, NSTouchBarItem.Identifier.companionUsageFiveHour),
            (usage.sevenDay, sevenDayButton, .companionUsageSevenDay),
        ] {
            guard let window else { continue }
            button.image = UsageRenderer.image(
                window, batteryWidth: 130, number: "\(UsageRenderer.remaining(window))%",
                trailing: UsageRenderer.resetText(window), stale: usage.isStale,
                charging: !usage.isStale && UsageRenderer.refillsSoon(window))
            items.append(identifier)
        }
        return items
    }

    /// Same colors as the BTT setup, keyed by meaning instead of slot position,
    /// so "No" is always red even when it is not the third button.
    private static func color(forActionId id: String) -> NSColor? {
        switch id {
        case "allow", "allow_once":
            return NSColor(srgbRed: 22 / 255, green: 163 / 255, blue: 74 / 255, alpha: 1)
        case "allow_session_edits", "allow_session_read", "choice_0":
            return NSColor(srgbRed: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1)
        case "deny":
            return NSColor(srgbRed: 220 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1)
        default:
            return nil
        }
    }

    @objc private func trayTapped() {
        onTrayTap?()
        autoPresented = false
        PrivateTouchBar.present(touchBar, trayIdentifier: .companionTray)
    }

    @objc private func actionTapped(_ sender: NSButton) {
        onTap?(sender.tag, renderedRequestId)
    }

    func touchBar(
        _ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let fixedViews: [NSTouchBarItem.Identifier: NSView] = [
            .companionContext: contextButton,
            .companionUsageBadge: badgeButton,
            .companionUsageFiveHour: fiveHourButton,
            .companionUsageSevenDay: sevenDayButton,
        ]
        if let view = fixedViews[identifier] {
            item.view = view
            return item
        }
        guard let button = actionButtons.first(where: { .companionAction($0.tag) == identifier })
        else { return nil }
        item.view = button
        return item
    }
}
