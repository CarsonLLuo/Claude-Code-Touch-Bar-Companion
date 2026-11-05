import Foundation
import Testing
@testable import CompanionCore

struct UsageTests {
    let minute: Int64 = 60 * 1000
    let hour: Int64 = 3600 * 1000
    let day: Int64 = 24 * 3600 * 1000
    let start: Int64 = 1_800_000_000_000

    func fiveHour(_ used: Double) -> UsageWindow {
        UsageWindow(usedPercentage: used, resetsAt: (start + 5 * hour) / 1000)
    }

    func sevenDay(_ used: Double) -> UsageWindow {
        UsageWindow(usedPercentage: used, resetsAt: (start + 7 * day) / 1000)
    }

    @Test func booksDeltasIntoMinisectors() {
        let now = start + 2 * hour + 45 * minute
        let history = [
            UsageSnapshot(at: start + 10 * minute, fiveHour: fiveHour(6), sevenDay: nil),
            UsageSnapshot(at: start + 40 * minute, fiveHour: fiveHour(14), sevenDay: nil),
            UsageSnapshot(at: start + 100 * minute, fiveHour: fiveHour(30), sevenDay: nil),
            // Belongs to the previous 5h window and must be ignored.
            UsageSnapshot(
                at: start + 50 * minute,
                fiveHour: UsageWindow(usedPercentage: 90, resetsAt: start / 1000), sevenDay: nil),
        ]
        let current = UsageSnapshot(at: start + 100 * minute, fiveHour: fiveHour(30), sevenDay: nil)
        let usage = UsageStore.summarize(current: current, history: history, now: now)!.fiveHour!

        #expect(usage.remainingPercentage == 70)
        #expect(usage.segments.count == 10)
        #expect(usage.segments[0] == .done(ratio: 0.6))
        #expect(usage.segments[1] == .done(ratio: 0.8))
        #expect(usage.segments[2] == .noData)
        #expect(usage.segments[3] == .done(ratio: 1.6))
        #expect(usage.segments[4] == .noData)
        #expect(usage.segments[5] == .live(ratio: nil))
        #expect(usage.segments[6...].allSatisfy { $0 == .future })
    }

    @Test func firstSnapshotMidWindowIsOnlyABaseline() {
        let now = start + 90 * minute
        let history = [UsageSnapshot(at: start + 70 * minute, fiveHour: fiveHour(42), sevenDay: nil)]
        let current = UsageSnapshot(at: start + 85 * minute, fiveHour: fiveHour(45), sevenDay: nil)
        let usage = UsageStore.summarize(current: current, history: history, now: now)!.fiveHour!

        #expect(usage.segments[0] == .noData)
        #expect(usage.segments[1] == .noData)
        #expect(usage.segments[2] == .done(ratio: 0.3))  // only the 3% seen after the baseline
        #expect(usage.segments[3] == .live(ratio: nil))
    }

    @Test func fiveHourSeverity() {
        let now = start + hour
        func severity(_ used: Double) -> UsageSeverity? {
            let current = UsageSnapshot(at: now, fiveHour: fiveHour(used), sevenDay: nil)
            return UsageStore.summarize(current: current, history: [], now: now)?.fiveHour?.severity
        }
        #expect(severity(50) == .ok)
        #expect(severity(75) == .warning)
        #expect(severity(92) == .critical)
    }

    @Test func sevenDayPaceCountsAfterFirstDay() {
        func severity(_ used: Double, elapsed: Int64) -> UsageSeverity? {
            let now = start + elapsed
            let current = UsageSnapshot(at: now, fiveHour: nil, sevenDay: sevenDay(used))
            return UsageStore.summarize(current: current, history: [], now: now)?.sevenDay?.severity
        }
        #expect(severity(50, elapsed: 3 * day) == .warning)  // 50% used at ~43% of the week
        #expect(severity(30, elapsed: 3 * day) == .ok)
        #expect(severity(10, elapsed: 12 * hour) == .ok)  // first day: pace ignored
        #expect(severity(85, elapsed: 6 * day + 12 * hour) == .warning)  // 15% left
        #expect(severity(97, elapsed: 6 * day + 12 * hour) == .critical)
    }

    @Test func bindingPicksTighterWindowAndPrefersFiveHourOnTie() {
        let now = start + 3 * day
        let fiveHourNow = UsageWindow(usedPercentage: 20, resetsAt: (now + 2 * hour) / 1000)

        let ahead = UsageSnapshot(at: now, fiveHour: fiveHourNow, sevenDay: sevenDay(60))
        #expect(UsageStore.summarize(current: ahead, history: [], now: now)?.binding?.kind == .sevenDay)

        let calm = UsageSnapshot(at: now, fiveHour: fiveHourNow, sevenDay: sevenDay(20))
        #expect(UsageStore.summarize(current: calm, history: [], now: now)?.binding?.kind == .fiveHour)
    }

    @Test func dropsResetWindowsAndFlagsStaleData() {
        let now = start + 6 * hour
        let current = UsageSnapshot(at: start + hour, fiveHour: fiveHour(40), sevenDay: sevenDay(10))
        let summary = UsageStore.summarize(current: current, history: [], now: now)!

        #expect(summary.fiveHour == nil)
        #expect(summary.binding?.kind == .sevenDay)
        #expect(summary.isStale)

        let expired = UsageSnapshot(at: now, fiveHour: fiveHour(40), sevenDay: nil)
        #expect(UsageStore.summarize(current: expired, history: [], now: now) == nil)
    }

    @Test func loadsFilesWrittenByStatusLine() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = start + 20 * minute
        let usage = """
            {"updated_at": \(now), "five_hour": {"used_percentage": 12.5, "resets_at": \((start + 5 * hour) / 1000)},
             "seven_day": null, "context_used_percentage": 34}
            """
        let history = """
            {"at":\(start + 5 * minute),"five_hour":{"used_percentage":4,"resets_at":\((start + 5 * hour) / 1000)},"seven_day":null}
            not json
            {"at":\(now),"five_hour":{"used_percentage":12.5,"resets_at":\((start + 5 * hour) / 1000)},"seven_day":null}
            """
        try usage.write(to: dir.appendingPathComponent("usage.json"), atomically: true, encoding: .utf8)
        try history.write(
            to: dir.appendingPathComponent("usage-history.jsonl"), atomically: true, encoding: .utf8)

        let summary = try #require(UsageStore.load(in: dir, now: now))
        #expect(summary.sevenDay == nil)
        #expect(summary.fiveHour?.remainingPercentage == 87.5)
        #expect(summary.fiveHour?.segments[0] == .live(ratio: 1.25))
    }
}
