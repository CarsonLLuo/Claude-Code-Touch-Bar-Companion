import Foundation

/// One Touch Bar tap, as logged by `ActionResponder` in `actions.jsonl`.
public struct RecentAction: Equatable {
    /// Unix epoch milliseconds.
    public let clickedAt: Int64
    public let context: String
    public let label: String
}

public enum RecentActions {
    /// The newest `limit` taps, newest first. A missing file or unreadable lines are skipped,
    /// and so are repeats of a newer tap (same session, context and answer).
    public static func load(in baseDir: URL, limit: Int) -> [RecentAction] {
        guard let text = try? String(
            contentsOf: baseDir.appendingPathComponent("actions.jsonl"), encoding: .utf8)
        else { return [] }

        var result: [RecentAction] = []
        var seen = Set<[String]>()
        for line in text.split(separator: "\n").reversed() {
            if result.count >= limit { break }
            guard
                let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let clickedAt = (row["clicked_at"] as? NSNumber)?.int64Value,
                let label = (row["action"] as? [String: Any])?["label"] as? String
            else { continue }
            let context = row["context"] as? String ?? ""
            guard seen.insert([row["session_id"] as? String ?? "", context, label]).inserted else { continue }
            result.append(RecentAction(
                clickedAt: clickedAt, context: context, label: label))
        }
        return result
    }
}
