import XCTest
@testable import BubbleTaxBarCore

final class AllocationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func fixture() -> AppData {
        var d = AppData(); d.scannedAt = now; d.enabledProviders = [.claude, .openai]
        d.snapshot = CollectorSnapshot(days: [], sources: [], quotaWindows: [], connections: [
            ProviderConnection(provider: .claude, status: "connected", source: "test", planLabel: "Pro", accountKey: "claude"),
            ProviderConnection(provider: .openai, status: "connected", source: "test", planLabel: "Plus", accountKey: "openai")])
        for p in [Provider.claude, .openai] {
            for minutes in [300, 10080] {
                d.snapshot?.quotaWindows?.append(QuotaWindow(provider: p, limitID: (p == .claude ? "claude" : "codex") + (minutes == 300 ? ":primary" : ":secondary"), windowMinutes: minutes,
                    resetsAt: now.timeIntervalSince1970 + Double(minutes * 60), observedAt: now.timeIntervalSince1970 - 30,
                    usedPercent: p == .claude ? 85 : 25, accountKey: p.rawValue))
            }
        }; return d
    }
    func testReadyHeadroomWins() { XCTAssertEqual(Allocation.options(data: fixture(), now: now).first?.provider, .openai) }
    func testBlockedSessionCannotWin() {
        var d = fixture(); d.snapshot?.quotaWindows?[2].usedPercent = 100
        XCTAssertEqual(Allocation.options(data: d, now: now).first(where: \.ready)?.provider, .claude)
    }
    func testStaleAndChangedAccountsExcluded() {
        var d = fixture(); d.scannedAt = now.addingTimeInterval(-901)
        XCTAssertTrue(Allocation.options(data: d, now: now).isEmpty)
        d = fixture(); d.snapshot?.connections?[1].accountKey = "changed"
        XCTAssertEqual(Allocation.options(data: d, now: now).map(\.provider), [.claude])
    }
    func testWorkAndPersonalNeverMix() {
        var d = fixture(); d.snapshot?.connections?[1].planLabel = "Enterprise"
        XCTAssertEqual(Allocation.options(data: d, now: now).map(\.provider), [.claude])
        XCTAssertEqual(Allocation.options(data: d, workAccount: true, now: now).map(\.provider), [.openai])
    }
    func testTaskEligibilityRespected() {
        var d = fixture(); var prefs = AllocationPreferences(); prefs.eligible[WorkKind.writing.rawValue] = [.claude]; d.allocationPreferences = prefs
        XCTAssertEqual(Allocation.options(data: d, work: .writing, now: now).map(\.provider), [.claude])
    }
}

extension AllocationTests {
    func reservation(_ d: AppData, percent: Double = 15) -> QuotaReservation {
        let w = d.snapshot!.quotaWindows![1]
        return QuotaReservation(provider: .claude, accountKey: "claude", planLabel: "Pro", limitID: w.limitID,
            resetsAt: w.resetsAt, title: "Release review", deadline: now.addingTimeInterval(86400), percent: percent)
    }
    func testReservationProtectsAccountAndResetSpecificBudget() {
        var d = fixture(); d.quotaReservations = [reservation(d)]
        XCTAssertEqual(Allocation.options(data: d, now: now).first(where: { $0.provider == .claude })?.available, 0)
        d.quotaReservations?[0].accountKey = "other"
        XCTAssertEqual(Allocation.options(data: d, now: now).first(where: { $0.provider == .claude })?.available, 15)
    }
    func testCannotOverbookOrReservePastReset() {
        let d = fixture(), w = d.snapshot!.quotaWindows![1], c = d.snapshot!.connections![0]
        var record = reservation(d, percent: 16)
        XCTAssertNotNil(ReservationValidation.issue(record, current: w, connection: c, existing: [], now: now))
        record.percent = 10; record.deadline = w.resetDate.addingTimeInterval(1)
        XCTAssertNotNil(ReservationValidation.issue(record, current: w, connection: c, existing: [], now: now))
        record.deadline = now.addingTimeInterval(100)
        XCTAssertNil(ReservationValidation.issue(record, current: w, connection: c, existing: [], now: now))
    }
    func testCompletedAndExpiredReservationsReleaseTargets() {
        var d = fixture(); var record = reservation(d); record.completedAt = now; d.quotaReservations = [record]
        XCTAssertEqual(Allocation.options(data: d, now: now).first(where: { $0.provider == .claude })?.protected, 0)
        record.completedAt = nil; record.deadline = now.addingTimeInterval(-1); d.quotaReservations = [record]
        XCTAssertEqual(Allocation.options(data: d, now: now).first(where: { $0.provider == .claude })?.protected, 0)
    }
}

