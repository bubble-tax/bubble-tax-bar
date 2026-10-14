import Foundation

/// Metadata from local code logs. Account ownership and complete account-wide
/// coverage are not verified, so this is context, never quota attribution.
public struct ModelUsageEvent: Codable, Equatable {
    public let id: String
    public let provider: Provider
    public let timestamp: Double
    public let model: String?
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public let tokens: Int
    public var breakdownKnown: Bool? = nil
}

public struct ModelUsageSummary: Identifiable {
    public var id: String { model ?? "unknown" }
    public let model: String?
    public let tokens: Int
    public let requests: Int
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public let breakdownKnown: Bool
    public var title: String { model ?? "Unknown model" }
}

public enum WindowModelActivity {
    public static func archive(_ existing: [ModelUsageEvent], incoming: [ModelUsageEvent], now: Date = Date()) -> [ModelUsageEvent] {
        let time = now.timeIntervalSince1970
        var records: [String: ModelUsageEvent] = [:]
        for event in existing + incoming where [.claude, .openai].contains(event.provider) &&
            event.timestamp.isFinite && event.timestamp <= time && event.timestamp >= time - 180 * 86400 &&
            event.tokens > 0 && event.tokens <= 1_000_000_000 &&
            [event.input, event.output, event.cacheRead, event.cacheWrite].allSatisfy({ (0...1_000_000_000).contains($0) }) {
            let key = event.provider.rawValue + ":" + event.id
            if let old = records[key], old.timestamp > event.timestamp || old.tokens > event.tokens { continue }
            records[key] = event
        }
        // A bounded archive also bounds menu rendering and state-file growth.
        return Array(records.values.sorted { $0.timestamp < $1.timestamp }.suffix(20_000))
    }

    public static func summaries(_ events: [ModelUsageEvent], window: WindowComparison) -> [ModelUsageSummary] {
        let local = events.filter { $0.provider == window.first.session.provider &&
            $0.timestamp > window.first.observedAt && $0.timestamp <= window.last.observedAt }
        return Dictionary(grouping: local, by: { $0.model ?? "" }).map { key, values in
            ModelUsageSummary(model: key.isEmpty ? nil : key,
                tokens: values.reduce(0) { $0 + $1.tokens }, requests: values.count,
                input: values.reduce(0) { $0 + $1.input }, output: values.reduce(0) { $0 + $1.output },
                cacheRead: values.reduce(0) { $0 + $1.cacheRead }, cacheWrite: values.reduce(0) { $0 + $1.cacheWrite },
                breakdownKnown: values.allSatisfy { $0.breakdownKnown != false && $0.input + $0.output + $0.cacheRead + $0.cacheWrite == $0.tokens })
        }.sorted { $0.tokens == $1.tokens ? $0.title < $1.title : $0.tokens > $1.tokens }
    }
}
