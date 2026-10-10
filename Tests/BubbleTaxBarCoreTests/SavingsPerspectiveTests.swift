import XCTest
@testable import BubbleTaxBarCore

final class SavingsPerspectiveTests: XCTestCase {
    func testProjectedPeriodsShareTheSameAnnualBudget() throws {
        XCTAssertEqual(try XCTUnwrap(SavingsPeriod.week.amount(monthly: 80)) * 52, 960, accuracy: 0.0001)
        XCTAssertEqual(SavingsPeriod.month.amount(monthly: 80), 80)
        XCTAssertEqual(SavingsPeriod.year.amount(monthly: 80), 960)
        for invalid in [0.0, -1, .infinity, .nan] {
            for period in SavingsPeriod.allCases {
                XCTAssertNil(RealWorldSavings.make(monthly: invalid, period: period))
            }
        }
        XCTAssertNil(SavingsPeriod.year.amount(monthly: .greatestFiniteMagnitude))
    }
    func testIdeasChangeWithTheActualPeriodBudget() throws {
        XCTAssertEqual(try XCTUnwrap(RealWorldSavings.make(monthly: 80, period: .week)).symbol, "fork.knife")
        XCTAssertEqual(try XCTUnwrap(RealWorldSavings.make(monthly: 80, period: .month)).symbol, "person.2")
        XCTAssertEqual(try XCTUnwrap(RealWorldSavings.make(monthly: 80, period: .year)).symbol, "airplane")
    }
    func testComparisonUsesOnlyStrictlyCheaperCatalogTiers() {
        let options = DowngradeOption.cheaper(provider: .claude, currentPrice: 200)
        XCTAssertEqual(options.map(\.label), ["Max 5x", "Pro", "Free"])
        XCTAssertEqual(options.map(\.monthlyPrice), [100, 20, 0])
        XCTAssertTrue(DowngradeOption.cheaper(provider: .claude, currentPrice: 0).isEmpty)
        XCTAssertTrue(DowngradeOption.cheaper(provider: .claude, currentPrice: .nan).isEmpty)
        XCTAssertNil(PlanPricing.lookup(provider: .claude, label: "Enterprise")?.exact)
        XCTAssertNil(PlanPricing.lookup(provider: .claude, label: "Max")?.exact)
    }
}
