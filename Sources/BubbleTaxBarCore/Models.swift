import Foundation

public enum Provider: String, Codable, CaseIterable, Identifiable {
    case openai, claude, gemini, cursor, copilot, windsurf, antigravity, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .openai: return "ChatGPT / Codex"
        case .claude: return "Claude / Claude Code"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor"
        case .copilot: return "GitHub Copilot"
        case .windsurf: return "Windsurf"
        case .antigravity: return "Antigravity"
        case .other: return "Other AI"
        }
    }
    // Keep legacy gemini/windsurf values only to decode previously saved data.
    public static let supported: [Provider] = [.openai, .claude, .cursor, .copilot, .antigravity]
    public var serviceName: String {
        switch self {
        case .openai: return "ChatGPT / Codex"
        case .claude: return "Claude"
        default: return title
        }
    }
    public var supportsCLI: Bool { self == .openai || self == .claude }
}

public struct Subscription: Codable, Identifiable, Equatable {
    public var id: UUID
    public var provider: Provider
    public var name: String
    public var monthlyPrice: Double
    public var currency: String
    public var billingAnchor: Date
    public var observedSince: Date
    public var includesCLI: Bool
    public var coverageConfirmed: Bool
    public var coverageConfirmedAt: Date?
    public var valuableThisCycle: Bool
    public var valueMarkedAt: Date?
    public var manualDays: [Date]
    public var cancelledAt: Date?

    public init(id: UUID = UUID(), provider: Provider = .openai, name: String = "", monthlyPrice: Double = 0,
                currency: String = "USD", billingAnchor: Date = Date(), observedSince: Date = Date(),
                includesCLI: Bool = false, coverageConfirmed: Bool = false, coverageConfirmedAt: Date? = nil, valuableThisCycle: Bool = false,
                valueMarkedAt: Date? = nil, manualDays: [Date] = [], cancelledAt: Date? = nil) {
        self.id = id; self.provider = provider; self.name = name; self.monthlyPrice = monthlyPrice
        self.currency = currency; self.billingAnchor = billingAnchor; self.observedSince = observedSince
        self.includesCLI = includesCLI; self.coverageConfirmed = coverageConfirmed
        self.coverageConfirmedAt = coverageConfirmedAt
        self.valuableThisCycle = valuableThisCycle; self.valueMarkedAt = valueMarkedAt
        self.manualDays = manualDays; self.cancelledAt = cancelledAt
    }
}

public struct UsageDay: Codable, Equatable {
    public var provider: Provider
    public var day: String
    public var tokens: Int
    public var requests: Int
}

public struct SourceStatus: Codable {
    public var provider: Provider
    public var status: String
    public var files: Int
    public var malformed: Int
    public var unreadable: Int
    public var unsupported: Int
}

public struct CollectorSnapshot: Codable {
    public var days: [UsageDay]
    public var sources: [SourceStatus]
    public var quotaWindows: [QuotaWindow]?
    public var connections: [ProviderConnection]?
    public var piUsage: PiUsageSnapshot?
    public var modelUsage: [ModelUsageEvent]?
    public var modelUsageTruncated: [Provider]?
}

public struct PiUsageDay: Codable {
    public var providerID: String
    public var day: String
    public var tokens: Int
    public var requests: Int
}

public struct PiUsageSnapshot: Codable {
    public var days: [PiUsageDay]
    public var status: String
    public var files: Int
    public var malformed: Int
    public var unreadable: Int
    public var unsupported: Int
}

public struct AppData: Codable {
    public var version: Int = 1
    public var subscriptions: [Subscription] = []
    public var claudeFolder: String?
    public var codexFolder: String?
    public var piFolder: String?
    public var snapshot: CollectorSnapshot?
    public var scannedAt: Date?
    public var enabledProviders: [Provider]?
    public var subscriptionChanges: [SubscriptionChange]?
    public var reviewFirst: Bool?
    public var recordingPlans: [ProviderConnection]?
    public var billingSchedules: [BillingSchedule]?
    public var unusedQuotaArchive: [QuotaWindow]?
    public var claudeQuotaSamples: [ClaudeQuotaSample]?
    public var codexQuotaSamples: [WindowQuotaSample]?
    public var modelUsageArchive: [ModelUsageEvent]?
    public var allocationPreferences: AllocationPreferences?
    public var quotaReservations: [QuotaReservation]?
    public init() {}
}

public enum Verdict: String {
    case observing = "Observing"
    case incomplete = "Missing receipts"
    case keep = "Still alive"
    case review = "On thin ice"
    case buried = "Rest in peace"
}

public struct Assessment {
    public var verdict: Verdict
    public var activeDays: Int
    public var observationDays: Int
    public var tokens: Int
    public var riskScore: Int?
    public var nextBilling: Date
    public var explanation: String
}
