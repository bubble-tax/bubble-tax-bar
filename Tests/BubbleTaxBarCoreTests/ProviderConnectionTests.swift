import XCTest
@testable import BubbleTaxBarCore

final class ProviderConnectionTests: XCTestCase {
    func testOrganizationPlanDetectionNeedsExplicitProviderLabel() {
        for plan in ["enterprise", "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based", "ChatGPT Business", "Copilot Business", "Claude Teams", "Gemini Enterprise"] {
            XCTAssertEqual(PlanContext.classify(plan), .organization)
        }
        for plan in [nil, "oauth", "my-company@example.com", "teamwork", "unknown"] {
            XCTAssertEqual(PlanContext.classify(plan), .unknown)
        }
        XCTAssertEqual(PlanContext.classify("Cursor Free"), .free)
        XCTAssertEqual(PlanContext.classify("plus"), .personal)
        XCTAssertEqual(PlanContext.classify("copilot_student"), .free)
        XCTAssertEqual(PlanContext.classify("individual_pro"), .personal)
    }
    func testWorkPlanRoastDoesNotAskUserToCancelPersonalSubscription() {
        let roast = UsageRoast.make(provider: .copilot, snapshot: nil, context: .organization)
        XCTAssertEqual(roast.scenario, .workUnknown)
        XCTAssertTrue(roast.punchline.contains("seat"))
        XCTAssertFalse(roast.punchline.contains("cancel it"))
        XCTAssertTrue(roast.uncertain)
    }
    func testFreePlanDoesNotSuggestCancellation() {
        let roast = UsageRoast.make(provider: .cursor, snapshot: nil, context: .free)
        XCTAssertEqual(roast.status, "FREE PLAN")
        XCTAssertFalse(roast.punchline.contains("cancel it"))
    }
    func testQuotaHistoryIsSeparatedByAccountAndBudgetBucket() {
        var first = QuotaWindow(provider: .cursor, limitID: "cursor:primary", windowMinutes: 300,
            resetsAt: 2_000_001_000, observedAt: 2_000_000_000, usedPercent: 20, accountKey: "account-a")
        var second = first; second.accountKey = "account-b"; second.usedPercent = 70
        var third = first; third.limitID = "cursor:secondary"; third.usedPercent = 40
        let compacted = QuotaUsage.compact([first, second, third])
        XCTAssertEqual(compacted.count, 3)
        first.usedPercent = 30
        XCTAssertEqual(QuotaUsage.compact([first, second, third]).count, 3)
    }
}
