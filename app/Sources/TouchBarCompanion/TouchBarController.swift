import AppKit
import CompanionCore

extension NSTouchBarItem.Identifier {
    static let companionTray = Self("com.claude-touchbar-companion.tray")
    static let companionContext = Self("com.claude-touchbar-companion.context")
    static func companionAction(_ index: Int) -> Self {
        Self("com.claude-touchbar-companion.action.\(index)")
    }
}

/// Renders `[Context] [Action 1] [Action 2] [Action 3]`, same layout as the BTT setup.
///
/// The bar pops up by itself when a request needs an answer and steps aside again
/// afterwards, so the regular Touch Bar (Esc, etc.) is back the rest of the time.
/// The Control Strip "CC" button opens it manually.
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let maxActions = 3

    var onTap: ((_ index: Int, _ requestId: String?) -> Void)?

    private let touchBar = NSTouchBar()
    private let contextButton = NSButton(title: "", target: nil, action: nil)
    private let actionButtons: [NSButton]
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
        contextButton.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
        for button in actionButtons {
            button.target = self
            button.action = #selector(actionTapped(_:))
        }

        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [.companionContext]
    }

    func install() {
        let tray = NSCustomTouchBarItem(identifier: .companionTray)
        tray.view = NSButton(title: "CC", target: self, action: #selector(trayTapped))
        PrivateTouchBar.addToControlStrip(tray)
    }

    func render(_ state: CompanionState?) {
        let actions = Array((state?.actions ?? []).prefix(Self.maxActions))

        contextButton.attributedTitle = NSAttributedString(
            string: state?.context ?? "CC Ready",
            attributes: [.foregroundColor: NSColor.black, .font: NSFont.systemFont(ofSize: 15)]
        )
        for (button, action) in zip(actionButtons, actions) {
            button.title = action.label
            button.bezelColor = Self.color(forActionId: action.id)
        }
        touchBar.defaultItemIdentifiers =
            [.companionContext] + actions.indices.map { .companionAction($0) }

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

    /// Same colors as the BTT setup, keyed by meaning instead of slot position,
    /// so "No" is always red even when it is not the third button.
    private static func color(forActionId id: String) -> NSColor? {
        switch id {
        case "allow", "allow_once":
            return NSColor(srgbRed: 22 / 255, green: 163 / 255, blue: 74 / 255, alpha: 1)
        case "allow_session_edits", "allow_session_read":
            return NSColor(srgbRed: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1)
        case "deny":
            return NSColor(srgbRed: 220 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1)
        default:
            return nil
        }
    }

    @objc private func trayTapped() {
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
        if identifier == .companionContext {
            item.view = contextButton
            return item
        }
        guard let button = actionButtons.first(where: { .companionAction($0.tag) == identifier })
        else { return nil }
        item.view = button
        return item
    }
}
