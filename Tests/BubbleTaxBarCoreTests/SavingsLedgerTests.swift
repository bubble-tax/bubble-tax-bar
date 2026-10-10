import XCTest
@testable import BubbleTaxBarCore

final class SavingsLedgerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func connection(_ plan: String = "Max 5x", account: String = "account") -> ProviderConnection {
        ProviderConnection(provider: .claude, status: "connected", source: "oauth", planLabel: plan,
            accountKey: account, observedAt: now.timeIntervalSince1970)
    }
    func testCancellationUsesListPriceNotUnusedPercentOrInvoice() throws {
        var paid = connection()
        paid.verifiedMonthlyCost = VerifiedMonthlyCost(amount: 110, currency: "USD", accountKey: "account", observedAt: now.timeIntervalSince1970)
        let record = try XCTUnwrap(SubscriptionChange.make(connection: paid, kind: .cancelled, now: now))
        XCTAssertEqual(record.beforeMonthlyUSD, 100)
        XCTAssertEqual(record.monthlyReduction, 100)
        XCTAssertEqual(record.toPlan, "No paid plan")
        XCTAssertEqual(try JSONDecoder().decode(SubscriptionChange.self, from: JSONEncoder().encode(record)), record)
    }
    func testDowngradeChainDoesNotDoubleCountAndUndoRestoresPriorEstimate() throws {
        let down = try XCTUnwrap(SubscriptionChange.make(connection: connection(), kind: .downgraded, targetPlan: "Pro", now: now))
        XCTAssertEqual(down.monthlyReduction, 80)
        let cancel = try XCTUnwrap(SubscriptionChange.make(connection: connection(), kind: .cancelled, previous: down, now: now.addingTimeInterval(1)))
        XCTAssertEqual(cancel.beforeMonthlyUSD, 20)
        XCTAssertEqual(SavingsLedger.monthlyReduction([down, cancel]), 100)
        XCTAssertEqual(SavingsLedger.monthlyReduction([down]), 80)
        XCTAssertNil(SubscriptionChange.make(connection: connection(), kind: .cancelled, previous: cancel, now: now.addingTimeInterval(2)))
    }
    func testWorkFreeUnknownAndAmbiguousPricesCannotFabricateSavings() throws {
        XCTAssertNil(SubscriptionChange.make(connection: connection("Free"), kind: .cancelled, now: now))
        XCTAssertNil(SubscriptionChange.make(connection: connection("Enterprise"), kind: .cancelled, now: now))
        let work = try XCTUnwrap(SubscriptionChange.make(connection: connection("Enterprise"), kind: .releasedSeat, now: now))
        XCTAssertNil(work.monthlyReduction)
        for plan in ["Individual", "Max", "Unknown"] {
            let record = try XCTUnwrap(SubscriptionChange.make(connection: connection(plan), kind: .cancelled, now: now))
            XCTAssertNil(record.monthlyReduction)
            XCTAssertEqual(SavingsLedger.monthlyReduction([record]), 0)
        }
        XCTAssertNil(SubscriptionChange.make(connection: connection(), kind: .releasedSeat, now: now))
        XCTAssertNil(SubscriptionChange.make(connection: connection("Pro"), kind: .downgraded, targetPlan: "Max 5x", now: now))
        XCTAssertNil(SubscriptionChange.make(connection: connection(), kind: .downgraded, targetPlan: "invented", now: now))
    }
    func testMovingToFreeCannotBeCountedAgainAsCancellation() throws {
        let free = try XCTUnwrap(SubscriptionChange.make(connection: connection(), kind: .downgraded, targetPlan: "Free", now: now))
        XCTAssertEqual(free.monthlyReduction, 100)
        XCTAssertNil(SubscriptionChange.make(connection: connection(), kind: .cancelled, previous: free, now: now.addingTimeInterval(1)))
    }
    func testAccountChangesKeepChainsSeparate() throws {
        let first = try XCTUnwrap(SubscriptionChange.make(connection: connection(account: "a"), kind: .cancelled, now: now))
        let second = try XCTUnwrap(SubscriptionChange.make(connection: connection(account: "b"), kind: .downgraded, targetPlan: "Pro", previous: first, now: now.addingTimeInterval(1)))
        XCTAssertEqual(second.monthlyReduction, 80)
        XCTAssertEqual(SavingsLedger.monthlyReduction([first, second]), 180)
        XCTAssertNil(SavingsLedger.latest([first], provider: .claude, accountKey: "b"))
    }
    func testReportedNewTierAndFreeKeepPriorBasisButNeverCrossAccounts() {
        let paid = connection("Max 5x", account: "a")
        let pro = connection("Pro", account: "a")
        let free = connection("Free", account: "a")
        var history = SavingsLedger.rememberPlans([], connections: [paid])
        history = SavingsLedger.rememberPlans(history, connections: [pro])
        XCTAssertEqual(SavingsLedger.recordingConnection(pro, remembered: history, records: [], kind: .downgraded)?.planLabel, "Max 5x")
        XCTAssertEqual(SavingsLedger.recordingConnection(pro, remembered: history, records: [])?.planLabel, "Pro")
        XCTAssertEqual(SavingsLedger.recordingConnection(free, remembered: history, records: [])?.planLabel, "Pro")
        XCTAssertNil(SavingsLedger.recordingConnection(connection("Free", account: "b"), remembered: history, records: []))
        var anonymous = connection("Free"); anonymous.accountKey = nil
        XCTAssertNil(SavingsLedger.recordingConnection(anonymous, remembered: history, records: []))
        XCTAssertEqual(SavingsLedger.rememberPlans(history, connections: [free]).count, 2)
    }
    func testLegacyStateDecodesWithoutNewFields() throws {
        let data = try JSONDecoder().decode(AppData.self, from: Data("{\"version\":1,\"subscriptions\":[]}".utf8))
        XCTAssertNil(data.subscriptionChanges)
        XCTAssertNil(data.reviewFirst)
        XCTAssertNil(data.recordingPlans)
    }
    func testReviewOrderIsStableAndExcludesCompletedFreeAndStale() throws {
        let providers: [Provider] = [.cursor, .claude, .openai]
        let paid = connection()
        let free = ProviderConnection(provider: .cursor, status: "connected", source: "oauth", planLabel: "Free", accountKey: "free")
        let active = ProviderConnection(provider: .openai, status: "connected", source: "oauth", planLabel: "Plus", accountKey: "active")
        let history = (0..<3).map { index -> QuotaWindow in
            let end = now.timeIntervalSince1970 - 60 - Double(index) * 18000
            return QuotaWindow(provider: .claude, limitID: "primary", windowMinutes: 300,
                resetsAt: end, observedAt: end - 60, usedPercent: 10, accountKey: "account")
        }
        let snapshot = CollectorSnapshot(days: [], sources: [], quotaWindows: history + [
            QuotaWindow(provider: .openai, limitID: "weekly", windowMinutes: 10080,
                resetsAt: now.timeIntervalSince1970 + 10000, observedAt: now.timeIntervalSince1970 - 10, usedPercent: 66, accountKey: "active")], connections: [free, paid, active])
        XCTAssertEqual(ReviewPriority.ordered(providers, snapshot: snapshot, fresh: true, changes: [], now: now), [.claude, .cursor, .openai])
        XCTAssertEqual(ReviewPriority.ordered(providers, snapshot: snapshot, fresh: false, changes: [], now: now), providers)
        let record = try XCTUnwrap(SubscriptionChange.make(connection: paid, kind: .cancelled, now: now))
        XCTAssertEqual(ReviewPriority.ordered(providers, snapshot: snapshot, fresh: true, changes: [record], now: now), providers)
    }
}
