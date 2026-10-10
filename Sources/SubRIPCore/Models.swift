import Foundation

public enum Provider: String, Codable, CaseIterable, Identifiable {
    case openai, claude, gemini, cursor, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .openai: return "ChatGPT / Codex"
        case .claude: return "Claude / Claude Code"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor"
        case .other: return "기타 AI"
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
}

public struct AppData: Codable {
    public var version: Int = 1
    public var subscriptions: [Subscription] = []
    public var claudeFolder: String?
    public var codexFolder: String?
    public var snapshot: CollectorSnapshot?
    public var scannedAt: Date?
    public init() {}
}

public enum Verdict: String {
    case observing = "관찰 중"
    case incomplete = "기록 확인 필요"
    case keep = "생존 신고"
    case review = "장례 후보"
    case buried = "안치 완료"
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
