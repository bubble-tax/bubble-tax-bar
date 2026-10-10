import XCTest
@testable import BubbleTaxBarCore

final class PlanPricingTests: XCTestCase {
    func testSpecificTiersAndProviderPrices() {
        for (provider, label, expected): (Provider, String, Double) in [
            (.openai, "ChatGPT Plus", 20), (.openai, "Pro 500", 500), (.openai, "pro100", 100),
            (.openai, "Go", 8), (.claude, "Max 5x", 100), (.claude, "Max 20x", 200),
            (.cursor, "Pro+", 60), (.copilot, "individual_pro_plus", 39), (.copilot, "Max", 100),
            (.antigravity, "Google AI Pro", 19.99), (.antigravity, "Ultra 20x", 200)] {
            XCTAssertEqual(PlanPricing.lookup(provider: provider, label: label)?.exact, expected, label)
        }
    }
    func testAmbiguousTiersCannotBecomeExactCharges() {
        XCTAssertNil(PlanPricing.lookup(provider: .claude, label: "Max")?.exact)
        XCTAssertEqual(PlanPricing.lookup(provider: .claude, label: "Max")?.minimum, 100)
        XCTAssertEqual(PlanPricing.lookup(provider: .claude, label: "Max")?.maximum, 200)
        XCTAssertEqual(PlanPricing.lookup(provider: .openai, label: "Pro")?.maximum, 500)
        for label in ["Enterprise Pro", "Teams", "Free", "student", "oauth", "unknown"] {
            XCTAssertNil(PlanPricing.lookup(provider: .copilot, label: label))
        }
    }
    func testCatalogWeightsKnownTiersAndKeepsAmbiguousTotalsAsRanges() {
        let fixture = SubscriptionPersonaTests()
        let windows = [fixture.window(.claude, unused: 90), fixture.window(.openai, unused: 10)]
        let connections = [fixture.connection(.claude, plan: "Max 5x"), fixture.connection(.openai, plan: "Plus")]
        let exact = PersonaAssessment.make(snapshot: fixture.snapshot(connections, windows), now: fixture.now)
        XCTAssertEqual(exact.monthlyTotal, 120)
        XCTAssertEqual(exact.remainingPercent!, 76.6667, accuracy: 0.001)
        XCTAssertTrue(exact.priceWeighted)
        XCTAssertTrue(exact.usesListPrices)
        let vague = PersonaAssessment.make(snapshot: fixture.snapshot([
            fixture.connection(.claude, plan: "Max"), fixture.connection(.openai, plan: "Plus")], windows), now: fixture.now)
        XCTAssertEqual(vague.monthlyRange, 120...220)
        XCTAssertNil(vague.monthlyTotal)
        XCTAssertFalse(vague.priceWeighted)
        XCTAssertEqual(vague.remainingPercent, 50)
    }
}
