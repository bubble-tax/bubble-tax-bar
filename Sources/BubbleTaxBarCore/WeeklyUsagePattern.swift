import Foundation

public struct WeeklyUsagePattern {
    public enum Status: Equatable { case insufficient, exhausted, feasible, paceTooSlow, windowsTooFew }
    public let status: Status
    public let reason: String?
    public let remaining: Double?
    public let hoursLeft: Double?
    public let hoursNeeded: Double?
    public let hoursPerDay: Double?
    public let fullQuotasPerDay: Double?
    public let availableFullQuotas: Double?
    public let intervals: Int
    public let models: [String]

    public static func make(provider: Provider, connection: ProviderConnection?, windows: [QuotaWindow],
                            samples: [WindowQuotaSample], modelEvents: [ModelUsageEvent] = [], now: Date = Date()) -> Self {
        func missing(_ message: String) -> Self {
            Self(status: .insufficient, reason: message, remaining: nil, hoursLeft: nil, hoursNeeded: nil,
                 hoursPerDay: nil, fullQuotasPerDay: nil, availableFullQuotas: nil, intervals: 0, models: [])
        }
        guard [.claude, .openai].contains(provider), let connection, connection.provider == provider, connection.status == "connected",
              let account = connection.accountKey, !account.isEmpty else { return missing("Connect usage to estimate your weekly pattern.") }
        let prefix = provider == .claude ? "claude" : "codex"
        let current = QuotaUsage.summaries(provider: provider, windows: windows, now: now).compactMap(\.current)
        guard let weekly = current.first(where: { $0.limitID == prefix + ":secondary" && $0.windowMinutes == 10080 && $0.accountKey == account }) else {
            return missing("A fresh overall weekly reading is needed.")
        }
        let session = current.first { $0.limitID == prefix + ":primary" && $0.windowMinutes == 300 &&
            $0.accountKey == account && $0.interrupted != true && abs($0.observedAt - weekly.observedAt) <= 60 }
        let remaining = weekly.remainingPercent
        let left = (weekly.resetsAt - now.timeIntervalSince1970) / 3600
        if remaining <= 0 {
            return Self(status: .exhausted, reason: nil, remaining: 0, hoursLeft: left, hoursNeeded: 0,
                        hoursPerDay: 0, fullQuotasPerDay: 0, availableFullQuotas: nil, intervals: 0, models: [])
        }
        guard weekly.interrupted != true else { return missing("A limit reset interrupted this week's measurements.") }
        let rows = WindowQuotaHistory.comparisons(samples, now: now).filter {
            $0.first.session.provider == provider && $0.first.accountKey == account &&
            $0.first.planLabel == connection.planLabel && $0.first.weekly.limitID == weekly.limitID &&
            $0.first.weekly.windowLabel == weekly.windowLabel && abs($0.first.weekly.resetsAt - weekly.resetsAt) <= 60 &&
            $0.last.observedAt <= weekly.observedAt + 60 &&
            $0.weeklyPerFullSession != nil && $0.weeklyDelta >= 1 &&
            $0.last.observedAt - $0.first.observedAt >= 900
        }
        guard !rows.isEmpty else { return missing("More paired usage is needed before a reliable estimate.") }
        let duration = rows.reduce(0) { $0 + ($1.last.observedAt - $1.first.observedAt) / 3600 }
        let weeklyChange = rows.reduce(0) { $0 + $1.weeklyDelta }
        let sessionChange = rows.reduce(0) { $0 + $1.sessionDelta }
        let weeklyPerHour = weeklyChange / duration
        let weeklyPerFullQuota = weeklyChange / sessionChange * 100
        let needed = remaining / weeklyPerHour
        let fullQuotas = remaining / weeklyPerFullQuota
        let days = left / 24
        // Optimistic capacity: a fresh quota can be spent immediately after a
        // reset. Do not assume even consumption across its five-hour period.
        var available: Double?
        var fitsWindows = true
        if let session {
            let newWindows = ceil(max(0, weekly.resetsAt - session.resetsAt) / (300 * 60))
            available = session.remainingPercent / 100 + newWindows
            // Use the best observed conversion for an optimistic capacity check.
            let bestWeeklyPerQuota = rows.compactMap(\.weeklyPerFullSession).max()!
            fitsWindows = remaining <= available! * bestWeeklyPerQuota + 0.000001
        }
        let status: Status = !fitsWindows ? .windowsTooFew : needed > left ? .paceTooSlow : .feasible
        var modelTotals: [String: Int] = [:]
        for row in rows {
            for model in WindowModelActivity.summaries(modelEvents, window: row) {
                if let name = model.model { modelTotals[name, default: 0] += model.tokens }
            }
        }
        let models = Array(modelTotals.keys.sorted {
            modelTotals[$0] == modelTotals[$1] ? $0 < $1 : modelTotals[$0]! > modelTotals[$1]!
        }.prefix(2))
        return Self(status: status, reason: nil, remaining: remaining, hoursLeft: left, hoursNeeded: needed,
                    hoursPerDay: needed / days, fullQuotasPerDay: fullQuotas / days,
                    availableFullQuotas: available, intervals: rows.count, models: models)
    }
}
