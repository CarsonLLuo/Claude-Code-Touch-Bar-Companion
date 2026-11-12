import AppKit
import CompanionCore

/// Read-only rows for the menu bar menu, drawn as custom item views: AppKit grays out
/// disabled items whatever color their title has.
enum MenuRows {
    static let width: CGFloat = 300
    private static let inset: CGFloat = 14
    private static let baseSize = NSFont.menuFont(ofSize: 0).pointSize

    /// A colored dot and a bold title, with a smaller line underneath.
    static func header(title: String, subtitle: String, dotColor: NSColor) -> NSMenuItem {
        let dot = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 9, weight: .regular))!)
        dot.contentTintColor = dotColor
        let text = NSStackView(views: [
            label(title, size: baseSize + 1, weight: .semibold, truncates: true),
            label(subtitle, size: 11, color: .secondaryLabelColor, truncates: true),
        ])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        return item(height: 46, content: row([dot, text], spacing: 7))
    }

    static func section(_ title: String) -> NSMenuItem {
        item(height: 20, content: label(title, size: 11, weight: .semibold, color: .secondaryLabelColor))
    }

    static func note(_ text: String) -> NSMenuItem {
        item(height: 20, content: label(text, size: 11, color: .secondaryLabelColor))
    }

    /// `5h  resets in 56m ........ 78% left` over a full-width sector bar.
    static func usage(_ window: WindowUsage, reset: String, stale: Bool) -> NSMenuItem {
        let line = row([
            label(window.kind.label, weight: .semibold),
            label(reset, size: 11, color: .secondaryLabelColor),
            spacer(),
            label("\(UsageRenderer.remaining(window))%", weight: .semibold,
                  color: stale ? .secondaryLabelColor : .labelColor),
            label("left", size: 11, color: .secondaryLabelColor),
        ])
        let bar = UsageBarView(segments: window.segments, stale: stale)
        let block = NSStackView(views: [line, bar])
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 6
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalTo: block.widthAnchor),
            bar.widthAnchor.constraint(equalTo: block.widthAnchor),
            bar.heightAnchor.constraint(equalToConstant: 6),
        ])
        return item(height: 38, content: block)
    }

    /// `question ........ [answer] 13m`
    static func answer(context: String, label answer: String, ago: String) -> NSMenuItem {
        let time = label(ago, size: 11, color: .tertiaryLabelColor, mono: true)
        time.alignment = .right
        time.widthAnchor.constraint(equalToConstant: 26).isActive = true
        return item(height: 22, content: row([
            label(context, truncates: true), spacer(), PillView(label(answer, size: 11)), time,
        ]))
    }

    // MARK: - Building blocks

    private static func item(height: CGFloat, content: NSView) -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.autoresizingMask = [.width]
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        let item = NSMenuItem()
        item.view = container
        return item
    }

    private static func row(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.distribution = .fill
        row.spacing = spacing
        return row
    }

    private static func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        return view
    }

    private static func label(
        _ text: String, size: CGFloat = baseSize, weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor, mono: Bool = false, truncates: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = mono
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        if truncates {
            field.lineBreakMode = .byTruncatingTail
            field.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        }
        return field
    }
}

/// The usage sectors as one flat bar, colored like the Touch Bar battery.
final class UsageBarView: NSView {
    private let segments: [UsageSegment]
    private let stale: Bool

    init(segments: [UsageSegment], stale: Bool) {
        self.segments = segments
        self.stale = stale
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let spacing: CGFloat = 2
        let count = CGFloat(segments.count)
        let segmentWidth = (bounds.width - spacing * (count - 1)) / count

        for (index, segment) in segments.enumerated() {
            let cell = NSRect(
                x: CGFloat(index) * (segmentWidth + spacing), y: 0, width: segmentWidth, height: bounds.height)
            let path = NSBezierPath(roundedRect: cell, xRadius: 2, yRadius: 2)
            var ratio: Double?
            switch segment {
            case .future, .noData: break
            case .done(let value): ratio = value
            case .live(let value): ratio = value
            }
            (ratio.map { stale ? .tertiaryLabelColor : UsageRenderer.segmentColor(ratio: $0) } ?? .quaternaryLabelColor)
                .setFill()
            path.fill()
            if segment == .noData { UsageRenderer.drawHatch(in: cell, clip: path) }
            if case .live = segment {
                NSColor.labelColor.setStroke()
                let ring = NSBezierPath(roundedRect: cell.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
                ring.lineWidth = 1
                ring.stroke()
            }
        }
    }
}

/// A label on a small rounded tint.
final class PillView: NSView {
    init(_ label: NSTextField) {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var firstBaselineOffsetFromTop: CGFloat {
        subviews.first.map { 2 + $0.firstBaselineOffsetFromTop } ?? 0
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    }
}
