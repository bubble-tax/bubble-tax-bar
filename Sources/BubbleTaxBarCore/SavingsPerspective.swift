import Foundation

public enum SavingsPeriod: String, CaseIterable, Identifiable {
    case week, month, year
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public func amount(monthly: Double) -> Double? {
        guard monthly.isFinite, monthly > 0 else { return nil }
        let value: Double
        switch self {
        case .week: value = monthly * 12 / 52
        case .month: value = monthly
        case .year: value = monthly * 12
        }
        return value.isFinite ? value : nil
    }
}

public struct RealWorldSavings {
    public let amount: Double
    public let symbol: String
    public let message: String
    public static let workMessage = "Don't tell your boss. Buy AI stocks instead. /s"

    public static func make(monthly: Double, period: SavingsPeriod) -> RealWorldSavings? {
        guard let amount = period.amount(monthly: monthly) else { return nil }
        let symbol: String
        let message: String
        switch amount {
        case ..<5:
            symbol = "carrot"; message = "Snack fund. Feed yourself, not the AI bubble."
        case ..<15:
            symbol = "cup.and.saucer"; message = "Coffee fund. For an actual human this time."
        case ..<40:
            symbol = "fork.knife"; message = "Lunch fund. With someone who isn't a chatbot."
        case ..<100:
            symbol = "person.2"; message = "Dinner-with-friends fund. No context-window limits."
        case ..<250:
            symbol = "music.note"; message = "Concert fund. Touch grass. Hear actual humans."
        case ..<750:
            symbol = "sun.max"; message = "Weekend-away fund. Log out somewhere nice."
        default:
            symbol = "airplane"; message = "Travel fund. Give your passport some tokens."
        }
        return RealWorldSavings(amount: amount, symbol: symbol, message: message)
    }
}

public struct DowngradeOption: Identifiable {
    public let label: String
    public let monthlyPrice: Double
    public var id: String { label }
    /// Comparisons, not a claim that a cheaper tier includes the same features.
    public static func cheaper(provider: Provider, currentPrice: Double) -> [DowngradeOption] {
        guard currentPrice.isFinite, currentPrice > 0 else { return [] }
        return PlanPricing.recordingOptions(provider: provider).compactMap { label in
            let amount = label == "Free" ? 0 : PlanPricing.lookup(provider: provider, label: label)?.exact
            guard let amount, amount < currentPrice else { return nil }
            return DowngradeOption(label: label, monthlyPrice: amount)
        }.sorted { $0.monthlyPrice > $1.monthlyPrice }
    }
}
