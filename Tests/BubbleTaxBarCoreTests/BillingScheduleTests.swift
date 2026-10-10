import XCTest
@testable import BubbleTaxBarCore

final class BillingScheduleTests: XCTestCase {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    func testMonthEndRecursFromOriginalAnchorAndIncludesToday() {
        let value = BillingSchedule(provider: .claude, accountKey: "a", anchor: date(2026, 1, 31), interval: .monthly)
        XCTAssertEqual(value.nextRenewal(now: date(2026, 2, 1), calendar: calendar), date(2026, 2, 28))
        XCTAssertEqual(value.nextRenewal(now: date(2026, 3, 1), calendar: calendar), date(2026, 3, 31))
        XCTAssertEqual(value.nextRenewal(now: date(2026, 3, 31).addingTimeInterval(3600), calendar: calendar), date(2026, 3, 31))
        XCTAssertEqual(value.nextRenewal(now: date(2028, 2, 1), calendar: calendar), date(2028, 2, 29))
    }
    func testYearlyLeapDayAndFutureAnchor() {
        let value = BillingSchedule(provider: .openai, accountKey: nil, anchor: date(2024, 2, 29), interval: .yearly)
        XCTAssertEqual(value.nextRenewal(now: date(2025, 2, 1), calendar: calendar), date(2025, 2, 28))
        XCTAssertEqual(value.nextRenewal(now: date(2028, 2, 1), calendar: calendar), date(2028, 2, 29))
        XCTAssertEqual(value.nextRenewal(now: date(2020, 1, 1), calendar: calendar), date(2024, 2, 29))
    }
    func testPersistenceIsOptionalAndAccountScoped() throws {
        let old = try JSONDecoder().decode(AppData.self, from: Data(#"{"version":1,"subscriptions":[]}"#.utf8))
        XCTAssertNil(old.billingSchedules)
        let value = BillingSchedule(provider: .claude, accountKey: "a", anchor: date(2026, 1, 31), interval: .monthly)
        var state = old; state.billingSchedules = [value]
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(BillingSchedule.matching(restored.billingSchedules!, provider: .claude, accountKey: "a"), value)
        XCTAssertNil(BillingSchedule.matching(restored.billingSchedules!, provider: .claude, accountKey: "b"))
        XCTAssertNil(BillingSchedule.matching(restored.billingSchedules!, provider: .openai, accountKey: "a"))
        XCTAssertNil(BillingSchedule.matching(restored.billingSchedules!, provider: .claude, accountKey: nil))
    }
}
