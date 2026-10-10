import XCTest
@testable import BubbleTaxBarCore

final class MenuBarQuotaTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func data() -> AppData {
        var data = AppData()
        data.enabledProviders = [.openai, .claude]
        data.scannedAt = now
        data.snapshot = CollectorSnapshot(days: [], sources: [], quotaWindows: [], connections: [
            ProviderConnection(provider: .openai, status: "connected", source: "oauth", planLabel: "Plus", accountKey: "openai"),
            ProviderConnection(provider: .claude, status: "connected", source: "oauth", planLabel: "Max 5x", accountKey: "claude")])
        return data
    }
    func quota(_ provider: Provider, minutes: Int = 10080, used: Double, reset: Double = 1000, observed: Double = -10) -> QuotaWindow {
        QuotaWindow(provider: provider, windowMinutes: minutes, resetsAt: now.timeIntervalSince1970 + reset,
                    observedAt: now.timeIntervalSince1970 + observed, usedPercent: used, accountKey: provider.rawValue)
    }
    func testWeeklyLeftWinsOverQuietSession() {
        var data = data()
        data.snapshot?.quotaWindows = [quota(.openai, used: 66), quota(.openai, minutes: 300, used: 0)]
        XCTAssertEqual(MenuBarQuota.make(data: data, now: now).title, "† Codex · Weekly quota 34% left")
    }
    func testReviewCandidateWinsOverDefaultServiceOrder() {
        var data = data()
        data.snapshot?.quotaWindows = [quota(.openai, used: 66), quota(.claude, used: 10)] +
            (0..<3).map { quota(.claude, used: 10, reset: -60 - Double($0) * 604800,
                              observed: -120 - Double($0) * 604800) }
        XCTAssertEqual(MenuBarQuota.make(data: data, now: now).title, "† Claude · Weekly quota 90% left")
    }
    func testStaleExpiredAndPreviousAccountAreHidden() {
        var data = data()
        for reading in [quota(.openai, used: 10, observed: -901), quota(.openai, used: 10, reset: -1)] {
            data.snapshot?.quotaWindows = [reading]
            XCTAssertEqual(MenuBarQuota.make(data: data, now: now).title, "†")
        }
        var previous = quota(.openai, used: 10); previous.accountKey = "old-account"
        data.snapshot?.quotaWindows = [previous]
        XCTAssertEqual(MenuBarQuota.make(data: data, now: now).title, "†")
    }
    func testMissingWeeklyDoesNotSubstituteSessionAndDisabledServiceIsHidden() {
        var data = data()
        data.snapshot?.quotaWindows = [quota(.openai, used: 10, observed: -901), quota(.openai, minutes: 300, used: 0)]
        XCTAssertEqual(MenuBarQuota.make(data: data, now: now).title, "†")
        data.enabledProviders = []
        XCTAssertEqual(MenuBarQuota.make(data: data, now: now).title, "†")
    }
    func testRotationContainsOnlyIdentifiedPaidPlansIncludingWork() {
        var data = data()
        data.snapshot?.quotaWindows = [quota(.openai, used: 66), quota(.claude, used: 10)]
        XCTAssertEqual(MenuBarQuota.entries(data: data, now: now).map(\.provider), [.openai, .claude])
        for label in ["Free", "Student", "Unknown"] {
            data.snapshot?.connections?[0].planLabel = label
            XCTAssertEqual(MenuBarQuota.entries(data: data, now: now).map(\.provider), [.claude])
        }
        data.snapshot?.connections?[0].planLabel = "Enterprise"
        XCTAssertEqual(MenuBarQuota.entries(data: data, now: now).count, 2)
        data.snapshot?.connections?[0].accountKey = nil
        XCTAssertEqual(MenuBarQuota.entries(data: data, now: now).map(\.provider), [.claude])
    }
    func testCompletedCancellationAndExpiryLeaveRotation() throws {
        var data = data()
        data.snapshot?.quotaWindows = [quota(.openai, used: 66), quota(.claude, used: 10, reset: 5)]
        let connection = try XCTUnwrap(data.snapshot?.connections?.first)
        data.subscriptionChanges = [try XCTUnwrap(SubscriptionChange.make(connection: connection, kind: .cancelled, now: now))]
        XCTAssertEqual(MenuBarQuota.entries(data: data, now: now).map(\.provider), [.claude])
        XCTAssertTrue(MenuBarQuota.entries(data: data, now: now.addingTimeInterval(6)).isEmpty)
    }
}
