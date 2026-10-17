import XCTest
@testable import BubbleTaxBarCore

final class PortfolioReviewTests: XCTestCase {
    let base = AllocationTests()
    func history(_ d: inout AppData) {
        for i in 0..<3 {
            var w = d.snapshot!.quotaWindows![3]
            w.resetsAt = base.now.timeIntervalSince1970 - 86400 - Double(i) * 604800
            w.observedAt = w.resetsAt - 60; w.usedPercent = 20
            d.snapshot?.quotaWindows?.append(w)
        }
    }
    func testPersistentUnusedCapacityNeedsThreeResets() {
        var d = base.fixture(); history(&d)
        XCTAssertEqual(PortfolioReview.rows(data: d, now: base.now).first(where: { $0.provider == .openai })?.action, .compare)
        d.snapshot?.quotaWindows?.removeLast()
        XCTAssertEqual(PortfolioReview.rows(data: d, now: base.now).first(where: { $0.provider == .openai })?.action, .observe)
    }
    func testReservationsAndBurstNeedsOverrideQuietWeeks() {
        var d = base.fixture(); history(&d)
        let w = d.snapshot!.quotaWindows![3]
        d.quotaReservations = [QuotaReservation(provider: .openai, accountKey: "openai", planLabel: "Plus", limitID: w.limitID,
            resetsAt: w.resetsAt, title: "Launch", deadline: base.now.addingTimeInterval(86400), percent: 30)]
        XCTAssertEqual(PortfolioReview.rows(data: d, now: base.now).first(where: { $0.provider == .openai })?.action, .protect)
        d.quotaReservations = []; d.snapshot?.quotaWindows?[2].usedPercent = 98
        XCTAssertEqual(PortfolioReview.rows(data: d, now: base.now).first(where: { $0.provider == .openai })?.action, .keep)
    }
    func testStaleAndWorkspaceCostsStaySeparate() {
        var d = base.fixture(); history(&d); d.scannedAt = base.now.addingTimeInterval(-1000)
        let row = PortfolioReview.rows(data: d, now: base.now).first(where: { $0.provider == .openai })
        XCTAssertEqual(row?.action, .observe); XCTAssertNil(row?.monthlyListPrice)
        d.scannedAt = base.now; d.snapshot?.connections?[1].planLabel = "Enterprise"
        XCTAssertNil(PortfolioReview.rows(data: d, now: base.now).first(where: { $0.provider == .openai }))
        let work = PortfolioReview.rows(data: d, workAccount: true, now: base.now).first
        XCTAssertEqual(work?.action, .seat); XCTAssertNil(work?.monthlyListPrice)
    }
}
