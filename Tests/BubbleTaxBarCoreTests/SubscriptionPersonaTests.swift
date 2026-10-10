import XCTest
@testable import BubbleTaxBarCore

final class SubscriptionPersonaTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func connection(_ provider: Provider, plan: String = "Pro", cost: Double? = nil, currency: String = "USD") -> ProviderConnection {
        var connection = ProviderConnection(provider: provider, status: "connected", source: "oauth",
            planLabel: plan, accountKey: provider.rawValue, observedAt: now.timeIntervalSince1970)
        if let cost {
            connection.verifiedMonthlyCost = VerifiedMonthlyCost(amount: cost, currency: currency,
                accountKey: provider.rawValue, observedAt: now.timeIntervalSince1970)
        }
        return connection
    }
    func window(_ provider: Provider, unused: Double, minutes: Int = 10080, bucket: String = "primary", observedGap: Double = 60) -> QuotaWindow {
        QuotaWindow(provider: provider, limitID: bucket, windowMinutes: minutes,
            resetsAt: now.timeIntervalSince1970 + 86400, observedAt: now.timeIntervalSince1970 - observedGap,
            usedPercent: 100 - unused, accountKey: provider.rawValue)
    }
    func snapshot(_ connections: [ProviderConnection], _ windows: [QuotaWindow]) -> CollectorSnapshot {
        CollectorSnapshot(days: [], sources: [], quotaWindows: windows, connections: connections)
    }
    func testPersonaThresholdsAndPriceUnknownFallback() {
        for (unused, persona): (Double, SubscriptionPersona) in [(95, .environmentalist), (82, .donationAngel), (65, .bubbleSponsor), (50, .benchwarmer), (20, .tokenMaxxer)] {
            let result = PersonaAssessment.make(snapshot: snapshot([connection(.claude, plan: "Individual")], [window(.claude, unused: unused)]), now: now)
            XCTAssertEqual(result.persona, persona)
            XCTAssertNil(result.monthlyTotal)
            XCTAssertFalse(result.priceWeighted)
        }
    }
    func testVerifiedPricesWeightQuotaWithoutClaimingCashWaste() {
        let result = PersonaAssessment.make(snapshot: snapshot([
            connection(.claude, cost: 80), connection(.openai, cost: 20)],
            [window(.claude, unused: 90), window(.openai, unused: 10)]), now: now)
        XCTAssertEqual(result.monthlyTotal, 100)
        XCTAssertEqual(result.remainingPercent!, 74, accuracy: 0.001)
        XCTAssertTrue(result.priceWeighted)
        XCTAssertEqual(result.currency, "USD")
    }
    func testMissingCostsMixedCurrencyAndChangedAccountsCannotFabricateTotal() {
        for second in [connection(.openai, plan: "Individual"), connection(.openai, cost: 20, currency: "KRW")] {
            let result = PersonaAssessment.make(snapshot: snapshot([connection(.claude, cost: 80), second],
                [window(.claude, unused: 90), window(.openai, unused: 10)]), now: now)
            XCTAssertNil(result.monthlyTotal)
            XCTAssertFalse(result.priceWeighted)
            XCTAssertEqual(result.remainingPercent, 50)
        }
        var old = connection(.claude, cost: 80)
        old.verifiedMonthlyCost?.accountKey = "another-account"
        XCTAssertEqual(PersonaAssessment.make(snapshot: snapshot([old], [window(.claude, unused: 90)]), now: now).monthlyTotal, 20)
    }
    func testNestedBudgetsWorkSeatsAndFreePlansDoNotInflatePersonalScore() {
        let result = PersonaAssessment.make(snapshot: snapshot([
            connection(.claude), connection(.openai, plan: "Enterprise", cost: 200), connection(.cursor, plan: "Free")],
            [window(.claude, unused: 100, minutes: 300), window(.claude, unused: 80, minutes: 10080, bucket: "weekly"),
             window(.openai, unused: 100), window(.cursor, unused: 100)]), now: now)
        XCTAssertEqual(result.personalPlans, 1)
        XCTAssertEqual(result.workPlans, 1)
        XCTAssertEqual(result.coveredPlans, 1)
        XCTAssertEqual(result.remainingPercent, 80)
    }
    func testExpiredShortStaleAndOtherAccountReadingsStayPending() {
        var expired = window(.claude, unused: 100)
        expired.resetsAt = now.timeIntervalSince1970 - 10
        expired.observedAt = now.timeIntervalSince1970 - 20
        var other = window(.claude, unused: 100)
        other.accountKey = "another-account"
        for windows in [[expired], [window(.claude, unused: 100, minutes: 300)],
                        [window(.claude, unused: 100, observedGap: 1000)], [other]] {
            let result = PersonaAssessment.make(snapshot: snapshot([connection(.claude)], windows), now: now)
            XCTAssertEqual(result.persona, .pending)
            XCTAssertTrue(result.pendingReason?.contains("weekly") == true)
            XCTAssertNil(result.remainingPercent)
        }
        let stale = PersonaAssessment.make(snapshot: snapshot([connection(.claude)], [window(.claude, unused: 100)]), fresh: false, now: now)
        XCTAssertEqual(stale.persona, .pending)
        XCTAssertTrue(stale.pendingReason?.contains("Refresh") == true)
    }
    func testFreeAndCorporatePersonasStayInTheirBillingScope() {
        let free = PersonaAssessment.make(snapshot: snapshot([connection(.cursor, plan: "Free")], []), now: now)
        XCTAssertEqual(free.persona, .freeLegend)
        let work = PersonaAssessment.make(snapshot: snapshot([connection(.claude, plan: "Enterprise", cost: 200)], [window(.claude, unused: 80)]), now: now)
        XCTAssertEqual(work.persona, .corporateSponsor)
        XCTAssertNil(work.monthlyTotal)
        XCTAssertEqual(work.personalPlans, 0)
    }

    func testNewPersonasMatchEvidenceAndStayStableAcrossRefreshes() {
        for (unused, expected): (Double, SubscriptionPersona) in [
            (99, .cloudPreserver), (87, .ghostSubscriber), (72, .tokenTrasher),
            (55, .benchwarmer), (40, .backupHoarder), (8, .rateLimitRegular), (2, .quotaMenace)] {
            let data = snapshot([connection(.claude)], [window(.claude, unused: unused)])
            XCTAssertEqual(PersonaAssessment.make(snapshot: data, now: now).persona, expected)
            XCTAssertEqual(PersonaAssessment.make(snapshot: data, now: now.addingTimeInterval(30)).persona, expected)
        }
        for (unused, expected): (Double, SubscriptionPersona) in [
            (99, .emptySeat), (70, .procurementPrank), (55, .budgetBurner), (10, .officePowerUser)] {
            let data = snapshot([connection(.claude, plan: "Enterprise")], [window(.claude, unused: unused)])
            let result = PersonaAssessment.make(snapshot: data, now: now)
            XCTAssertEqual(result.persona, expected)
            XCTAssertNil(result.monthlyTotal)
        }
    }

    func testCollectionPersonasUsePlanCountAndPremiumNeedsCompleteUSDEvidence() {
        let plans = [connection(.claude, plan: "Individual"), connection(.openai, plan: "Individual"), connection(.cursor, plan: "Individual")]
        for (unused, expected): (Double, SubscriptionPersona) in [(65, .ventureCapitalist), (55, .collector), (40, .fomoCollector)] {
            let windows = plans.map { window($0.provider, unused: unused) }
            XCTAssertEqual(PersonaAssessment.make(snapshot: snapshot(plans, windows), now: now).persona, expected)
        }
        let paid = [connection(.claude, plan: "Max 5x"), connection(.openai, plan: "Plus")]
        let complete = [window(.claude, unused: 80), window(.openai, unused: 80)]
        XCTAssertEqual(PersonaAssessment.make(snapshot: snapshot(paid, complete), now: now).persona, .premiumPhilanthropist)
        XCTAssertEqual(PersonaAssessment.make(snapshot: snapshot(paid, [complete[0]]), now: now).persona, .donationAngel)
        XCTAssertEqual(PersonaAssessment.make(snapshot: snapshot([connection(.claude, plan: "Max")], [complete[0]]), now: now).persona, .donationAngel)
        XCTAssertEqual(PersonaAssessment.make(snapshot: snapshot([connection(.claude, cost: 200, currency: "KRW")], [complete[0]]), now: now).persona, .donationAngel)
        let free = [connection(.cursor, plan: "Free"), connection(.copilot, plan: "student")]
        XCTAssertEqual(PersonaAssessment.make(snapshot: snapshot(free, []), now: now).persona, .couponLegend)
        XCTAssertEqual(Set(SubscriptionPersona.allCases.map(\.title)).count, 24)
    }
    func testWeekly34PercentLeftOverridesQuietShortWindowWithoutExpiredHistory() {
        let data = snapshot([connection(.claude)], [window(.claude, unused: 99, minutes: 300),
            window(.claude, unused: 34, bucket: "weekly")])
        let result = PersonaAssessment.make(snapshot: data, now: now)
        XCTAssertEqual(result.persona, .tokenMaxxer)
        XCTAssertEqual(result.remainingPercent, 34)
        XCTAssertEqual(result.coveredPlans, 1)
    }

    func testPartialCoverageDoesNotInventMissingWeeklyQuota() {
        let plans = [connection(.claude), connection(.openai)]
        let readings = [window(.claude, unused: 80), window(.openai, unused: 0, minutes: 300)]
        let result = PersonaAssessment.make(snapshot: snapshot(plans, readings), now: now)
        XCTAssertEqual(result.coveredPlans, 1)
        XCTAssertEqual(result.remainingPercent, 80)
        XCTAssertFalse(result.priceWeighted)
        XCTAssertFalse(result.scope.contains("ChatGPT"))
    }
}
