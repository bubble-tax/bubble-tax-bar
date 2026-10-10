import XCTest
@testable import BubbleTaxBarCore

final class QuotaUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func reading(reset: Double, observed: Double, used: Double, minutes: Int = 300) -> QuotaWindow {
        QuotaWindow(provider: .openai, windowMinutes: minutes,
                    resetsAt: now.timeIntervalSince1970 + reset,
                    observedAt: now.timeIntervalSince1970 + observed, usedPercent: used, accountKey: "verified")
    }
    func testCurrentRemainingDoesNotCountAsExpired() {
        let summary = QuotaUsage.summaries(provider: .openai,
            windows: [reading(reset: 1000, observed: -10, used: 25)], now: now)[0]
        XCTAssertEqual(summary.current?.remainingPercent, 75)
        XCTAssertNil(summary.averageUnused)
    }
    func testLatestAccountSnapshotWinsWithoutSummingSessions() {
        let summary = QuotaUsage.summaries(provider: .openai,
            windows: [reading(reset: -100, observed: -500, used: 20),
                      reading(reset: -100, observed: -200, used: 40),
                      reading(reset: -100, observed: -200, used: 40)], now: now)[0]
        XCTAssertEqual(summary.expired.count, 1)
        XCTAssertEqual(summary.averageUnused, 60)
        XCTAssertEqual(summary.latestExpired?.observedAt, now.timeIntervalSince1970 - 200)
    }
    func testOverlappingWindowsStaySeparateAndOldHistoryExcluded() {
        let summaries = QuotaUsage.summaries(provider: .openai,
            windows: [reading(reset: -100, observed: -200, used: 20),
                      reading(reset: -100, observed: -200, used: 80, minutes: 10080),
                      reading(reset: -31 * 86400, observed: -32 * 86400, used: 0)], now: now)
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].averageUnused, 80)
        XCTAssertEqual(summaries[1].averageUnused, 20)
        XCTAssertEqual(summaries[0].expired.count, 1)
    }
    func testMergeRetainsHistoryAndGroupsResetTimestampDrift() {
        let windows = QuotaUsage.compact([
            reading(reset: -100, observed: -500, used: 20),
            reading(reset: -95, observed: -200, used: 40),
            reading(reset: 1000, observed: -10, used: 5)
        ])
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].usedPercent, 40)
        XCTAssertEqual(windows[1].usedPercent, 5)
    }
    func testUnknownInvalidAndFutureReadingsAreNotZeroUsage() {
        let summaries = QuotaUsage.summaries(provider: .openai,
            windows: [reading(reset: 1000, observed: 10, used: 0),
                      reading(reset: -100, observed: -200, used: 101),
                      reading(reset: -100, observed: -10, used: 5)], now: now)
        XCTAssertTrue(summaries.isEmpty)
        XCTAssertTrue(QuotaUsage.summaries(provider: .claude,
            windows: [reading(reset: -100, observed: -200, used: 5)], now: now).isEmpty)
    }
    func testOldAndAnonymousExpiredBalancesDoNotBecomeWaste() {
        var anonymous = reading(reset: -100, observed: -200, used: 10)
        anonymous.accountKey = nil
        let summaries = QuotaUsage.summaries(provider: .openai, windows: [anonymous,
            reading(reset: -1000, observed: -5000, used: 10)], now: now)
        XCTAssertTrue(summaries.allSatisfy { $0.averageUnused == nil })
    }
    func testEarlyReplacementAndUsageDecreaseAreExcludedFromWaste() {
        let early = QuotaUsage.compact([
            reading(reset: -100, observed: -300, used: 40),
            reading(reset: 1000, observed: -200, used: 5)])
        XCTAssertEqual(early.first?.interrupted, true)
        XCTAssertNil(QuotaUsage.summaries(provider: .openai, windows: early, now: now)[0].averageUnused)
        let drop = QuotaUsage.compact([
            reading(reset: -100, observed: -300, used: 80),
            reading(reset: -100, observed: -200, used: 5)])
        XCTAssertEqual(drop.first?.interrupted, true)
        XCTAssertNil(QuotaUsage.summaries(provider: .openai, windows: drop, now: now)[0].averageUnused)
        XCTAssertEqual(QuotaUsage.compact(drop).first?.interrupted, true)
    }
    func testStaleReadingDoesNotAppearAsCurrentLeft() {
        let quota = QuotaUsage.summaries(provider: .openai,
            windows: [reading(reset: 5000, observed: -901, used: 20)], now: now)[0]
        XCTAssertNil(quota.current)
    }
}
