import Foundation

public struct MenuBarQuota {
    public let provider: Provider?
    public let title: String
    public let detail: String

    public static func make(data: AppData, now: Date = Date()) -> MenuBarQuota {
        entries(data: data, now: now).first ?? empty
    }

    public static var empty: MenuBarQuota {
        MenuBarQuota(provider: nil, title: "†", detail: "Bubble Tax — no current paid-plan quota reported. Refresh to check subscriptions.")
    }

    public static func entries(data: AppData, now: Date = Date()) -> [MenuBarQuota] {
        let fresh = data.scannedAt.map { (0..<900).contains(now.timeIntervalSince($0)) } ?? false
        let providers = (data.enabledProviders ?? Provider.supported).filter { Provider.supported.contains($0) }
        let ordered = ReviewPriority.ordered(providers, snapshot: data.snapshot, fresh: fresh,
                                             changes: data.subscriptionChanges ?? [], now: now)
        return ordered.compactMap { provider in
            guard let connection = data.snapshot?.connections?.first(where: { $0.provider == provider }),
                  connection.status == "connected", let account = connection.accountKey,
                  connection.planContext == .personal || connection.planContext == .organization else { return nil }
            if let record = SavingsLedger.latest(data.subscriptionChanges ?? [], provider: provider, accountKey: account),
               record.kind == .cancelled || record.kind == .releasedSeat || record.afterMonthlyUSD == 0 { return nil }
            let quotas = QuotaUsage.summaries(provider: provider, windows: data.snapshot?.quotaWindows ?? [], now: now)
                .filter { $0.accountKey == account }
            guard let widest = QuotaUsage.representative(quotas), let current = widest.current else { return nil }
            // Old account observations must never be attributed to the current account.
            guard current.accountKey == account else { return nil }
            let name = provider == .openai ? "Codex" : provider == .copilot ? "Copilot" : provider.serviceName
            let percent = Int(current.remainingPercent.rounded())
            let period: String
            switch widest.windowMinutes {
            case 10080: period = "Weekly"
            case 43200: period = "Monthly"
            case 1440: period = "Daily"
            case 300: period = "5h"
            default: period = "\(widest.windowMinutes)min"
            }
            return MenuBarQuota(provider: provider, title: "† \(name) · \(period) quota \(percent)% left",
                detail: "Bubble Tax · \(provider.serviceName) · \(connection.planLabel ?? "Paid plan")\n\(widest.title) (\(widest.windowMinutes) min): \(percent)% of this quota remains\nResets \(current.resetDate.formatted(date: .abbreviated, time: .shortened))\nUpdated \(current.observedDate.formatted(date: .omitted, time: .shortened))")
        }
    }
}
