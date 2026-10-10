import Foundation

public enum SubscriptionChangeKind: String, Codable, CaseIterable {
    case cancelled, downgraded, releasedSeat
    public var title: String {
        switch self {
        case .cancelled: return "Cancelled"
        case .downgraded: return "Downgraded"
        case .releasedSeat: return "Seat released"
        }
    }
}

/// A user-reported completed action, never an API-confirmed billing event.
public struct SubscriptionChange: Codable, Identifiable, Equatable {
    public var id: UUID
    public var provider: Provider
    public var accountKey: String?
    public var kind: SubscriptionChangeKind
    public var fromPlan: String
    public var toPlan: String
    public var completedAt: Date
    public var baselineMonthlyUSD: Double?
    public var beforeMonthlyUSD: Double?
    public var afterMonthlyUSD: Double?
    public var priceCheckedOn: String

    public var monthlyReduction: Double? {
        guard kind != .releasedSeat, let baseline = baselineMonthlyUSD, let after = afterMonthlyUSD,
              baseline.isFinite, after.isFinite, baseline >= 0, after >= 0, after <= baseline else { return nil }
        return baseline - after
    }

    public static func make(connection: ProviderConnection, kind: SubscriptionChangeKind,
                            targetPlan: String? = nil, previous: SubscriptionChange? = nil,
                            now: Date = Date()) -> SubscriptionChange? {
        guard Provider.supported.contains(connection.provider), connection.status == "connected" else { return nil }
        let context = connection.planContext
        guard context != .free else { return nil }
        if context == .organization && kind != .releasedSeat { return nil }
        if context != .organization && kind == .releasedSeat { return nil }
        let prior = previous.flatMap {
            $0.provider == connection.provider && $0.accountKey == connection.accountKey && $0.completedAt <= now ? $0 : nil
        }
        // A second cancellation must not add another copy of the same saving.
        guard prior?.kind != .cancelled && prior?.kind != .releasedSeat && prior?.afterMonthlyUSD != 0 else { return nil }
        let before = prior != nil ? prior?.afterMonthlyUSD : PlanPricing.lookup(provider: connection.provider, label: connection.planLabel)?.exact
        let after: Double?
        let target: String
        switch kind {
        case .cancelled: after = 0; target = "No paid plan"
        case .releasedSeat: after = nil; target = "Seat released"
        case .downgraded:
            guard let targetPlan, PlanPricing.recordingOptions(provider: connection.provider).contains(targetPlan) else { return nil }
            target = targetPlan
            after = targetPlan == "Free" ? 0 : PlanPricing.lookup(provider: connection.provider, label: targetPlan)?.exact
            guard let after, before.map({ after < $0 }) ?? true, target != (prior?.toPlan ?? connection.planLabel) else { return nil }
        }
        return SubscriptionChange(id: UUID(), provider: connection.provider, accountKey: connection.accountKey,
            kind: kind, fromPlan: prior?.toPlan ?? connection.planLabel ?? "Plan not reported", toPlan: target,
            completedAt: now, baselineMonthlyUSD: kind == .releasedSeat ? nil : prior != nil ? prior?.baselineMonthlyUSD : before,
            beforeMonthlyUSD: before, afterMonthlyUSD: after, priceCheckedOn: PlanPricing.checkedOn)
    }
}

public enum SavingsLedger {
    public static func rememberPlans(_ existing: [ProviderConnection], connections: [ProviderConnection]) -> [ProviderConnection] {
        var plans = existing
        for connection in connections where connection.status == "connected" && connection.accountKey != nil &&
            (connection.planContext == .personal || connection.planContext == .organization) {
            plans.removeAll { $0.provider == connection.provider && $0.accountKey == connection.accountKey && $0.planLabel == connection.planLabel }
            plans.append(connection)
        }
        return plans
    }
    public static func recordingConnection(_ current: ProviderConnection?, remembered: [ProviderConnection],
                                           records: [SubscriptionChange], kind: SubscriptionChangeKind = .cancelled) -> ProviderConnection? {
        guard let current else { return nil }
        let history = current.accountKey == nil ? [] : remembered.filter {
            $0.provider == current.provider && $0.accountKey == current.accountKey
        }
        if current.planContext == .free { return history.last }
        // The new/free tier can be reported before the user records the action.
        if kind == .downgraded, latest(records, provider: current.provider, accountKey: current.accountKey) == nil,
           let currentPrice = PlanPricing.lookup(provider: current.provider, label: current.planLabel)?.exact,
           let prior = history.last(where: { $0.planLabel != current.planLabel }),
           let previousPrice = PlanPricing.lookup(provider: current.provider, label: prior.planLabel)?.exact,
           previousPrice > currentPrice { return prior }
        return current
    }

    public static func latest(_ records: [SubscriptionChange], provider: Provider, accountKey: String?) -> SubscriptionChange? {
        records.filter { $0.provider == provider && $0.accountKey == accountKey }
            .max { $0.completedAt < $1.completedAt }
    }
    /// Current monthly run-rate reduction, not accumulated cash saved.
    /// Keep only the latest action in each account's chain to avoid double counting.
    public static func latestRecords(_ records: [SubscriptionChange]) -> [SubscriptionChange] {
        let groups = Dictionary(grouping: records, by: { "\($0.provider.rawValue):\($0.accountKey ?? "unidentified")" })
        return groups.values.compactMap { $0.max { $0.completedAt < $1.completedAt } }
    }
    public static func monthlyReduction(_ records: [SubscriptionChange]) -> Double {
        latestRecords(records).compactMap(\.monthlyReduction).reduce(0, +)
    }
}

public enum ReviewPriority {
    public static func isCandidate(_ roast: UsageRoast) -> Bool {
        roast.scenario == .wasted || roast.scenario == .workWaste
    }
    public static func ordered(_ providers: [Provider], snapshot: CollectorSnapshot?, fresh: Bool,
                               changes: [SubscriptionChange], now: Date = Date()) -> [Provider] {
        // Preserve the original service order within groups. No invented risk score.
        let candidates = Set(providers.filter { provider in
            let connection = snapshot?.connections?.first { $0.provider == provider }
            let recorded = SavingsLedger.latest(changes, provider: provider, accountKey: connection?.accountKey)
            guard recorded == nil else { return false }
            return isCandidate(UsageRoast.make(provider: provider, snapshot: snapshot, fresh: fresh, now: now))
        })
        return providers.filter { candidates.contains($0) } + providers.filter { !candidates.contains($0) }
    }
}
