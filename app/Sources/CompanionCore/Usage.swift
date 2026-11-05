import Foundation

/// One rate-limit window as reported by Claude Code's status line (`rate_limits.*`).
public struct UsageWindow: Equatable {
    public let usedPercentage: Double
    /// Unix epoch seconds.
    public let resetsAt: Int64

    public init(usedPercentage: Double, resetsAt: Int64) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    init?(json: Any?) {
        guard
            let json = json as? [String: Any],
            let used = (json["used_percentage"] as? NSNumber)?.doubleValue,
            let resetsAt = (json["resets_at"] as? NSNumber)?.int64Value
        else { return nil }
        self.init(usedPercentage: used, resetsAt: resetsAt)
    }
}

public struct UsageSnapshot {
    /// Unix epoch milliseconds.
    public let at: Int64
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?

    public init(at: Int64, fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        self.at = at
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    func window(_ kind: UsageKind) -> UsageWindow? {
        kind == .fiveHour ? fiveHour : sevenDay
    }
}

public enum UsageKind {
    case fiveHour, sevenDay

    public var label: String { self == .fiveHour ? "5h" : "7d" }
    var lengthMs: Int64 { self == .fiveHour ? 5 * 3600 * 1000 : 7 * 24 * 3600 * 1000 }
    /// 5h: 30-minute sectors, 7d: one sector per day.
    var segmentCount: Int { self == .fiveHour ? 10 : 7 }
}

/// One F1-style minisector. `ratio` is the usage in that slice divided by its fair share
/// (100% / segment count): <= 1 is under pace.
public enum UsageSegment: Equatable {
    case future
    case noData
    case live(ratio: Double?)
    case done(ratio: Double)
}

public enum UsageSeverity: Int, Comparable {
    case ok, warning, critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct WindowUsage {
    public let kind: UsageKind
    public let remainingPercentage: Double
    /// Unix epoch seconds.
    public let resetsAt: Int64
    public let segments: [UsageSegment]
    public let severity: UsageSeverity
}

public struct UsageSummary {
    public let fiveHour: WindowUsage?
    public let sevenDay: WindowUsage?
    public let isStale: Bool

    /// The tighter window, shown in the Control Strip. Ties go to 5h.
    public var binding: WindowUsage? {
        guard let fiveHour else { return sevenDay }
        guard let sevenDay else { return fiveHour }
        return sevenDay.severity > fiveHour.severity ? sevenDay : fiveHour
    }
}

public enum UsageStore {
    static let staleAfterMs: Int64 = 30 * 60 * 1000
    /// Snapshots whose `resets_at` differs by more than this belong to another window.
    static let sameWindowToleranceSeconds: Int64 = 300

    /// Reads `usage.json` and `usage-history.jsonl` written by `touchbar_statusline.py`.
    public static func load(in baseDir: URL, now: Int64 = nowMs()) -> UsageSummary? {
        guard
            let data = try? Data(contentsOf: baseDir.appendingPathComponent("usage.json")),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let updatedAt = (json["updated_at"] as? NSNumber)?.int64Value
        else { return nil }

        let current = UsageSnapshot(
            at: updatedAt,
            fiveHour: UsageWindow(json: json["five_hour"]),
            sevenDay: UsageWindow(json: json["seven_day"])
        )
        let historyText = (try? String(
            contentsOf: baseDir.appendingPathComponent("usage-history.jsonl"), encoding: .utf8)) ?? ""
        let history = historyText.split(separator: "\n").compactMap { line -> UsageSnapshot? in
            guard
                let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let at = (row["at"] as? NSNumber)?.int64Value
            else { return nil }
            return UsageSnapshot(
                at: at,
                fiveHour: UsageWindow(json: row["five_hour"]),
                sevenDay: UsageWindow(json: row["seven_day"])
            )
        }
        return summarize(current: current, history: history, now: now)
    }

    public static func summarize(
        current: UsageSnapshot, history: [UsageSnapshot], now: Int64
    ) -> UsageSummary? {
        let fiveHour = windowUsage(.fiveHour, current: current, history: history, now: now)
        let sevenDay = windowUsage(.sevenDay, current: current, history: history, now: now)
        if fiveHour == nil, sevenDay == nil { return nil }
        return UsageSummary(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            isStale: now - current.at > staleAfterMs
        )
    }

    static func windowUsage(
        _ kind: UsageKind, current: UsageSnapshot, history: [UsageSnapshot], now: Int64
    ) -> WindowUsage? {
        // Claude Code drops a window once it resets; a reset window is unknown, not full.
        guard let window = current.window(kind), window.resetsAt * 1000 > now else { return nil }

        let endMs = window.resetsAt * 1000
        let startMs = endMs - kind.lengthMs
        let used = min(max(window.usedPercentage, 0), 100)
        let elapsed = Double(now - startMs) / Double(kind.lengthMs)

        var severity: UsageSeverity
        let remaining = 100 - used
        switch kind {
        case .fiveHour:
            severity = remaining <= 10 ? .critical : remaining <= 30 ? .warning : .ok
        case .sevenDay:
            // Pace only counts after the first day; early in the week any use looks "ahead".
            let aheadOfPace = elapsed >= 1.0 / 7 && used > elapsed * 100
            severity = remaining <= 5 ? .critical : (remaining <= 20 || aheadOfPace) ? .warning : .ok
        }

        let points = (history + [current])
            .compactMap { snapshot -> (at: Int64, used: Double)? in
                guard
                    let w = snapshot.window(kind),
                    abs(w.resetsAt - window.resetsAt) <= sameWindowToleranceSeconds,
                    snapshot.at >= startMs, snapshot.at <= now
                else { return nil }
                return (snapshot.at, w.usedPercentage)
            }
            .sorted { $0.at < $1.at }

        return WindowUsage(
            kind: kind,
            remainingPercentage: remaining,
            resetsAt: window.resetsAt,
            segments: segments(kind, startMs: startMs, points: points, now: now),
            severity: severity
        )
    }

    /// Each snapshot's increase is booked to the sector it was recorded in. The first snapshot
    /// of a window only counts from zero if it falls in the first sector; later on it is just a
    /// baseline, because there is no telling when that earlier usage happened.
    static func segments(
        _ kind: UsageKind, startMs: Int64, points: [(at: Int64, used: Double)], now: Int64
    ) -> [UsageSegment] {
        let count = kind.segmentCount
        let segmentMs = kind.lengthMs / Int64(count)
        let fairShare = 100 / Double(count)

        var deltas = [Double?](repeating: nil, count: count)
        var previous: Double?
        for point in points {
            let index = min(count - 1, max(0, Int((point.at - startMs) / segmentMs)))
            if previous == nil, index > 0 {
                previous = point.used
                continue
            }
            deltas[index] = (deltas[index] ?? 0) + max(0, point.used - (previous ?? 0))
            previous = point.used
        }

        return (0..<count).map { index in
            let segmentStart = startMs + Int64(index) * segmentMs
            if segmentStart > now { return .future }
            if now < segmentStart + segmentMs { return .live(ratio: deltas[index].map { $0 / fairShare }) }
            if let delta = deltas[index] { return .done(ratio: delta / fairShare) }
            return .noData
        }
    }
}
