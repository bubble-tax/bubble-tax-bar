import Foundation

public enum WorkKind: String, Codable, CaseIterable, Identifiable {
    case coding = "Coding", writing = "Writing", research = "Research"
    public var id: String { rawValue }
}

public struct AllocationPreferences: Codable {
    public var eligible: [String: [Provider]] = [:]
    public var hoursPerDay: [String: Double] = [:]
    public var recentWork: WorkKind?
    public init() {}
    public func providers(for work: WorkKind) -> [Provider] { eligible[work.rawValue] ?? [.openai, .claude] }
}

/// A local planning target, never a provider-side quota lock.
public struct QuotaReservation: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var provider: Provider
    public var accountKey: String
    public var planLabel: String?
    public var limitID: String
    public var resetsAt: Double
    public var title: String
    public var deadline: Date
    public var percent: Double
    public var completedAt: Date?
    public init(provider: Provider, accountKey: String, planLabel: String?, limitID: String, resetsAt: Double,
                title: String, deadline: Date, percent: Double) {
        self.provider = provider; self.accountKey = accountKey; self.planLabel = planLabel
        self.limitID = limitID; self.resetsAt = resetsAt; self.title = title
        self.deadline = deadline; self.percent = percent
    }
    public func matches(_ window: QuotaWindow, plan: String?, now: Date) -> Bool {
        completedAt == nil && deadline > now && percent.isFinite && percent > 0 && percent <= 100 &&
        provider == window.provider && accountKey == window.accountKey && planLabel == plan &&
        limitID == window.limitID && abs(resetsAt - window.resetsAt) <= 60 && resetsAt > now.timeIntervalSince1970
    }
}

public struct AllocationOption: Identifiable {
    public var id: Provider { provider }
    public let provider: Provider
    public let connection: ProviderConnection
    public let weekly: QuotaWindow
    public let session: QuotaWindow?
    public let protected: Double
    public var available: Double { max(0, weekly.remainingPercent - protected) }
    public var ready: Bool { available > 0 && session.map { $0.remainingPercent > 0 } == true }
    public var title: String { provider == .openai ? "Codex" : "Claude" }
}

public enum Allocation {
    public static func options(data: AppData, work: WorkKind = .coding, workAccount: Bool = false,
                               respectEligibility: Bool = true, now: Date = Date()) -> [AllocationOption] {
        guard let scan = data.scannedAt, (0..<900).contains(now.timeIntervalSince(scan)) else { return [] }
        let eligible = (data.allocationPreferences ?? AllocationPreferences()).providers(for: work)
        return [Provider.openai, .claude].compactMap { provider -> AllocationOption? in
            guard (!respectEligibility || eligible.contains(provider)), (data.enabledProviders ?? Provider.supported).contains(provider),
                  let connection = data.snapshot?.connections?.first(where: { $0.provider == provider }),
                  connection.status == "connected", let account = connection.accountKey, !account.isEmpty,
                  workAccount ? connection.planContext == .organization : [.personal, .free].contains(connection.planContext) else { return nil }
            if let change = SavingsLedger.latest(data.subscriptionChanges ?? [], provider: provider, accountKey: account),
               connection.planContext != .free, change.kind == .cancelled || change.kind == .releasedSeat || change.afterMonthlyUSD == 0 { return nil }
            let current = QuotaUsage.summaries(provider: provider, windows: data.snapshot?.quotaWindows ?? [], now: now)
                .compactMap(\.current).filter { $0.accountKey == account && $0.interrupted != true }
            let prefix = provider == .claude ? "claude" : "codex"
            guard let weekly = current.first(where: { $0.limitID == prefix + ":secondary" && $0.windowMinutes == 10080 }) else { return nil }
            let session = current.first { $0.limitID == prefix + ":primary" && $0.windowMinutes == 300 }
            let protected = (data.quotaReservations ?? []).filter { $0.matches(weekly, plan: connection.planLabel, now: now) }.reduce(0) { $0 + $1.percent }
            return AllocationOption(provider: provider, connection: connection, weekly: weekly, session: session, protected: protected)
        }.sorted { a, b in
            if a.ready != b.ready { return a.ready }
            // Headroom is a routing hint, never an assertion of equivalent work capacity.
            let scoreA = a.available / 100 + 0.15 * (1 - min(1, (a.weekly.resetsAt - now.timeIntervalSince1970) / 604800))
            let scoreB = b.available / 100 + 0.15 * (1 - min(1, (b.weekly.resetsAt - now.timeIntervalSince1970) / 604800))
            return scoreA == scoreB ? a.provider.rawValue < b.provider.rawValue : scoreA > scoreB
        }
    }
}

public enum ReservationValidation {
    public static func issue(_ reservation: QuotaReservation, current: QuotaWindow, connection: ProviderConnection,
                             existing: [QuotaReservation], now: Date = Date()) -> String? {
        guard [.claude, .openai].contains(current.provider), current.observedAt <= now.timeIntervalSince1970, now.timeIntervalSince1970 - current.observedAt < 900,
              current.interrupted != true, current.windowMinutes == 10080,
              current.limitID == (current.provider == .claude ? "claude:secondary" : "codex:secondary"),
              connection.provider == current.provider, connection.status == "connected", current.accountKey == connection.accountKey,
              reservation.matches(current, plan: connection.planLabel, now: now) else { return "Refresh this account's overall weekly quota first." }
        guard !reservation.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reservation.title.count <= 120 else { return "Name the work you're setting aside quota for." }
        guard reservation.deadline.timeIntervalSince1970 <= current.resetsAt else { return "Choose a deadline before this weekly quota resets." }
        let used = existing.filter { $0.id != reservation.id && $0.matches(current, plan: connection.planLabel, now: now) }.reduce(0) { $0 + $1.percent }
        guard reservation.percent + used <= current.remainingPercent + 0.000001 else { return "That exceeds the unallocated weekly quota." }
        return nil
    }
}
