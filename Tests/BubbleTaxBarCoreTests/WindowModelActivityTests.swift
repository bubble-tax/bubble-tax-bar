import XCTest
@testable import BubbleTaxBarCore

final class WindowModelActivityTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func sample(provider: Provider = .openai, time: Double = -60, session: Double = 30, weekly: Double = 10) -> WindowQuotaSample {
        let prefix = provider == .openai ? "codex" : "claude"
        let t = now.timeIntervalSince1970
        return WindowQuotaSample(accountKey: "a", planLabel: "Pro",
            session: QuotaWindow(provider: provider, limitID: prefix+":primary", windowMinutes: 300, resetsAt: t+1000, observedAt: t+time, usedPercent: session, accountKey: "a"),
            weekly: QuotaWindow(provider: provider, limitID: prefix+":secondary", windowMinutes: 10080, resetsAt: t+100000, observedAt: t+time, usedPercent: weekly, accountKey: "a"))
    }
    func event(_ id: String, model: String? = "gpt-5.4", provider: Provider = .openai, time: Double = -100, tokens: Int = 100) -> ModelUsageEvent {
        ModelUsageEvent(id: id, provider: provider, timestamp: now.timeIntervalSince1970+time, model: model, input: tokens/2, output: tokens/2, cacheRead: 0, cacheWrite: 0, tokens: tokens)
    }
    func testCodexPairsServerWindowsAndKeepsProvidersSeparate() throws {
        let value = sample()
        let connection = try JSONDecoder().decode(ProviderConnection.self, from: Data(#"{"provider":"openai","status":"connected","source":"oauth","accountKey":"a","planLabel":"Pro"}"#.utf8))
        let recorded = WindowQuotaHistory.record([], windows: [value.session, value.weekly], connection: connection, provider: .openai, now: now)
        XCTAssertEqual(recorded.count, 1)
        let before = sample(time: -300, session: 10, weekly: 5)
        let rows = WindowQuotaHistory.comparisons([before, value, sample(provider: .claude)], now: now)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first!.weeklyPerFullSession, 25)
        XCTAssertEqual(WindowQuotaHistory.record(recorded, windows: [value.session, value.weekly], connection: connection, provider: .openai, now: now).count, 1)
        XCTAssertTrue(ClaudeWindowHistory.record([], windows: [value.session, value.weekly], connection: connection, now: now).isEmpty)
    }
    func testModelContextUsesExactObservedIntervalAndProvider() {
        let window = WindowQuotaHistory.comparisons([sample(time: -300, session: 10), sample()], now: now)[0]
        let summaries = WindowModelActivity.summaries([event("a"), event("b", model: "gpt-5.4-mini", tokens: 20),
            event("unknown", model: nil, tokens: 10), event("outside", time: -301),
            event("boundary", time: -300), event("future", time: -59), event("claude", provider: .claude)], window: window)
        XCTAssertEqual(summaries.count, 3)
        XCTAssertEqual(summaries.reduce(0) { $0+$1.tokens }, 130)
        XCTAssertEqual(summaries.last!.title, "Unknown model")
    }
    func testArchiveUpdatesWithoutDuplicatesOrCounterRegression() {
        let values = WindowModelActivity.archive([event("a", tokens: 100)], incoming: [event("a", tokens: 200), event("b", model: nil)], now: now)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values.first { $0.id == "a" }!.tokens, 200)
        XCTAssertEqual(WindowModelActivity.archive(values, incoming: [event("a", tokens: 10)], now: now).first { $0.id == "a" }!.tokens, 200)
        XCTAssertTrue(WindowModelActivity.archive([], incoming: [event("old", time: -181*86400), event("future", time: 1), event("negative", tokens: -10)], now: now).isEmpty)
    }
    func testCachedComponentsAndUnavailableBreakdownsArePreserved() {
        var cached = ModelUsageEvent(id: "cache", provider: .openai, timestamp: now.timeIntervalSince1970-100,
            model: "gpt-5.4", input: 20, output: 10, cacheRead: 70, cacheWrite: 0, tokens: 100)
        let window = WindowQuotaHistory.comparisons([sample(time: -300), sample()], now: now)[0]
        let summary = WindowModelActivity.summaries([cached], window: window)[0]
        XCTAssertTrue(summary.breakdownKnown)
        XCTAssertEqual(summary.cacheRead, 70)
        XCTAssertEqual(summary.tokens, 100)
        cached.breakdownKnown = false
        XCTAssertFalse(WindowModelActivity.summaries([cached], window: window)[0].breakdownKnown)
    }
    func testOldStateCompatibilityAndNewRecordsRoundTrip() throws {
        let old = try JSONDecoder().decode(AppData.self, from: Data(#"{"version":1,"subscriptions":[]}"#.utf8))
        XCTAssertNil(old.codexQuotaSamples)
        XCTAssertNil(old.modelUsageArchive)
        var data = AppData(); data.claudeQuotaSamples = [sample(provider: .claude)]; data.codexQuotaSamples = [sample()]; data.modelUsageArchive = [event("a")]
        let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.claudeQuotaSamples, data.claudeQuotaSamples)
        XCTAssertEqual(decoded.codexQuotaSamples, data.codexQuotaSamples)
        XCTAssertEqual(decoded.modelUsageArchive, data.modelUsageArchive)
    }
}
