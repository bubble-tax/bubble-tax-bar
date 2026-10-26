import XCTest
@testable import BubbleTaxBarCore

final class ClaudeLocalQuotaJournalTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func entry(_ time: Double, stream: String = String(repeating: "a", count: 64), used: Double = 10) -> [String: Any] {
        ["streamID": stream, "windows": [
            ["provider": "claude", "limitID": "claude:primary", "windowMinutes": 300,
             "observedAt": time, "resetsAt": 2_000_000_000 + 1800, "usedPercent": used],
            ["provider": "claude", "limitID": "claude:secondary", "windowMinutes": 10080,
             "observedAt": time, "resetsAt": 2_000_000_000 + 86400, "usedPercent": used / 10]]]
    }
    func testImportOfflineJournalAndDeduplicateWithoutVerifiedOwnership() throws {
        let bytes = try JSONSerialization.data(withJSONObject: [entry(1_999_999_100), entry(1_999_999_400, used: 40)])
        let samples = ClaudeLocalQuotaJournal.merge([], data: bytes, now: now)
        XCTAssertEqual(samples.count, 2)
        XCTAssertTrue(samples.allSatisfy { $0.isLocalStream && $0.planLabel == nil })
        XCTAssertEqual(ClaudeLocalQuotaJournal.merge(samples, data: bytes, now: now), samples)
        let rows = WindowQuotaHistory.comparisons(samples, now: now)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].weeklyPerFullSession, 10)
    }
    func testSessionsNeverJoinAndCorruptOrMissingIdentityIsRejected() throws {
        let bytes = try JSONSerialization.data(withJSONObject: [entry(1_999_999_100),
            entry(1_999_999_400, stream: String(repeating: "b", count: 64), used: 40),
            entry(1_999_999_500, stream: "not-a-session-hash"), entry(2_000_000_001)])
        let samples = ClaudeLocalQuotaJournal.merge([], data: bytes, now: now)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(WindowQuotaHistory.comparisons(samples, now: now).count, 2)
        XCTAssertEqual(ClaudeLocalQuotaJournal.merge(samples, data: Data("broken".utf8), now: now), samples)
    }
    func testAccountOwnedWindowsAndOverflowingDurationsAreRejected() throws {
        var owned = entry(1_999_999_400)
        var windows = owned["windows"] as! [[String: Any]]
        windows[0]["accountKey"] = "real-account"; owned["windows"] = windows
        var invalid = entry(1_999_999_400)
        windows = invalid["windows"] as! [[String: Any]]
        windows[0]["windowMinutes"] = Int.max; invalid["windows"] = windows
        let bytes = try JSONSerialization.data(withJSONObject: [owned, invalid])
        XCTAssertTrue(ClaudeLocalQuotaJournal.merge([], data: bytes, now: now).isEmpty)
    }
}
