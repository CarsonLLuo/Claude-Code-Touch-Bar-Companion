import Foundation

/// Parses the response of `GET https://api.anthropic.com/api/oauth/usage`, the undocumented
/// endpoint behind Claude Code's `/usage` command.
public enum AccountUsage {
    public static func parse(_ data: Data, at now: Int64) -> UsageSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let fiveHour = window(json["five_hour"])
        let sevenDay = window(json["seven_day"])
        if fiveHour == nil, sevenDay == nil { return nil }
        return UsageSnapshot(at: now, fiveHour: fiveHour, sevenDay: sevenDay)
    }

    static func window(_ value: Any?) -> UsageWindow? {
        guard
            let json = value as? [String: Any],
            let utilization = (json["utilization"] as? NSNumber)?.doubleValue,
            let resets = json["resets_at"] as? String,
            let resetsAt = epochSeconds(resets)
        else { return nil }
        return UsageWindow(usedPercentage: utilization, resetsAt: resetsAt)
    }

    /// `2026-11-05T18:59:59.993843+00:00` -> 1793905200 (fraction rounded up to the next second).
    static func epochSeconds(_ text: String) -> Int64? {
        var trimmed = text
        var hasFraction = false
        if let dot = text.firstIndex(of: "."),
           let zone = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
        {
            hasFraction = true
            trimmed = String(text[..<dot]) + String(text[zone...])
        }
        guard let date = ISO8601DateFormatter().date(from: trimmed) else { return nil }
        return Int64(date.timeIntervalSince1970) + (hasFraction ? 1 : 0)
    }
}

/// Swift counterpart of `.claude/hooks/touchbar_statusline.py`: writes `usage.json` and
/// appends to `usage-history.jsonl` in the same format, so either source can feed the app.
public enum UsageRecorder {
    static let historyKeepMs: Int64 = 8 * 24 * 3600 * 1000
    static let historyPruneBytes = 512 * 1024

    public static func record(_ snapshot: UsageSnapshot, source: String, in baseDir: URL) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let usageURL = baseDir.appendingPathComponent("usage.json")
        let historyURL = baseDir.appendingPathComponent("usage-history.jsonl")

        var usage = (try? Data(contentsOf: usageURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let changed = UsageWindow(json: usage["five_hour"]) != snapshot.fiveHour
            || UsageWindow(json: usage["seven_day"]) != snapshot.sevenDay

        usage["updated_at"] = snapshot.at
        usage["five_hour"] = json(snapshot.fiveHour)
        usage["seven_day"] = json(snapshot.sevenDay)
        usage["source"] = source
        if let data = try? JSONSerialization.data(withJSONObject: usage, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: usageURL, options: .atomic)
        }

        guard changed else { return }
        let row: [String: Any] = [
            "at": snapshot.at, "five_hour": json(snapshot.fiveHour), "seven_day": json(snapshot.sevenDay),
        ]
        guard var line = try? JSONSerialization.data(withJSONObject: row, options: .sortedKeys) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: historyURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        } else {
            try? line.write(to: historyURL)
        }

        let size = (try? fileManager.attributesOfItem(atPath: historyURL.path)[.size] as? Int) ?? 0
        if size > historyPruneBytes { prune(historyURL, now: snapshot.at) }
    }

    private static func json(_ window: UsageWindow?) -> Any {
        guard let window else { return NSNull() }
        return ["used_percentage": window.usedPercentage, "resets_at": window.resetsAt]
    }

    private static func prune(_ url: URL, now: Int64) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let kept = text.split(separator: "\n").filter { line in
            guard
                let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let at = (row["at"] as? NSNumber)?.int64Value
            else { return false }
            return at >= now - historyKeepMs
        }
        try? (kept.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
