import Foundation
import Testing
@testable import CompanionCore

struct UsageRecorderTests {
    let sample = Data("""
        {
          "five_hour": {"utilization": 40.0, "resets_at": "2026-11-05T18:59:59.993843+00:00", "locked_reason": null},
          "seven_day": {"utilization": 53.0, "resets_at": "2026-11-07T15:59:59.993866+00:00"},
          "seven_day_opus": null,
          "limits": [{"kind": "session", "percent": 40}]
        }
        """.utf8)

    @Test func parsesAccountUsageResponse() throws {
        let snapshot = try #require(AccountUsage.parse(sample, at: 1))
        #expect(snapshot.fiveHour == UsageWindow(usedPercentage: 40, resetsAt: 1_793_905_200))
        #expect(snapshot.sevenDay == UsageWindow(usedPercentage: 53, resetsAt: 1_794_067_200))
        #expect(AccountUsage.parse(Data("{\"five_hour\": null}".utf8), at: 1) == nil)
        #expect(AccountUsage.epochSeconds("2026-11-05T19:00:00Z") == 1_793_905_200)
    }

    @Test func writesUsageAndAppendsHistoryOnlyOnChange() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A status line run left context info behind; the recorder must keep it.
        try Data("{\"context_used_percentage\": 34}".utf8).write(to: dir.appendingPathComponent("usage.json"))

        let first = try #require(AccountUsage.parse(sample, at: 1_793_890_000_000))
        UsageRecorder.record(first, source: "account", in: dir)
        UsageRecorder.record(
            UsageSnapshot(at: 1_793_890_300_000, fiveHour: first.fiveHour, sevenDay: first.sevenDay),
            source: "account", in: dir)
        UsageRecorder.record(
            UsageSnapshot(
                at: 1_793_890_600_000,
                fiveHour: UsageWindow(usedPercentage: 42, resetsAt: 1_793_905_200), sevenDay: first.sevenDay),
            source: "account", in: dir)

        let history = try String(contentsOf: dir.appendingPathComponent("usage-history.jsonl"), encoding: .utf8)
        #expect(history.split(separator: "\n").count == 2)

        let usage = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("usage.json")))
                as? [String: Any])
        #expect(usage["context_used_percentage"] as? Int == 34)
        #expect(usage["source"] as? String == "account")

        let summary = try #require(UsageStore.load(in: dir, now: 1_793_890_600_000))
        #expect(summary.fiveHour?.remainingPercentage == 58)
        #expect(summary.sevenDay?.remainingPercentage == 47)
    }
}
