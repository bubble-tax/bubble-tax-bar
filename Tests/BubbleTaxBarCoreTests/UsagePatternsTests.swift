import XCTest
@testable import BubbleTaxBarCore

final class UsagePatternsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func event(_ id: String, input: Int = 40000, read: Int = 60000, write: Int = 0) -> ModelUsageEvent {
        ModelUsageEvent(id: id, provider: .claude, timestamp: now.timeIntervalSince1970 - 100, model: "claude-model",
                        input: input, output: 100, cacheRead: read, cacheWrite: write, tokens: input + read + write + 100, breakdownKnown: true)
    }
    func testReusedTokensAreNotNewInputsOrDoubleCounted() {
        let s = UsagePatternSummary.make(events: [event("1"), event("2"), event("3")], provider: .claude, now: now)
        XCTAssertEqual(s.largeNewInputs, 3); XCTAssertEqual(s.reuseShare, 0.6); XCTAssertEqual(s.requests, 3)
        let cached = UsagePatternSummary.make(events: [event("cached", input: 100, read: 100000)], provider: .claude, now: now)
        XCTAssertEqual(cached.largeNewInputs, 0)
    }
    func testUnknownBreakdownsAndDuplicateEventsDoNotInventPatterns() {
        let row = event("one"); var unknown = event("unknown"); unknown.breakdownKnown = false
        let s = UsagePatternSummary.make(events: [row, row, unknown], provider: .claude, now: now)
        XCTAssertEqual(s.requests, 2); XCTAssertEqual(s.knownRequests, 1)
        XCTAssertEqual(UsagePatternSummary.make(events: [row], provider: .openai, now: now).requests, 0)
    }
}
