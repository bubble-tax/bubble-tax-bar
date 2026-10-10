import XCTest
@testable import BubbleTaxBarCore

final class UnusedQuotaHistoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func window(_ reset: Double, remaining: Double = 80, minutes: Int = 10080, account: String? = "a") -> QuotaWindow {
        QuotaWindow(provider: .claude, limitID: "limit", windowMinutes: minutes,
            resetsAt: reset, observedAt: reset - 60, usedPercent: 100 - remaining, accountKey: account)
    }
    func testAllRecordedRetainsOlderHistoryWithoutMixingLimitsOrAccounts() {
        let recent = now.timeIntervalSince1970 - 86400
        let old = recent - 60 * 86400
        let values = [window(old, remaining: 60), window(recent), window(recent, minutes: 300), window(recent, account: "b")]
        let groups = UnusedQuotaHistory.groups(values + values, now: now)
        XCTAssertEqual(groups.count, 3)
        let weekly = groups.first { $0.accountKey == "a" && $0.windowMinutes == 10080 }!
        XCTAssertEqual(weekly.windows.count, 2)
        XCTAssertEqual(weekly.averageUnused, 70)
        XCTAssertEqual(weekly.fullWindowEquivalent, 1.4, accuracy: 0.001)
        XCTAssertEqual(UnusedQuotaHistory.groups(values, since: now.addingTimeInterval(-30 * 86400), now: now).reduce(0) { $0 + $1.windows.count }, 3)
    }
    func testCurrentAnonymousStaleAndInterruptedReadingsAreExcluded() {
        let reset = now.timeIntervalSince1970 - 60
        var current = window(now.timeIntervalSince1970 + 86400)
        current.observedAt = now.timeIntervalSince1970 - 10
        var stale = window(reset); stale.observedAt = reset - 901
        var interrupted = window(reset); interrupted.interrupted = true
        XCTAssertTrue(UnusedQuotaHistory.eligibleWindows([current, stale, interrupted, window(reset, account: nil)], now: now).isEmpty)
    }
    func testEarlyReplacementInvalidatesEarlierArchivedReading() {
        let reset = now.timeIntervalSince1970 - 60
        let first = window(reset)
        var replacement = window(reset + 86400)
        var earlier = first; earlier.observedAt = reset - 300
        replacement.observedAt = reset - 120
        XCTAssertTrue(UnusedQuotaHistory.eligibleWindows([earlier, replacement], now: now).isEmpty)
    }
    func testLegacyStateDecodesWithoutArchive() throws {
        let data = try JSONDecoder().decode(AppData.self, from: Data(#"{"version":1,"subscriptions":[]}"#.utf8))
        XCTAssertNil(data.unusedQuotaArchive)
    }
}
