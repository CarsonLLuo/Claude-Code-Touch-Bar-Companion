import Foundation

/// Swift port of `scripts/btt_action.py`: turns a Touch Bar tap into a response file
/// that the hook picks up and returns to Claude Code as a structured decision.
public enum ActionResponder {
    static let blockedDirectActions: Set<String> = [
        "allow",
        "allow_once",
        "allow_session_edits",
        "allow_session_read",
        "always_allow",
        "run",
    ]

    /// - Parameter expectedRequestId: request id of the state the button was rendered from.
    ///   The tap is ignored if the state on disk has moved on since then.
    /// - Returns: true if the tap was accepted.
    @discardableResult
    public static func perform(
        index: Int,
        expectedRequestId: String?,
        baseDir: URL,
        now: Int64 = nowMs()
    ) -> Bool {
        guard
            let state = CompanionStore.activeState(in: baseDir, now: now),
            state.requestId == expectedRequestId,
            state.actions.indices.contains(index)
        else { return false }

        let action = state.actions[index]
        if ["high", "unknown"].contains(state.risk), blockedDirectActions.contains(action.id) {
            return false
        }

        var responseWritten = false
        if state.kind == "PermissionRequest", let requestId = state.requestId {
            var response: [String: Any] = [
                "request_id": requestId,
                "session_id": state.sessionId,
                "clicked_at": now,
                "kind": state.kind,
                "risk": state.risk,
                "action_id": action.id,
                "action_label": action.label,
            ]
            if let updated = action.raw["updated_permissions"] {
                response["updated_permissions"] = updated
            }
            let url = baseDir
                .appendingPathComponent("responses", isDirectory: true)
                .appendingPathComponent("\(requestId).json")
            responseWritten = writeJSON(response, to: url)
        }

        appendLog(
            [
                "clicked_at": now,
                "response_written": responseWritten,
                "session_id": state.sessionId,
                "kind": state.kind,
                "context": state.context,
                "risk": state.risk,
                "action": action.raw,
            ],
            baseDir: baseDir
        )
        return true
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func appendLog(_ row: [String: Any], baseDir: URL) {
        guard var line = try? JSONSerialization.data(withJSONObject: row, options: .sortedKeys)
        else { return }
        line.append(0x0A)

        let url = baseDir.appendingPathComponent("actions.jsonl")
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }
}
