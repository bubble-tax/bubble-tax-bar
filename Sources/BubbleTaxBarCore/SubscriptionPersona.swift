import Foundation

/// Only a provider billing response may populate this value. Legacy/manual
/// Subscription prices are deliberately not used for the overall assessment.
public struct VerifiedMonthlyCost: Codable {
    public var amount: Double
    public var currency: String
    public var accountKey: String
    public var observedAt: Double
}

public enum SubscriptionPersona: String, CaseIterable {
    case environmentalist, donationAngel, bubbleSponsor, collector, tokenMaxxer, corporateSponsor, corporateMaxxer, freeLegend, pending, cloudPreserver, ghostSubscriber, premiumPhilanthropist, tokenTrasher, ventureCapitalist, benchwarmer, fomoCollector, backupHoarder, rateLimitRegular, quotaMenace, emptySeat, procurementPrank, budgetBurner, officePowerUser, couponLegend

    public var title: String {
        switch self {
        case .environmentalist: return "The Environmentalist"
        case .donationAngel: return "The Donation Angel"
        case .bubbleSponsor: return "The AI Bubble Sponsor"
        case .collector: return "The Subscription Collector"
        case .tokenMaxxer: return "The Token Maxxer"
        case .corporateSponsor: return "The Corporate Philanthropist"
        case .corporateMaxxer: return "The Procurement Favorite"
        case .freeLegend: return "The Free-Tier Legend"
        case .pending: return "Persona Pending"
        case .cloudPreserver: return "The Cloud Conservationist"
        case .ghostSubscriber: return "The Ghost Subscriber"
        case .premiumPhilanthropist: return "The Premium Philanthropist"
        case .tokenTrasher: return "The Token Trasher"
        case .ventureCapitalist: return "The Accidental VC"
        case .benchwarmer: return "The Benchwarmer"
        case .fomoCollector: return "The FOMO Collector"
        case .backupHoarder: return "The Backup Plan Hoarder"
        case .rateLimitRegular: return "The Rate-Limit Regular"
        case .quotaMenace: return "The Quota Menace"
        case .emptySeat: return "The Empty Seat"
        case .procurementPrank: return "The Procurement Prank"
        case .budgetBurner: return "The Budget Bonfire"
        case .officePowerUser: return "The Office Power User"
        case .couponLegend: return "The Free-Plan Collector"
        }
    }
    public var message: String {
        switch self {
        case .environmentalist: return "Saving compute. Saving the planet. Still paying for the privilege."
        case .donationAngel: return "You save tokens. You don't save subscription money."
        case .bubbleSponsor: return "Big subscription energy. Small compute energy. The AI bubble thanks you."
        case .collector: return "Collecting subscriptions like trading cards. Some of them even get used."
        case .tokenMaxxer: return "Your subscriptions get used. Keep the ones whose value earns the bill."
        case .corporateSponsor: return "Your boss sponsors the AI bubble. You help by leaving the quota alone."
        case .corporateMaxxer: return "A work seat with receipts. Procurement can finally unclench."
        case .freeLegend: return "Saving tokens and money. The billing allegations have been dropped."
        case .pending: return "Waiting for reset receipts before diagnosing your wallet."
        case .cloudPreserver: return "Your quota is practically untouched. Put it in a museum."
        case .ghostSubscriber: return "Haunting the billing cycle. Barely appearing in the usage history."
        case .premiumPhilanthropist: return "Premium-plan money. Background-character usage. The shareholders send their love."
        case .tokenTrasher: return "Token maxxing? More like token trashing. Those resets are taking out the bins."
        case .ventureCapitalist: return "A portfolio of AI subscriptions. Most of the investment is still sitting in the quota."
        case .benchwarmer: return "A decent chunk of your quota watches from the bench. Still getting paid, though."
        case .fomoCollector: return "Several plans on the roster. Plenty of quota waiting for its big moment."
        case .backupHoarder: return "Keeping spare quota like emergency snacks. The snacks expire."
        case .rateLimitRegular: return "Most of your quota gets used. A smaller tier might be a tight fit; keep checking the value."
        case .quotaMenace: return "Very little quota goes unused. This plan has usage receipts; the price still needs to make sense."
        case .emptySeat: return "A work license with almost no quota touched. The seat has better attendance than the usage."
        case .procurementPrank: return "Procurement bought the seat. Most of the quota bought itself a vacation."
        case .budgetBurner: return "At least half the work quota went unused. Finance would love this little fun fact."
        case .officePowerUser: return "You actually use the work quota. Your boss finally has a flex that survives a spreadsheet."
        case .couponLegend: return "Several free plans. Zero subscription charges reported. A collection Finance can get behind."
        }
    }
    public var weeklyMessage: String {
        switch self {
        case .environmentalist: return "Saving compute this week. Still paying for the privilege."
        case .donationAngel: return "Most of this week's quota is still chilling. The subscription money isn't."
        case .bubbleSponsor: return "Big subscription energy. Plenty of weekly quota still on the sidelines."
        case .collector: return "Collecting subscriptions like trading cards. This week's quota collection is looking healthy."
        case .tokenMaxxer: return "You're using this week's quota. Keep the plans whose value earns the bill."
        case .corporateSponsor: return "Your boss paid for the seat. Most of this week's quota is taking a vacation."
        case .corporateMaxxer: return "A work seat getting used this week. Procurement can breathe."
        case .freeLegend, .couponLegend: return message
        case .pending: return "Waiting for a fresh weekly quota reading."
        case .cloudPreserver: return "This week's quota is practically untouched. Museum-quality preservation."
        case .ghostSubscriber: return "The weekly quota hasn't seen much of you yet. The bill knows where you live."
        case .premiumPhilanthropist: return "Premium-plan money. Most of this week's quota still waiting for its cameo."
        case .tokenTrasher: return "Token maxxing? Not this week so far. Plenty of quota still waiting."
        case .ventureCapitalist: return "A portfolio of AI plans. Plenty of weekly quota still waiting for a return."
        case .benchwarmer: return "A chunk of this week's quota is warming the bench. Check if a smaller plan fits."
        case .fomoCollector: return "Several plans on the roster. This week's quota still has room to spare."
        case .backupHoarder: return "Keeping spare weekly quota like emergency snacks. Check the expiry date."
        case .rateLimitRegular: return "Most of this week's quota is already used. A smaller tier could be a tight fit."
        case .quotaMenace: return "Weekly quota nearly tapped. Usage receipts acquired; value still matters."
        case .emptySeat: return "A work seat with this week's quota almost untouched. Your boss bought a spectator."
        case .procurementPrank: return "Procurement bought the seat. Most of this week's quota is still on holiday."
        case .budgetBurner: return "At least half the weekly work quota is still available. Finance might have questions."
        case .officePowerUser: return "You're putting the work quota to use this week. Your boss finally has a flex."
        }
    }

