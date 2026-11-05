import Foundation

public func nowMs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}

public struct CompanionAction {
    public let id: String
    public let label: String
    /// Original JSON object, passed through untouched (e.g. `updated_permissions`).
    public let raw: [String: Any]
}

/// Mirrors `~/.claude-touchbar/state.json` written by `.claude/hooks/touchbar_hook.py`.
public struct CompanionState {
    public let requestId: String?
    public let sessionId: String
    public let kind: String
    public let context: String
    public let risk: String
    public let expiresAt: Int64
    public let actions: [CompanionAction]

    init(json: [String: Any]) {
        requestId = json["request_id"] as? String
        sessionId = json["session_id"] as? String ?? "unknown"
        kind = json["kind"] as? String ?? "unknown"
        context = json["context"] as? String ?? "Claude"
        risk = json["risk"] as? String ?? "unknown"
        expiresAt = (json["expires_at"] as? NSNumber)?.int64Value ?? 0
        actions = (json["actions"] as? [[String: Any]] ?? []).map {
            CompanionAction(
                id: $0["id"] as? String ?? "",
                label: $0["label"] as? String ?? "",
                raw: $0
            )
        }
    }

    public func isExpired(at now: Int64) -> Bool {
        expiresAt != 0 && expiresAt < now
    }
}

public enum CompanionStore {
    public static func baseDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let custom = environment["CLAUDE_TOUCHBAR_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-touchbar", isDirectory: true)
    }

    /// Returns the current state, or nil when missing, unreadable or expired.
    public static func activeState(in baseDir: URL, now: Int64 = nowMs()) -> CompanionState? {
        let url = baseDir.appendingPathComponent("state.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let state = CompanionState(json: json)
        return state.isExpired(at: now) ? nil : state
    }
}