extension AllocationTests {
    func measured(_ d: AppData) -> [WindowQuotaSample] {
        let option = Allocation.options(data: d, now: now).first { $0.provider == .claude }!
        return (0..<5).map { i in
            var short = option.session!, weekly = option.weekly
            short.observedAt = now.timeIntervalSince1970 - 3630 + Double(i * 900)
            weekly.observedAt = short.observedAt
            short.usedPercent = Double(10 + i * 10); weekly.usedPercent = Double(83) + Double(i) * 0.5
            return WindowQuotaSample(accountKey: "claude", planLabel: "Pro", session: short, weekly: weekly)
        }
    }
    func testForecastUsesExplicitDailyPlanAndProtectedFloor() {
        var d = fixture(); d.quotaReservations = [reservation(d, percent: 10)]
        let option = Allocation.options(data: d, now: now).first { $0.provider == .claude }!
        let f = QuotaForecast.make(option: option, samples: measured(d), reservations: d.quotaReservations!, hoursPerDay: 2, now: now)
        XCTAssertEqual(f?.weeklyPerDay, 4)
        XCTAssertEqual(f?.daysToProtectedFloor, 1.25)
        XCTAssertEqual(f?.reserveAtRisk, false)
    }
    func testForecastDoesNotInventMissingRatesOrUseOtherAccounts() {
        let d = fixture(), option = Allocation.options(data: fixture(), now: now).first!
        XCTAssertNil(QuotaForecast.make(option: option, samples: [], reservations: [], hoursPerDay: 2, now: now))
        XCTAssertNil(QuotaForecast.make(option: option, samples: measured(d), reservations: [], hoursPerDay: 2, now: now))
        XCTAssertNil(QuotaForecast.make(option: option, samples: measured(d), reservations: [], hoursPerDay: .nan, now: now))
    }
}

extension AllocationTests {
    func testReservationDoesNotCrossPlanOrResetAndRejectsNaN() {
        var d = fixture(); var record = reservation(d)
        record.resetsAt += 604800; d.quotaReservations = [record]
        XCTAssertEqual(Allocation.options(data: d, now: now).first(where: { $0.provider == .claude })?.protected, 0)
        record = reservation(d); record.planLabel = "Max 5x"; d.quotaReservations = [record]
        XCTAssertEqual(Allocation.options(data: d, now: now).first(where: { $0.provider == .claude })?.protected, 0)
        record = reservation(d); record.percent = .nan
        XCTAssertNotNil(ReservationValidation.issue(record, current: d.snapshot!.quotaWindows![1], connection: d.snapshot!.connections![0], existing: [], now: now))
    }
    func testStateRoundTripAndLegacyDecode() throws {
        let legacy = try JSONDecoder().decode(AppData.self, from: Data("{\"version\":1,\"subscriptions\":[]}".utf8))
        XCTAssertNil(legacy.quotaReservations); XCTAssertNil(legacy.allocationPreferences)
        var data = fixture(); data.quotaReservations = [reservation(data)]
        var prefs = AllocationPreferences(); prefs.recentWork = .writing; prefs.eligible[WorkKind.writing.rawValue] = [.claude]
        prefs.hoursPerDay["claude|claude"] = 1.5; data.allocationPreferences = prefs
        let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.quotaReservations, data.quotaReservations)
        XCTAssertEqual(decoded.allocationPreferences?.recentWork, .writing)
        XCTAssertEqual(decoded.allocationPreferences?.hoursPerDay["claude|claude"], 1.5)
    }
}
