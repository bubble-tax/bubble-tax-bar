import Foundation

/// Bundled public US monthly list prices, not a user's invoice or API credits.
/// Refresh this catalog in source when pricing changes; no runtime billing scraping.
public struct PublicPlanPrice {
    public let minimum: Double
    public let maximum: Double
    public let sourceURL: String
    public var exact: Double? { minimum == maximum ? minimum : nil }
    public var display: String {
        func dollars(_ value: Double) -> String {
            value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
        }
        return minimum == maximum ? dollars(minimum) : "\(dollars(minimum))–\(dollars(maximum))"
    }
}

public enum PlanPricing {
    public static let checkedOn = "2026-10-08"
    public static let caveat = "US monthly list prices. Taxes, annual discounts, promotions, regional prices and extra usage are excluded. Google plans bundle other benefits."

    /// Choices describe a change already made by the user, not recommended tiers.
    public static func recordingOptions(provider: Provider) -> [String] {
        switch provider {
        case .openai: return ["Free", "Go", "Plus", "Pro 100", "Pro 200", "Pro 500"]
        case .claude: return ["Free", "Pro", "Max 5x", "Max 20x"]
        case .cursor: return ["Free", "Pro", "Pro+", "Ultra"]
        case .copilot: return ["Free", "Pro", "Pro+", "Max"]
        case .antigravity: return ["Free", "Google AI Pro", "Google AI Ultra 5x", "Google AI Ultra 20x"]
        default: return []
        }
    }

    public static func lookup(provider: Provider, label: String?) -> PublicPlanPrice? {
        guard let label, PlanContext.classify(label) == .personal else { return nil }
        let words = Set(label.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let compact = label.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "+" }
        func price(_ low: Double, _ high: Double? = nil, _ url: String) -> PublicPlanPrice {
            PublicPlanPrice(minimum: low, maximum: high ?? low, sourceURL: url)
        }
        switch provider {
        case .openai:
            if words.contains("pro") || words.contains(where: { ["pro100", "pro200", "pro500"].contains($0) }) {
                let url = "https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers"
                for tier in [100, 200, 500] where words.contains(String(tier)) || compact.contains("pro\(tier)") {
                    return price(Double(tier), nil, url)
                }
                return price(100, 500, url)
            }
            let url = "https://openai.com/index/introducing-chatgpt-go/"
            if words.contains("plus") { return price(20, nil, url) }
            if words.contains("go") { return price(8, nil, url) }
        case .claude:
            let url = "https://support.claude.com/en/articles/11049762-choose-a-claude-plan"
            if words.contains("max") || words.contains(where: { ["max5", "max20", "max5x", "max20x"].contains($0) }) {
                if compact.contains("20x") || compact.contains("max20") { return price(200, nil, url) }
                if compact.contains("5x") || compact.contains("max5") { return price(100, nil, url) }
                return price(100, 200, url)
            }
            if words.contains("pro") { return price(20, nil, url) }
        case .cursor:
            let url = "https://cursor.com/help/account-and-billing/pricing"
            if words.contains("ultra") { return price(200, nil, url) }
            if compact.contains("pro+") || compact.contains("proplus") { return price(60, nil, url) }
            if words.contains("pro") { return price(20, nil, url) }
        case .copilot:
            let url = "https://github.com/features/copilot/plans"
            if words.contains("max") { return price(100, nil, url) }
            if compact.contains("pro+") || compact.contains("proplus") { return price(39, nil, url) }
            if words.contains("pro") { return price(10, nil, url) }
        case .antigravity:
            if words.contains("ultra") {
                let url = "https://blog.google/products-and-platforms/products/google-one/google-ai-subscriptions/"
                if words.contains("200") || compact.contains("20x") { return price(200, nil, url) }
                if words.contains("100") || compact.contains("5x") { return price(100, nil, url) }
                return price(100, 200, url)
            }
            if words.contains("pro") {
                return price(19.99, nil, "https://one.google.com/about/google-ai-plans/?gl=US&hl=en")
            }
        default: break
        }
        return nil
    }
}
