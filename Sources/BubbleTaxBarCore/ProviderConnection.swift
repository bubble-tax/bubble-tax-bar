import Foundation

public enum PlanContext: String, Codable {
    case personal, organization, free, unknown
    public static func classify(_ label: String?) -> PlanContext {
        guard let label else { return .unknown }
        let words = label.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: { ["enterprise", "ent26", "business", "team", "teams", "education", "edu"].contains($0) }) {
            return .organization
        }
        if words.contains("free") || words.contains("student") || words.contains("hobby") { return .free }
        if words.contains(where: { ["go", "plus", "pro", "max", "ultra", "individual", "pro100", "pro200", "pro500", "proplus", "max5", "max20", "max5x", "max20x"].contains($0) }) { return .personal }
        return .unknown
    }
}

public struct ProviderConnection: Codable {
    public var provider: Provider
    public var status: String
    public var source: String
    public var planLabel: String?
    public var accountKey: String?
    public var observedAt: Double?
    public var verifiedMonthlyCost: VerifiedMonthlyCost?
    public var planContext: PlanContext { PlanContext.classify(planLabel) }
}
