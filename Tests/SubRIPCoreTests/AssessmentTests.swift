import XCTest
@testable import SubRIPCore

final class AssessmentTests: XCTestCase {
    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return result
    }
    func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    func subscription() -> Subscription {
        Subscription(name: "Test", monthlyPrice: 20, billingAnchor: date(2026, 10, 1), observedSince: date(2026, 10, 1), coverageConfirmed: true, coverageConfirmedAt: date(2026, 10, 14))
    }
    func testShortObservationNeverRecommendsCancellation() {
        XCTAssertEqual(Assessor.assess(subscription(), snapshot: nil, now: date(2026, 10, 14), calendar: calendar).verdict, .observing)
    }
    func testConfirmedLowUseBecomesReviewAfter14CompletedDays() {
        let result = Assessor.assess(subscription(), snapshot: nil, now: date(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(result.verdict, .review)
        XCTAssertEqual(result.riskScore, 100)
    }
    func testUnknownCoverageNeverRecommendsCancellation() {
        var item = subscription(); item.coverageConfirmed = false
        XCTAssertEqual(Assessor.assess(item, snapshot: nil, now: date(2026, 10, 20), calendar: calendar).verdict, .incomplete)
    }
    func testCLIMissingSnapshotNeverRecommendsCancellation() {
        var item = subscription(); item.includesCLI = true
        XCTAssertEqual(Assessor.assess(item, snapshot: nil, now: date(2026, 10, 20), calendar: calendar).verdict, .incomplete)
    }
    func testValuableUseWinsOverLowFrequency() {
        var item = subscription(); item.valuableThisCycle = true; item.valueMarkedAt = date(2026, 10, 2)
        XCTAssertEqual(Assessor.assess(item, snapshot: nil, now: date(2026, 10, 20), calendar: calendar).verdict, .keep)
    }
    func testValuableUseDoesNotCarryIntoNewCycle() {
        var item = subscription(); item.valuableThisCycle = true; item.valueMarkedAt = date(2026, 10, 2)
        item.coverageConfirmedAt = date(2026, 11, 19)
        XCTAssertEqual(Assessor.assess(item, snapshot: nil, now: date(2026, 11, 20), calendar: calendar).verdict, .review)
    }
    func testManualDaysDeduplicateAndExcludeFutureAndPriorCycle() {
        var item = subscription()
        item.manualDays = [date(2026, 10, 2), date(2026, 10, 2), date(2026, 11, 2), date(2026, 9, 2)]
        let result = Assessor.assess(item, snapshot: nil, now: date(2026, 10, 20), calendar: calendar)
        XCTAssertEqual(result.activeDays, 1)
    }
    func testMonthEndAnchorDoesNotDrift() {
        var item = subscription(); item.billingAnchor = date(2026, 1, 31)
        let cycle = Assessor.cycle(for: item, now: date(2026, 3, 15), calendar: calendar)
        XCTAssertEqual(cycle.start, date(2026, 2, 28))
        XCTAssertEqual(cycle.end, date(2026, 3, 31))
    }
    func testUsageBeforeObservationDoesNotArtificiallyImproveScore() {
        var item = subscription(); item.observedSince = date(2026, 10, 5)
        item.manualDays = (1...4).map { date(2026, 10, $0) }
        let result = Assessor.assess(item, snapshot: nil, now: date(2026, 10, 20), calendar: calendar)
        XCTAssertEqual(result.riskScore, 100)
    }
    func testCancelledSubscriptionIsBuried() {
        var item = subscription(); item.cancelledAt = date(2026, 10, 3)
        XCTAssertEqual(Assessor.assess(item, snapshot: nil, now: date(2026, 10, 20), calendar: calendar).verdict, .buried)
    }
    func testOldCoverageConfirmationDoesNotCarryIntoNewCycle() {
        XCTAssertEqual(Assessor.assess(subscription(), snapshot: nil, now: date(2026, 11, 20), calendar: calendar).verdict, .incomplete)
    }
}
