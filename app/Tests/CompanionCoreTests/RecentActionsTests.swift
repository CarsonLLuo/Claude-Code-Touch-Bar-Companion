import Foundation
import Testing
@testable import CompanionCore

struct RecentActionsTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func writeLog(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n")
            .write(to: dir.appendingPathComponent("actions.jsonl"), atomically: true, encoding: .utf8)
    }

    @Test func missingFileGivesNothing() {
        #expect(RecentActions.load(in: dir, limit: 3).isEmpty)
    }

    @Test func newestFirstUpToLimitSkippingBadLines() throws {
        try writeLog([
            #"{"action":{"id":"allow","label":"Yes"},"clicked_at":1,"context":"Read a.md"}"#,
            #"{"action":{"id":"deny","label":"No"},"clicked_at":2,"context":"Delete tmp"}"#,
            "not json",
            #"{"action":{"id":"allow"},"clicked_at":3,"context":"No label"}"#,
            #"{"action":{"id":"screen","label":"On screen"},"clicked_at":4,"context":"Push"}"#,
        ])

        #expect(RecentActions.load(in: dir, limit: 2) == [
            RecentAction(clickedAt: 4, context: "Push", label: "On screen"),
            RecentAction(clickedAt: 2, context: "Delete tmp", label: "No"),
        ])
    }

    @Test func readsWhatActionResponderWrites() throws {
        let state: [String: Any] = [
            "request_id": "req-1", "session_id": "sess-1", "kind": "PermissionRequest",
            "context": "Edit foo.md", "risk": "low", "expires_at": nowMs() + 30_000,
            "actions": [["id": "allow", "label": "Yes"]],
        ]
        try JSONSerialization.data(withJSONObject: state)
            .write(to: dir.appendingPathComponent("state.json"))

        #expect(ActionResponder.perform(index: 0, expectedRequestId: "req-1", baseDir: dir, now: 42))
        #expect(RecentActions.load(in: dir, limit: 3) == [
            RecentAction(clickedAt: 42, context: "Edit foo.md", label: "Yes"),
        ])
    }
}
