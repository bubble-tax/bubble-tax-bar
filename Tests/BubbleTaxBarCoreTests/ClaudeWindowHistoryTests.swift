import XCTest
@testable import BubbleTaxBarCore

final class ClaudeWindowHistoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func pair(_ time: Double, session: Double, weekly: Double, reset: Double = 5000,
              weekReset: Double = 100000, account: String = "a", plan: String = "Max", limit: String = "claude:secondary") -> ClaudeQuotaSample {
        let t = now.timeIntervalSince1970
        return ClaudeQuotaSample(accountKey: account, planLabel: plan,
            session: QuotaWindow(provider: .claude, limitID: "claude:primary", windowMinutes: 300,
                resetsAt: t + reset, observedAt: t + time, usedPercent: session, accountKey: account),
            weekly: QuotaWindow(provider: .claude, limitID: limit, windowMinutes: 10080,
                resetsAt: t + weekReset, observedAt: t + time, usedPercent: weekly, accountKey: account))
    }
    func testPairedChangesAndRatioAcrossTwoWindows() {
        let rows = ClaudeWindowHistory.comparisons([
            pair(-1200, session: 10, weekly: 20), pair(-900, session: 60, weekly: 25),
            pair(-600, session: 0, weekly: 25, reset: 23000), pair(-300, session: 50, weekly: 35, reset: 23000)
        ], now: now)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].sessionDelta, 50)
        XCTAssertEqual(rows[0].weeklyDelta, 5)
        XCTAssertEqual(rows[0].weeklyPerFullSession, 10)
        XCTAssertEqual(rows[1].weeklyPerFullSession, 20)
    }
    func testWeeklyResetDecreaseAndPlanChangeNeverBecomeNegativeDelta() {
        let readings = [pair(-1200, session: 10, weekly: 90),
            pair(-900, session: 20, weekly: 0, weekReset: 700000),
            pair(-600, session: 5, weekly: 2, weekReset: 700000),
            pair(-300, session: 8, weekly: 3, weekReset: 700000, plan: "Pro")]
        let rows = ClaudeWindowHistory.comparisons(readings, now: now)
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.allSatisfy { $0.weeklyPerFullSession == nil && $0.sessionDelta == 0 })
    }
    func testReturningToEarlierPlanStillStartsNewSegment() {
        let rows = ClaudeWindowHistory.comparisons([pair(-900, session: 10, weekly: 10),
            pair(-600, session: 20, weekly: 20, plan: "Pro"),
            pair(-300, session: 30, weekly: 30)], now: now)
        XCTAssertEqual(rows.count, 3)
    }
    func testDifferentAccountsAndWeeklyMetersStaySeparate() {
        let rows = ClaudeWindowHistory.comparisons([pair(-300, session: 10, weekly: 20),
            pair(-300, session: 10, weekly: 2, limit: "claude:tertiary"),
            pair(-300, session: 10, weekly: 60, account: "b")], now: now)
        XCTAssertEqual(rows.count, 3)
    }
    func testGapAndRoundedTinyDeltaSuppressComparisonRate() {
        let gap = ClaudeWindowHistory.comparisons([pair(-2000, session: 0, weekly: 10), pair(-300, session: 40, weekly: 20)], now: now)[0]
        XCTAssertTrue(gap.hasGap)
        XCTAssertNil(gap.weeklyPerFullSession)
        let small = ClaudeWindowHistory.comparisons([pair(-600, session: 0, weekly: 10), pair(-300, session: 1, weekly: 11)], now: now)[0]
        XCTAssertNil(small.weeklyPerFullSession)
    }
    func testRecordingRejectsAnonymousStaleMismatchedAndNonClaudeDataAndDeduplicates() throws {
        let connection = try JSONDecoder().decode(ProviderConnection.self, from: Data(#"{"provider":"claude","status":"connected","source":"oauth","accountKey":"a","planLabel":"Max"}"#.utf8))
        let sample = pair(-60, session: 10, weekly: 20)
        let recorded = ClaudeWindowHistory.record([], windows: [sample.session, sample.weekly], connection: connection, now: now)
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(ClaudeWindowHistory.record(recorded, windows: [sample.session, sample.weekly], connection: connection, now: now).count, 1)
        let stale = pair(-1000, session: 10, weekly: 20)
        XCTAssertTrue(ClaudeWindowHistory.record([], windows: [stale.session, stale.weekly], connection: connection, now: now).isEmpty)
        var wrong = sample.weekly; wrong.accountKey = "b"
        XCTAssertTrue(ClaudeWindowHistory.record([], windows: [sample.session, wrong], connection: connection, now: now).isEmpty)
        wrong = sample.weekly; wrong.observedAt -= 61
        XCTAssertTrue(ClaudeWindowHistory.record([], windows: [sample.session, wrong], connection: connection, now: now).isEmpty)
        XCTAssertTrue(ClaudeWindowHistory.record([], windows: [sample.session, sample.weekly], connection: nil, now: now).isEmpty)
    }
    func testOldStateCompatibilityAndRetention() throws {
        let state = try JSONDecoder().decode(AppData.self, from: Data(#"{"version":1,"subscriptions":[]}"#.utf8))
        XCTAssertNil(state.claudeQuotaSamples)
        let old = pair(-181 * 86400, session: 10, weekly: 20)
        XCTAssertTrue(ClaudeWindowHistory.record([old], windows: [], connection: nil, now: now).isEmpty)
        var data = AppData(); data.claudeQuotaSamples = [pair(-60, session: 10, weekly: 20)]
        XCTAssertEqual(try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data)).claudeQuotaSamples, data.claudeQuotaSamples)
    }
}