    public var symbol: String {
        switch self {
        case .environmentalist: return "leaf"
        case .donationAngel: return "gift"
        case .bubbleSponsor: return "bubble.left.and.bubble.right"
        case .collector: return "rectangle.stack"
        case .tokenMaxxer: return "bolt"
        case .corporateSponsor: return "gift"
        case .corporateMaxxer: return "bolt"
        case .freeLegend: return "checkmark.seal"
        case .pending: return "hourglass"
        case .cloudPreserver: return "cloud"
        case .ghostSubscriber: return "moon"
        case .premiumPhilanthropist: return "gift.fill"
        case .tokenTrasher: return "trash"
        case .ventureCapitalist: return "chart.pie"
        case .benchwarmer: return "pause.circle"
        case .fomoCollector: return "square.stack"
        case .backupHoarder: return "archivebox"
        case .rateLimitRegular: return "speedometer"
        case .quotaMenace: return "flame"
        case .emptySeat: return "chair"
        case .procurementPrank: return "theatermasks"
        case .budgetBurner: return "banknote"
        case .officePowerUser: return "briefcase"
        case .couponLegend: return "ticket"
        }
    }

    // Refine the same unused-quota bands with plan count and known USD prices.
    // No random rotation: a refresh with unchanged evidence keeps its persona.
    static func classify(unused: Double, personalPlans: Int, usdMonthlyTotal: Double?) -> SubscriptionPersona {
        if personalPlans == 0 {
            if unused >= 98 { return .emptySeat }
            if unused >= 80 { return .corporateSponsor }
            if unused >= 65 { return .procurementPrank }
            if unused >= 50 { return .budgetBurner }
            if unused >= 20 { return .corporateMaxxer }
            return .officePowerUser
        }
        if unused >= 98 { return .cloudPreserver }
        if unused >= 90 { return .environmentalist }
        if unused >= 85 { return .ghostSubscriber }
        if unused >= 75 {
            return (usdMonthlyTotal ?? 0) >= 100 ? .premiumPhilanthropist : .donationAngel
        }
        if unused >= 70 { return .tokenTrasher }
        if unused >= 60 { return personalPlans >= 3 ? .ventureCapitalist : .bubbleSponsor }
        if unused >= 50 { return personalPlans >= 2 ? .collector : .benchwarmer }
        if unused >= 35 { return personalPlans >= 3 ? .fomoCollector : .backupHoarder }
        if unused >= 15 { return .tokenMaxxer }
        if unused >= 5 { return .rateLimitRegular }
        return .quotaMenace
    }
}

public struct PersonaAssessment {
    public let persona: SubscriptionPersona
    public let pendingReason: String?
    public let remainingPercent: Double?
    public let personalPlans: Int
    public let workPlans: Int
    public let coveredPlans: Int
    public let monthlyTotal: Double?
    public let currency: String?
    public let monthlyRange: ClosedRange<Double>?
    public let usesListPrices: Bool
    public let priceWeighted: Bool
    public let scope: String

