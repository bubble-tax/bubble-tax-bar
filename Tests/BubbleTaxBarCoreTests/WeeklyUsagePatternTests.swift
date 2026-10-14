import XCTest
@testable import BubbleTaxBarCore

final class WeeklyUsagePatternTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func connection(_ account: String = "a", plan: String = "Pro") -> ProviderConnection {
        try! JSONDecoder().decode(ProviderConnection.self, from: JSONSerialization.data(withJSONObject: ["provider":"openai","status":"connected","source":"oauth","accountKey":account,"planLabel":plan]))
    }
    func samples(duration: Double = 1800, sessionDelta: Double = 20, weeklyDelta: Double = 5, weekLeft: Double = 72*3600, used: Double = 20, account: String = "a", plan: String = "Pro") -> [WindowQuotaSample] {
        let t = now.timeIntervalSince1970
        let count = Int(ceil(duration / 900))
        return (0...count).map { i in
            let fraction = Double(i) / Double(count)
            let date = t - duration + fraction * duration
            return WindowQuotaSample(accountKey: account, planLabel: plan,
                session: QuotaWindow(provider: .openai, limitID: "codex:primary", windowMinutes: 300,
                    resetsAt: t+3600, observedAt: date, usedPercent: 30-sessionDelta+fraction*sessionDelta, accountKey: account),
                weekly: QuotaWindow(provider: .openai, limitID: "codex:secondary", windowMinutes: 10080,
                    resetsAt: t+weekLeft, observedAt: date, usedPercent: used-weeklyDelta+fraction*weeklyDelta, accountKey: account))
        }
    }
    func estimate(_ values: [WindowQuotaSample], history: [WindowQuotaSample]? = nil, account: String = "a", plan: String = "Pro") -> WeeklyUsagePattern {
        let last = values.last!
        return WeeklyUsagePattern.make(provider: .openai, connection: connection(account, plan: plan),
            windows: [last.session,last.weekly], samples: history ?? values, now: now)
    }
    func testHoursAndWindowQuotasPerDayUseObservedPaceAndDeadline() {
        let value = estimate(samples())
        XCTAssertEqual(value.status, .feasible)
        XCTAssertEqual(value.hoursNeeded!, 8, accuracy: 0.001)
        XCTAssertEqual(value.hoursPerDay!, 8.0/3, accuracy: 0.001)
        XCTAssertEqual(value.fullQuotasPerDay!, 3.2/3, accuracy: 0.001)
        XCTAssertEqual(value.intervals, 1)
    }
    func testSlowPaceIsExplicitlyConditionalAndDoesNotMeanNoOtherPatternCanFit() {
        let value = estimate(samples(duration: 7200, sessionDelta: 10, weeklyDelta: 5, weekLeft: 8*3600))
        XCTAssertEqual(value.status, .paceTooSlow)
        XCTAssertEqual(value.hoursNeeded!, 32, accuracy: 0.001)
        XCTAssertEqual(value.hoursLeft!, 8, accuracy: 0.001)
    }
    func testCapacityCheckBeforeCurrentSessionResetAndAtExactBoundary() {
        XCTAssertEqual(estimate(samples(weekLeft: 1800)).status, .windowsTooFew)
        let boundary = estimate(samples(weekLeft: 3600+18000))
        XCTAssertEqual(boundary.availableFullQuotas!, 1.7, accuracy: 0.001)
    }
    func testTinyWeeklyMovementZeroMovementAndGapAreNotGuessed() {
        XCTAssertEqual(estimate(samples(weeklyDelta: 0)).status, .insufficient)
        XCTAssertEqual(estimate(samples(sessionDelta: 5)).status, .insufficient)
        let values = samples(duration: 3600)
        XCTAssertEqual(estimate(values, history: [values.first!,values.last!]).status, .insufficient)
    }
    func testDifferentAccountPlanAndCycleAreExcluded() {
        let current = samples()
        XCTAssertEqual(estimate(current, history: samples(account: "b")).status, .insufficient)
        XCTAssertEqual(estimate(current, history: samples(plan: "Plus")).status, .insufficient)
        XCTAssertEqual(estimate(current, history: samples(weekLeft: 24*3600)).status, .insufficient)
    }
    func testWeeklyOnlyCanEstimateTimeWithoutInventingSessionCapacity() {
        let values = samples(); let last = values.last!
        let result = WeeklyUsagePattern.make(provider: .openai, connection: connection(), windows: [last.weekly], samples: values, now: now)
        XCTAssertEqual(result.status, .feasible)
        XCTAssertNil(result.availableFullQuotas)
        let exhausted = samples(used: 100).last!
        XCTAssertEqual(WeeklyUsagePattern.make(provider: .openai, connection: connection(), windows: [exhausted.weekly], samples: [], now: now).status, .exhausted)
    }
    func testExhaustedAndStaleReadings() {
        XCTAssertEqual(estimate(samples(used: 100)).status, .exhausted)
        let last = samples().last!
        var stale = last.session; stale.observedAt = now.timeIntervalSince1970-901
        XCTAssertEqual(WeeklyUsagePattern.make(provider: .openai, connection: connection(), windows: [stale,last.weekly], samples: samples(), now: now).status, .feasible)
    }
}
