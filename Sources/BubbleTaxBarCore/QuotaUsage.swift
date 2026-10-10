import Foundation

public struct QuotaWindow: Codable, Equatable {
    public var provider: Provider
    public var limitID: String
    public var windowMinutes: Int
    public var resetsAt: Double
    public var observedAt: Double
    public var usedPercent: Double
    public var accountKey: String?
    public var windowLabel: String?
    public var interrupted: Bool?

    public init(provider: Provider, limitID: String = "codex", windowMinutes: Int,
                resetsAt: Double, observedAt: Double, usedPercent: Double, accountKey: String? = nil, windowLabel: String? = nil) {
        self.provider = provider; self.limitID = limitID; self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt; self.observedAt = observedAt; self.usedPercent = usedPercent
        self.accountKey = accountKey; self.windowLabel = windowLabel
    }
    public var remainingPercent: Double { 100 - usedPercent }
    public var resetDate: Date { Date(timeIntervalSince1970: resetsAt) }
    public var observedDate: Date { Date(timeIntervalSince1970: observedAt) }
}

public struct QuotaUsage: Identifiable {
    public var id: String { "\(accountKey ?? "local")-\(limitID)-\(windowMinutes)" }
    public let limitID: String
    public let windowMinutes: Int
    public let windowLabel: String?
    public let accountKey: String?
    public let current: QuotaWindow?
    public let expired: [QuotaWindow]
    // Require an identified account and a recent pre-reset observation.
    // Early replacement windows and usage decreases may be manual resets.
    public var eligibleExpired: [QuotaWindow] {
        expired.filter { $0.accountKey != nil && $0.interrupted != true && $0.resetsAt - $0.observedAt <= 900 }
    }
    public var averageUnused: Double? {
        let readings = eligibleExpired
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0) { $0 + $1.remainingPercent } / Double(readings.count)
    }
    public var latestExpired: QuotaWindow? { eligibleExpired.last }
    public var title: String {
        if let windowLabel { return windowLabel }
        switch windowMinutes {
        case 300: return "5-hour quota"
        case 10080: return "Weekly quota"
        case 1440: return "Daily quota"
        case 43200: return "Monthly quota"
        default: return "\(windowMinutes) min quota"
        }
    }

    /// Use the widest reported budget for plan-level judgments. Missing history
    /// in that budget must not be replaced by a quiet short-window sample.
    public static func representative(_ quotas: [QuotaUsage]) -> QuotaUsage? {
        quotas.sorted {
            $0.windowMinutes == $1.windowMinutes ? $0.limitID < $1.limitID : $0.windowMinutes > $1.windowMinutes
        }.first
    }

    public static func compact(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        var result: [QuotaWindow] = []
        let groups = Dictionary(grouping: windows, by: { "\($0.provider.rawValue)-\($0.accountKey ?? "local")-\($0.limitID)-\($0.windowMinutes)" })
        for values in groups.values {
            var cluster: [QuotaWindow] = []
            func latest(_ readings: [QuotaWindow]) -> QuotaWindow {
                var value = readings.max {
                    $0.observedAt == $1.observedAt ? $0.usedPercent < $1.usedPercent : $0.observedAt < $1.observedAt
                }!
                let ordered = readings.sorted { $0.observedAt < $1.observedAt }
                if readings.contains(where: { $0.interrupted == true }) || zip(ordered, ordered.dropFirst()).contains(where: {
                    $1.observedAt > $0.observedAt && $1.usedPercent + 1 < $0.usedPercent
                }) { value.interrupted = true }
                // A replacement arrived before this window's scheduled end.
                if values.contains(where: { $0.observedAt > value.observedAt &&
                    $0.observedAt < value.resetsAt - 60 && abs($0.resetsAt - value.resetsAt) > 60 }) {
                    value.interrupted = true
                }
                return value
            }
            for reading in values.sorted(by: { $0.resetsAt < $1.resetsAt }) {
                if let first = cluster.first, reading.resetsAt - first.resetsAt > 60 {
                    result.append(latest(cluster)); cluster = []
                }
                cluster.append(reading)
            }
            if !cluster.isEmpty { result.append(latest(cluster)) }
        }
        return result.sorted { $0.resetsAt < $1.resetsAt }
    }

    public static func summaries(provider: Provider, windows: [QuotaWindow], now: Date = Date()) -> [QuotaUsage] {
        let time = now.timeIntervalSince1970
        let cutoff = time - 30 * 86400
        let valid = windows.filter {
            $0.provider == provider && $0.windowMinutes > 0 && $0.usedPercent.isFinite &&
            (0...100).contains($0.usedPercent) && $0.observedAt.isFinite && $0.resetsAt.isFinite &&
            $0.observedAt <= time && $0.observedAt < $0.resetsAt && $0.resetsAt >= cutoff
        }
        return Dictionary(grouping: valid, by: { "\($0.accountKey ?? "local")-\($0.limitID)-\($0.windowMinutes)" }).values.map { readings in
            let unique = compact(readings)
            let latest = readings[0]
            let current = unique.filter { $0.resetsAt > time && time - $0.observedAt <= 900 }.max { $0.observedAt < $1.observedAt }
            return QuotaUsage(limitID: latest.limitID, windowMinutes: latest.windowMinutes,
                              windowLabel: latest.windowLabel, accountKey: latest.accountKey, current: current, expired: unique.filter { $0.resetsAt <= time })
        }.sorted { ($0.windowMinutes, $0.limitID) < ($1.windowMinutes, $1.limitID) }
    }
}