    public static func make(snapshot: CollectorSnapshot?, providers: [Provider] = Provider.supported,
                            fresh: Bool = true, now: Date = Date()) -> PersonaAssessment {
        let time = now.timeIntervalSince1970
        let connections = (snapshot?.connections ?? []).filter { providers.contains($0.provider) && $0.status == "connected" }
        let personal = connections.filter { $0.planContext == .personal }
        let work = connections.filter { $0.planContext == .organization }
        // Work seats never increase the user's personal subscription total.
        let selected = personal.isEmpty ? work : personal
        var receipts: [(connection: ProviderConnection, quota: QuotaUsage, remaining: Double)] = []
        if fresh {
            for connection in selected {
                guard let account = connection.accountKey else { continue }
                let windows = (snapshot?.quotaWindows ?? []).filter { $0.accountKey == account }
                // The persona is a live weekly snapshot, not expired waste.
                // Don't substitute short/monthly budgets or previous weeks.
                let quotas = QuotaUsage.summaries(provider: connection.provider, windows: windows, now: now)
                    .filter { $0.windowMinutes == 10080 }
                if let quota = QuotaUsage.representative(quotas), let current = quota.current {
                    receipts.append((connection, quota, current.remainingPercent))
                }
            }
        }
        func cost(_ connection: ProviderConnection) -> VerifiedMonthlyCost? {
            guard fresh, let value = connection.verifiedMonthlyCost,
                  connection.accountKey == value.accountKey, value.amount.isFinite, value.amount > 0,
                  value.currency.count == 3, value.currency.allSatisfy({ $0.isASCII && $0.isUppercase }),
                  value.observedAt.isFinite, (0...86400).contains(time - value.observedAt) else { return nil }
            return value
        }
        // Static list prices are a reference estimate, never verified account billing.
        let prices = personal.compactMap { connection -> (low: Double, high: Double, currency: String, list: Bool)? in
            if let verified = cost(connection) {
                return (verified.amount, verified.amount, verified.currency, false)
            }
            guard fresh, let price = PlanPricing.lookup(provider: connection.provider, label: connection.planLabel) else { return nil }
            return (price.minimum, price.maximum, "USD", true)
        }
        let currencies = Set(prices.map(\.currency))
        let low = prices.reduce(0) { $0 + $1.low }
        let high = prices.reduce(0) { $0 + $1.high }
        let completePrices = !personal.isEmpty && prices.count == personal.count && currencies.count == 1 && low.isFinite && high.isFinite && low > 0
        let range = completePrices ? low...high : nil
        let total = completePrices && low == high ? low : nil
        let weighted = total != nil && receipts.count == personal.count
        let unused: Double?
        if receipts.isEmpty { unused = nil }
        else if weighted, let total {
            unused = receipts.reduce(0) { $0 + $1.remaining * ((cost($1.connection)?.amount ?? PlanPricing.lookup(provider: $1.connection.provider, label: $1.connection.planLabel)!.exact!) / total) }
        } else { unused = receipts.reduce(0) { $0 + $1.remaining } / Double(receipts.count) }
        let persona: SubscriptionPersona
        if !fresh { persona = .pending }
        else if let unused {
            persona = SubscriptionPersona.classify(unused: unused, personalPlans: personal.count,
                usdMonthlyTotal: weighted && currencies.first == "USD" ? total : nil)
        } else if !connections.isEmpty && connections.allSatisfy({ $0.planContext == .free }) {
            persona = connections.count >= 2 ? .couponLegend : .freeLegend
        }
        else { persona = .pending }
        let pendingReason: String?
        if persona != .pending { pendingReason = nil }
        else if !fresh { pendingReason = "Refresh usage to bring your receipts up to date." }
        else if connections.isEmpty { pendingReason = "Connect an account to start collecting usage receipts." }
        else if selected.isEmpty { pendingReason = "Your provider hasn't identified a paid or work plan yet." }
        else if selected.allSatisfy({ $0.accountKey == nil }) { pendingReason = "Account identity is missing. Weekly quota can't be linked yet." }
        else { pendingReason = "No fresh weekly quota reported. Short-window limits stay separate." }
        let scope = receipts.map { "\($0.connection.provider.serviceName): \(Int($0.remaining.rounded()))% weekly quota left" }.joined(separator: "; ")
        return PersonaAssessment(persona: persona, pendingReason: pendingReason, remainingPercent: unused, personalPlans: personal.count,
            workPlans: work.count, coveredPlans: receipts.count,
            monthlyTotal: total, currency: completePrices ? currencies.first : nil,
            monthlyRange: range, usesListPrices: prices.contains { $0.list },
            priceWeighted: weighted, scope: scope)
    }
}
