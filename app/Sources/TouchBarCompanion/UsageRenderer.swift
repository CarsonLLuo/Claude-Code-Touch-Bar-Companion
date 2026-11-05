import AppKit
import CompanionCore

/// Draws a usage window as `5h [segmented battery] 77 2h 10m` into a single image,
/// so it can sit in any Touch Bar button (including the Control Strip).
enum UsageRenderer {
    static let green = NSColor(srgbRed: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
    static let yellow = NSColor(srgbRed: 1, green: 0xD6 / 255, blue: 0x0A / 255, alpha: 1)
    static let red = NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
    private static let empty = NSColor(white: 0.2, alpha: 1)
    private static let staleFill = NSColor(white: 0.45, alpha: 1)
    private static let outline = NSColor(white: 0.78, alpha: 1)
    private static let secondaryText = NSColor(white: 0.62, alpha: 1)

    /// The remaining-percentage number turns yellow / red as the window gets tight.
    static func numberColor(_ usage: WindowUsage, stale: Bool) -> NSColor {
        if stale { return secondaryText }
        switch usage.severity {
        case .ok: return .white
        case .warning: return yellow
        case .critical: return red
        }
    }

    static func segmentColor(ratio: Double) -> NSColor {
        ratio <= 1 ? green : ratio <= 1.5 ? yellow : red
    }

    static func image(
        _ usage: WindowUsage,
        batteryWidth: CGFloat,
        number: String,
        trailing: String? = nil,
        stale: Bool,
        charging: Bool = false
    ) -> NSImage {
        let height: CGFloat = 22
        let gap: CGFloat = 5
        let label = text(usage.kind.label, size: 11, color: secondaryText)
        let value = text(number, size: 13, weight: .medium, color: numberColor(usage, stale: stale))
        let tail = trailing.map { text($0, size: 12, color: secondaryText) }
        let bolt = charging ? boltImage() : nil

        var width = label.size().width + gap + batteryWidth + 3 + gap + value.size().width
        if let tail { width += 6 + tail.size().width }
        if let bolt { width += 2 + bolt.size.width }

        return NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            draw(label, at: &x, height: height)
            x += gap
            drawBattery(usage.segments, in: NSRect(x: x, y: (height - 15) / 2, width: batteryWidth, height: 15), stale: stale)
            x += batteryWidth + 3 + gap
            draw(value, at: &x, height: height)
            if let tail {
                x += 6
                draw(tail, at: &x, height: height)
            }
            if let bolt {
                x += 2
                bolt.draw(in: NSRect(x: x, y: (height - bolt.size.height) / 2, width: bolt.size.width, height: bolt.size.height))
            }
            return true
        }
    }

    /// Control Strip slots are only about 50pt wide, so stack the text above a thin battery.
    static func compactImage(_ usage: WindowUsage, stale: Bool, charging: Bool) -> NSImage {
        let size = NSSize(width: 46, height: 26)
        let line = NSMutableAttributedString(attributedString: text(usage.kind.label + " ", size: 10, color: secondaryText))
        line.append(text(remaining(usage), size: 12, weight: .medium, color: numberColor(usage, stale: stale)))
        let bolt = charging ? boltImage(pointSize: 9) : nil

        return NSImage(size: size, flipped: false) { _ in
            let textSize = line.size()
            let boltWidth = bolt.map { $0.size.width + 1 } ?? 0
            let x = (size.width - textSize.width - boltWidth) / 2
            line.draw(at: NSPoint(x: x, y: size.height - textSize.height))
            if let bolt {
                bolt.draw(in: NSRect(
                    x: x + textSize.width + 1, y: size.height - textSize.height + (textSize.height - bolt.size.height) / 2,
                    width: bolt.size.width, height: bolt.size.height))
            }
            drawBattery(usage.segments, in: NSRect(x: 0, y: 1, width: size.width - 3, height: 9), stale: stale, thin: true)
            return true
        }
    }

    private static func drawBattery(_ segments: [UsageSegment], in rect: NSRect, stale: Bool, thin: Bool = false) {
        let border: CGFloat = thin ? 1 : 1.5
        let body = NSBezierPath(roundedRect: rect.insetBy(dx: border / 2, dy: border / 2), xRadius: thin ? 2 : 3.5, yRadius: thin ? 2 : 3.5)
        body.lineWidth = border
        outline.setStroke()
        body.stroke()
        outline.setFill()
        let nubHeight: CGFloat = thin ? 4 : 6
        NSBezierPath(
            roundedRect: NSRect(x: rect.maxX + 1, y: rect.midY - nubHeight / 2, width: 2, height: nubHeight), xRadius: 1, yRadius: 1
        ).fill()

        let inner = rect.insetBy(dx: thin ? 2 : 3, dy: thin ? 2 : 3)
        let spacing: CGFloat = thin ? 1 : 1.5
        let count = CGFloat(segments.count)
        let segmentWidth = (inner.width - spacing * (count - 1)) / count

        for (index, segment) in segments.enumerated() {
            let cell = NSRect(
                x: inner.minX + CGFloat(index) * (segmentWidth + spacing), y: inner.minY,
                width: segmentWidth, height: inner.height)
            let path = NSBezierPath(roundedRect: cell, xRadius: 1.2, yRadius: 1.2)

            switch segment {
            case .future:
                empty.setFill()
                path.fill()
            case .noData:
                empty.setFill()
                path.fill()
                drawHatch(in: cell, clip: path)
            case .done(let ratio):
                (stale ? staleFill : segmentColor(ratio: ratio)).setFill()
                path.fill()
            case .live(let ratio):
                (ratio.map { stale ? staleFill : segmentColor(ratio: $0) } ?? empty).setFill()
                path.fill()
                NSColor.white.setStroke()
                let ring = NSBezierPath(roundedRect: cell.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.2, yRadius: 1.2)
                ring.lineWidth = 1
                ring.stroke()
            }
        }
    }

    private static func drawHatch(in rect: NSRect, clip: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        NSColor(white: 0.42, alpha: 1).setStroke()
        let stripes = NSBezierPath()
        stripes.lineWidth = 1
        var x = rect.minX - rect.height
        while x < rect.maxX {
            stripes.move(to: NSPoint(x: x, y: rect.minY))
            stripes.line(to: NSPoint(x: x + rect.height, y: rect.maxY))
            x += 3
        }
        stripes.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func boltImage(pointSize: CGFloat = 12) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(paletteColors: [yellow]))
        return NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Refills soon")?
            .withSymbolConfiguration(config)
    }

    private static func text(
        _ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor
    ) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        )
    }

    private static func draw(_ string: NSAttributedString, at x: inout CGFloat, height: CGFloat) {
        let size = string.size()
        string.draw(at: NSPoint(x: x, y: (height - size.height) / 2))
        x += size.width
    }

    // MARK: - Labels

    static func remaining(_ usage: WindowUsage) -> String {
        "\(Int(usage.remainingPercentage.rounded()))"
    }

    /// 5h: countdown ("2h 10m"); 7d: weekday it resets ("Mon").
    static func resetText(_ usage: WindowUsage, now: Date = Date()) -> String {
        let resets = Date(timeIntervalSince1970: TimeInterval(usage.resetsAt))
        if usage.kind == .sevenDay {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE"
            return formatter.string(from: resets)
        }
        let minutes = max(0, Int(resets.timeIntervalSince(now) / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    static func refillsSoon(_ usage: WindowUsage, now: Date = Date()) -> Bool {
        usage.kind == .fiveHour && TimeInterval(usage.resetsAt) - now.timeIntervalSince1970 <= 15 * 60
    }
}
