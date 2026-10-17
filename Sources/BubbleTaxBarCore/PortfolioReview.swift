import Foundation

public struct PortfolioReview: Identifiable {
    public enum Action: Equatable { case protect, keep, compare, observe, seat, free }
    public var id: Provider { provider }
    public let provider: Provider
    public let plan: String
    public let action: Action
    public let reason: String
    public let eligibleResets: Int
    public let averageUnused: Double?
    public let monthlyListPrice: Double?

    public static func rows(data: AppData, workAccount: Bool = false, now: Date = Date()) -> [Self] {
        let fresh = data.scannedAt.map { (0..<900).contains(now.timeIntervalSince($0)) } ?? false
        return (data.enabledProviders ?? Provider.supported).filter { Provider.supported.contains($0) }.compactMap { provider -> Self? in
            guard let connection = data.snapshot?.connections?.first(where: { $0.provider == provider }),
                  connection.status == "connected", let account = connection.accountKey, !account.isEmpty,
                  workAccount ? connection.planContext == .organization : [.personal, .free].contains(connection.planContext) else { return nil }
            if let change = SavingsLedger.latest(data.subscriptionChanges ?? [], provider: provider, accountKey: account),
               connection.planContext != .free, change.kind == .cancelled || change.kind == .releasedSeat || change.afterMonthlyUSD == 0 { return nil }
            var quotas = QuotaUsage.summaries(provider: provider, windows: data.snapshot?.quotaWindows ?? [], now: now).filter { $0.accountKey == account }
            if provider == .claude || provider == .openai {
                let prefix = provider == .claude ? "claude" : "codex"
                quotas = quotas.filter { $0.limitID == prefix + ":secondary" && $0.windowMinutes == 10080 }
            }
            let quota = QuotaUsage.representative(quotas)
            let resets = quota?.eligibleExpired ?? []
            let average = resets.isEmpty ? nil : resets.reduce(0) { $0 + $1.remainingPercent } / Double(resets.count)
            let enoughHistory = resets.count >= 3 && (resets.last!.resetsAt - resets.first!.resetsAt) >= Double((quota?.windowMinutes ?? 10080) * 60) * 1.9
            let reserved = quota?.current.map { current in
                (data.quotaReservations ?? []).contains { $0.matches(current, plan: connection.planLabel, now: now) }
            } ?? false
            let samples = provider == .claude ? data.claudeQuotaSamples ?? [] : provider == .openai ? data.codexQuotaSamples ?? [] : []
            let recentBurst = samples.contains {
                $0.accountKey == account && $0.planLabel == connection.planLabel &&
                $0.observedAt >= now.timeIntervalSince1970 - 7 * 86400 && $0.observedAt <= now.timeIntervalSince1970 && $0.session.usedPercent >= 95
            } || (data.snapshot?.quotaWindows ?? []).contains {
                $0.provider == provider && $0.accountKey == account && $0.windowMinutes == 300 &&
                $0.resetsAt > now.timeIntervalSince1970 && $0.observedAt <= now.timeIntervalSince1970 &&
                now.timeIntervalSince1970 - $0.observedAt < 900 && $0.usedPercent >= 95 && $0.interrupted != true
            }
            let action: Action, reason: String
            if !fresh {
                action = .observe; reason = "Refresh current overall quota before reviewing capacity."
            } else if connection.planContext == .free {
                action = .free; reason = "No paid subscription to reduce."
            } else if quota?.current == nil || quota?.current?.interrupted == true {
                action = .observe; reason = "Refresh current overall quota before reviewing capacity."
            } else if reserved {
                action = .protect; reason = "Pending work has a protected quota target. Keep its needs in the plan."
            } else if recentBurst {
                action = .keep; reason = "A recent short window reached 95% used. Weekly headroom may hide burst needs."
            } else if (quota?.current?.usedPercent ?? 0) >= 50 {
                action = .keep; reason = "Current capacity is in use. Review after this work settles."
            } else if enoughHistory && (average ?? 0) >= 70 && resets.allSatisfy({ $0.usedPercent <= 40 }) {
                action = workAccount ? .seat : .compare
                reason = workAccount ? "Repeated unused capacity. Review shared seat needs with the workspace owner." : "Three or more recorded resets left substantial headroom. Compare a smaller tier for your actual tasks."
            } else {
                action = .observe; reason = "Keep observing. A quiet current week alone doesn't establish an oversized plan."
            }
            return Self(provider: provider, plan: connection.planLabel ?? "Reported plan", action: action, reason: reason,
                eligibleResets: resets.count, averageUnused: average,
                monthlyListPrice: fresh ? PlanPricing.lookup(provider: provider, label: connection.planLabel)?.exact : nil)
        }.sorted { a, b in
            func rank(_ action: Action) -> Int {
                switch action { case .compare, .seat: return 0; case .protect: return 1; case .keep: return 2; case .observe: return 3; case .free: return 4 }
            }
            return rank(a.action) == rank(b.action) ? a.provider.rawValue < b.provider.rawValue : rank(a.action) < rank(b.action)
        }
    }
}
