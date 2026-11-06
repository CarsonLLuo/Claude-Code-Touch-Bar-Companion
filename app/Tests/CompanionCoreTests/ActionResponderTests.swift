import Foundation
import Testing
@testable import CompanionCore

struct ActionResponderTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func writeState(
        risk: String = "low", kind: String = "PermissionRequest", expiresAt: Int64 = nowMs() + 30_000
    ) throws {
        let state: [String: Any] = [
            "version": 1,
            "request_id": "req-1",
            "session_id": "sess-1",
            "kind": kind,
            "context": "Edit foo.md",
            "risk": risk,
            "expires_at": expiresAt,
            "actions": [
                ["id": "allow", "label": "Yes"],
                [
                    "id": "allow_session_edits", "label": "All edits",
                    "updated_permissions": [
                        ["type": "setMode", "mode": "acceptEdits", "destination": "session"]
                    ],
                ],
                ["id": "deny", "label": "No"],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: state)
        try data.write(to: dir.appendingPathComponent("state.json"))
    }

    func readResponse() throws -> [String: Any]? {
        let url = dir.appendingPathComponent("responses/req-1.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @Test func writesResponseWithUpdatedPermissions() throws {
        try writeState()
        #expect(ActionResponder.perform(index: 1, expectedRequestId: "req-1", baseDir: dir))

        let response = try #require(try readResponse())
        #expect(response["request_id"] as? String == "req-1")
        #expect(response["action_id"] as? String == "allow_session_edits")
        let updated = try #require(response["updated_permissions"] as? [[String: Any]])
        #expect(updated.first?["mode"] as? String == "acceptEdits")

        let log = try String(contentsOf: dir.appendingPathComponent("actions.jsonl"), encoding: .utf8)
        #expect(log.contains("\"response_written\":true"))
    }

    @Test func answersNextStepQuestion() throws {
        try writeState(kind: "NextStepQuestion")
        #expect(ActionResponder.perform(index: 2, expectedRequestId: "req-1", baseDir: dir))
        #expect(try readResponse()?["action_label"] as? String == "No")
    }

    @Test func ignoresStaleButton() throws {
        try writeState()
        #expect(!ActionResponder.perform(index: 0, expectedRequestId: "req-old", baseDir: dir))
        #expect(try readResponse() == nil)
    }

    @Test func ignoresExpiredState() throws {
        try writeState(expiresAt: nowMs() - 1)
        #expect(!ActionResponder.perform(index: 0, expectedRequestId: "req-1", baseDir: dir))
        #expect(try readResponse() == nil)
    }

    @Test func blocksAllowOnHighRisk() throws {
        try writeState(risk: "high")
        #expect(!ActionResponder.perform(index: 0, expectedRequestId: "req-1", baseDir: dir))
        #expect(ActionResponder.perform(index: 2, expectedRequestId: "req-1", baseDir: dir))
        #expect(try readResponse()?["action_id"] as? String == "deny")
    }
}
