import XCTest
@testable import BubbleTaxBarCore

final class UsageRoastTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 8))! }
    func snapshot(status: String = "ok", days: [String]) -> CollectorSnapshot {
        let data: [String: Any] = [
            "days": days.map { ["provider": "claude", "day": $0, "tokens": 100, "requests": 1] as [String: Any] },
            "sources": [["provider": "claude", "status": status, "files": 2, "malformed": 0, "unreadable": 0, "unsupported": 0]]
        ]
        return try! JSONDecoder().decode(CollectorSnapshot.self, from: JSONSerialization.data(withJSONObject: data))
    }
    func testPartialAndStaleReceiptsNeverRecommendCancellation() {
        let data = snapshot(status: "partial", days: ["2026-09-08", "2026-10-01"])
        let partial = UsageRoast.make(provider: .claude, snapshot: data, now: now, calendar: calendar)
        XCTAssertTrue(partial.uncertain)
        XCTAssertFalse(partial.punchline.contains("cancel it"))
        let stale = UsageRoast.make(provider: .claude, snapshot: snapshot(days: ["2026-09-08"]), fresh: false, now: now, calendar: calendar)
        XCTAssertEqual(stale.status, "RECEIPTS MISSING")
    }
    func testFrequentUsageSurvivesTheRoast() {
        let days = (10...30).map { "2026-09-\($0)" }
        let result = UsageRoast.make(provider: .claude, snapshot: snapshot(days: days), now: now, calendar: calendar)
        XCTAssertEqual(result.status, "USAGE CONFIRMED")
        XCTAssertEqual(result.activeDays, 21)
    }
    func testLowUsageRoastUsesAHypotheticalPlanWithoutUserInput() {
        let result = UsageRoast.make(provider: .claude, snapshot: snapshot(days: ["2026-09-10"]), now: now, calendar: calendar)
        XCTAssertEqual(result.status, "ON THIN ICE")
        XCTAssertEqual(result.scenario, .localWaste)
        XCTAssertTrue(result.evidence.contains("Local logs:"))
        XCTAssertTrue(result.evidence.contains("Other usage may be missing"))
    }
    func testPartialRoastMentionsPlanRhetoricallyWithoutCancellationAdvice() {
        let result = UsageRoast.make(provider: .claude, snapshot: snapshot(status: "partial", days: ["2026-09-10"]), now: now, calendar: calendar)
        XCTAssertEqual(result.scenario, .missing)
        XCTAssertFalse(result.punchline.contains("cancel it"))
    }
    func testRecentWindowDeduplicatesDaysAndIgnoresInvalidOrFutureDates() {
        let data = snapshot(days: ["2026-09-01", "2026-10-01", "2026-10-01", "2026-10-09", "2026-09-31", "bad"])
        let result = UsageRoast.make(provider: .claude, snapshot: data, now: now, calendar: calendar)
        XCTAssertEqual(result.activeDays, 1)
        XCTAssertEqual(result.tokens, 200)
        XCTAssertEqual(result.lastUsed, "2026-10-01")
    }
    func testLegacyPlanLabelsAreIgnoredWhenDecodingState() throws {
        let state = try JSONDecoder().decode(AppData.self, from: Data("{\"version\":1,\"subscriptions\":[],\"planLabels\":{\"claude\":\"Max\"}}".utf8))
        XCTAssertEqual(state.version, 1)
        XCTAssertTrue(state.subscriptions.isEmpty)
    }

    func server(used: Double? = nil, reset: Double = 10000, plan: String? = "Max", expired: Int = 0) -> CollectorSnapshot {
        var value = snapshot(status: "unconfigured", days: [])
        value.connections = [ProviderConnection(provider: .claude, status: "connected", source: "oauth",
            planLabel: plan, accountKey: "verified", observedAt: now.timeIntervalSince1970)]
        value.quotaWindows = (0..<expired).map { index in
            let end = now.timeIntervalSince1970 - 60 - Double(index) * 18000
            return QuotaWindow(provider: .claude, limitID: "claude:primary", windowMinutes: 300,
                               resetsAt: end, observedAt: end - 60, usedPercent: 10, accountKey: "verified")
        }
        if let used {
            value.quotaWindows?.append(QuotaWindow(provider: .claude, limitID: "claude:primary", windowMinutes: 300,
                resetsAt: now.timeIntervalSince1970 + reset, observedAt: now.timeIntervalSince1970 - 10,
                usedPercent: used, accountKey: "verified"))
        }
        return value
    }
    func testServerEvidenceWorksWithoutLocalLogsAndEarlyWindowIsNotExpiredWaste() {
        let value = server(used: 10)
        let early = UsageRoast.make(provider: .claude, snapshot: value, now: now, calendar: calendar)
        XCTAssertEqual(early.scenario, .remaining)
        XCTAssertFalse(early.uncertain)
        XCTAssertTrue(early.evidence.contains("90% left"))
        XCTAssertEqual(UsageRoast.make(provider: .claude, snapshot: server(used: 10, reset: 1000), now: now, calendar: calendar).scenario, .expiring)
        XCTAssertEqual(UsageRoast.make(provider: .claude, snapshot: server(used: 85), now: now, calendar: calendar).scenario, .active)
    }
    func testWasteRequiresRepeatedEligibleWindowsAndKnownPersonalPlan() {
        XCTAssertEqual(UsageRoast.make(provider: .claude, snapshot: server(expired: 1), now: now, calendar: calendar).scenario, .missing)
        let paid = UsageRoast.make(provider: .claude, snapshot: server(expired: 3), now: now, calendar: calendar)
        XCTAssertEqual(paid.scenario, .wasted)
        XCTAssertTrue(paid.evidence.contains("3 windows"))
        let unknown = UsageRoast.make(provider: .claude, snapshot: server(plan: nil, expired: 3), now: now, calendar: calendar)
        XCTAssertEqual(unknown.scenario, .unverified)
        let stale = UsageRoast.make(provider: .claude, snapshot: server(expired: 3), fresh: false, now: now, calendar: calendar)
        XCTAssertEqual(stale.scenario, .stale)
    }
    func testRotationIsStableDiverseAndDoesNotLeakPlaceholders() {
        let value = server(used: 12, expired: 3)
        let first = UsageRoast.make(provider: .claude, snapshot: value, now: now, calendar: calendar)
        XCTAssertEqual(first.headline, UsageRoast.make(provider: .claude, snapshot: value, now: now, calendar: calendar).headline)
        let variants = (0..<10).map { UsageRoast.make(provider: .claude, snapshot: value, variant: $0, now: now, calendar: calendar) }
        XCTAssertEqual(Set(variants.map(\.headline)).count, 10)
        XCTAssertTrue(variants.allSatisfy { $0.scenario == .wasted && !$0.headline.contains("{") && !$0.punchline.contains("{") })
    }
    func testAllFreeAndWorkVariantsKeepBillingScope() {
        for variant in 0..<30 {
            let free = UsageRoast.make(provider: .claude, snapshot: server(plan: "free", expired: 3), variant: variant, now: now, calendar: calendar)
            XCTAssertEqual(free.scenario, .free)
            XCTAssertFalse(free.punchline.lowercased().contains("cancel it"))
            let work = UsageRoast.make(provider: .claude, snapshot: server(plan: "Enterprise", expired: 3), variant: variant, now: now, calendar: calendar)
            XCTAssertEqual(work.scenario, .workWaste)
            XCTAssertFalse(work.punchline.lowercased().contains("cancel"))
        }
    }
    func testReportedPersonalPlanDoesNotBecomeAnotherPlanInTheRoast() {
        for variant in 0..<10 {
            let roast = UsageRoast.make(provider: .claude, snapshot: server(plan: "Pro", expired: 3), variant: variant, now: now, calendar: calendar)
            XCTAssertFalse(roast.headline.contains("Claude Max"))
            XCTAssertFalse(roast.punchline.contains("Claude Max"))
        }
    }

    func testWeekly34PercentLeftOverridesQuietShortWindowAndItsWasteHistory() {
        for plan in ["Max", "Enterprise"] {
            var value = server(used: 6, reset: 1000, plan: plan, expired: 3)
            value.quotaWindows?.append(QuotaWindow(provider: .claude, limitID: "claude:secondary", windowMinutes: 10080,
                resetsAt: now.timeIntervalSince1970 + 5 * 86400, observedAt: now.timeIntervalSince1970 - 10,
                usedPercent: 66, accountKey: "verified"))
            for variant in 0..<10 {
                let result = UsageRoast.make(provider: .claude, snapshot: value, variant: variant, now: now, calendar: calendar)
                XCTAssertEqual(result.scenario, plan == "Enterprise" ? .workActive : .active)
                XCTAssertTrue(result.evidence.contains("34% left"))
                XCTAssertTrue(result.evidence.contains("weekly"))
                XCTAssertFalse(result.evidence.contains("90%"))
                XCTAssertFalse(result.headline.contains("Token wasting"))
                XCTAssertFalse(result.headline.contains("token trashing"))
            }
        }
    }

    func testCurrentUsageImprovementTakesPrecedenceOverHistoricalWaste() {
        let result = UsageRoast.make(provider: .claude, snapshot: server(used: 66, expired: 3), now: now, calendar: calendar)
        XCTAssertEqual(result.scenario, .active)
        XCTAssertTrue(result.evidence.contains("34% left"))
        XCTAssertFalse(result.evidence.contains("near reset across"))
    }

    func testExpiringCurrentQuotaIsOnlyAHeadsUpNotAClaimOfWaste() {
        for variant in 0..<10 {
            let result = UsageRoast.make(provider: .claude, snapshot: server(used: 6, reset: 1000), variant: variant, now: now, calendar: calendar)
            XCTAssertEqual(result.scenario, .expiring)
            XCTAssertFalse(result.headline.lowercased().contains("wasting"))
            XCTAssertFalse(result.headline.lowercased().contains("trashing"))
            XCTAssertTrue(result.evidence.contains("94% left"))
        }
        let work = UsageRoast.make(provider: .claude, snapshot: server(used: 6, reset: 1000, plan: "Enterprise"), now: now, calendar: calendar)
        XCTAssertEqual(work.scenario, .workUnknown)
    }
    func testMissingWeeklyEvidenceCannotBeReplacedByShortWindowWaste() {
        var data = server(expired: 3)
        data.quotaWindows?.append(QuotaWindow(provider: .claude, limitID: "weekly", windowMinutes: 10080,
            resetsAt: now.timeIntervalSince1970 - 60, observedAt: now.timeIntervalSince1970 - 3660,
            usedPercent: 0, accountKey: "verified"))
        let result = UsageRoast.make(provider: .claude, snapshot: data, now: now, calendar: calendar)
        XCTAssertEqual(result.scenario, .missing)
        XCTAssertFalse(result.evidence.contains("90%"))
    }

}
