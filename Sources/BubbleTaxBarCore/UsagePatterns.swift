import Foundation

/// Local metadata observations, never task-quality or account-wide efficiency scores.
public struct UsagePatternSummary {
    public let requests: Int
    public let knownRequests: Int
    public let largeNewInputs: Int
    public let inputTokens: Int
    public let reusedTokens: Int
    public let totalTokens: Int
    public let models: [(name: String, tokens: Int)]
    public var reuseShare: Double? { inputTokens > 0 ? Double(reusedTokens) / Double(inputTokens) : nil }
    public static func make(events: [ModelUsageEvent], provider: Provider, now: Date = Date()) -> Self {
        let recent = WindowModelActivity.archive([], incoming: events, now: now).filter {
            $0.provider == provider && $0.timestamp >= now.timeIntervalSince1970 - 7 * 86400
        }
        let known = recent.filter { $0.breakdownKnown != false && $0.input + $0.output + $0.cacheRead + $0.cacheWrite == $0.tokens }
        let grouped = Dictionary(grouping: recent, by: { $0.model ?? "Unknown model" })
        var models: [(name: String, tokens: Int)] = []
        for (name, values) in grouped { models.append((name: name, tokens: values.reduce(0) { $0 + $1.tokens })) }
        models.sort { a, b in a.tokens == b.tokens ? a.name < b.name : a.tokens > b.tokens }
        return Self(requests: recent.count, knownRequests: known.count,
            largeNewInputs: known.filter { $0.input + $0.cacheWrite >= 32_000 }.count,
            inputTokens: known.reduce(0) { $0 + $1.input + $1.cacheRead + $1.cacheWrite },
            reusedTokens: known.reduce(0) { $0 + $1.cacheRead }, totalTokens: recent.reduce(0) { $0 + $1.tokens }, models: models)
    }
}
