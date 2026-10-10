import Foundation

public struct UsageRoast {
    public let service: String
    public let headline: String
    public let punchline: String
    public let status: String
    public let activeDays: Int
    public let tokens: Int
    public let records: Int
    public let files: Int
    public let lastUsed: String?
    public let uncertain: Bool
    public let scenario: RoastScenario
    public let evidence: String

    public static func make(provider: Provider, snapshot: CollectorSnapshot?,
                            fresh: Bool = true, context requestedContext: PlanContext = .unknown, variant: Int = 0,
                            now: Date = Date(), calendar: Calendar = .current) -> UsageRoast {
        let service = provider == .openai ? "ChatGPT" : provider.serviceName
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -29, to: today)!
        func date(_ value: String) -> Date? {
            let parts = value.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
            guard let date = calendar.date(from: components),
                  calendar.component(.year, from: date) == parts[0],
                  calendar.component(.month, from: date) == parts[1],
                  calendar.component(.day, from: date) == parts[2] else { return nil }
            return date
        }
        let all = (snapshot?.days ?? []).filter { $0.provider == provider && date($0.day).map { $0 <= today } == true }
        let recent = all.filter { date($0.day).map { $0 >= first } == true }
        let activeDays = Set(recent.filter { $0.requests > 0 }.map(\.day)).count
        let source = snapshot?.sources.first { $0.provider == provider }
        let localUncertain = source?.status != "ok"
        let connection = snapshot?.connections?.first { $0.provider == provider }
        let context = requestedContext == .unknown && fresh && connection?.status == "connected"
            ? connection?.planContext ?? .unknown : requestedContext
        let accountWindows = (snapshot?.quotaWindows ?? []).filter {
            connection?.accountKey == nil || $0.accountKey == connection?.accountKey
        }
        let quotas = fresh ? QuotaUsage.summaries(provider: provider, windows: accountWindows, now: now) : []
        // Judge the widest reported budget, consistently with the persona.
        // A quiet 5-hour window must not accuse a well-used weekly plan of waste.
        let representative = QuotaUsage.representative(quotas)
        let current = representative?.current
        let wasted = representative.flatMap { quota in
            quota.eligibleExpired.count >= 2 && (quota.averageUnused ?? 0) >= 70 ? quota : nil
        }
        let expiring = current.map { $0.remainingPercent >= 80 && $0.resetsAt - now.timeIntervalSince1970 <= Double($0.windowMinutes) * 60 * 0.25 } ?? false
        let busy = current.map { $0.usedPercent >= 50 } ?? false
        let uncertain = !fresh || (current == nil && wasted == nil && localUncertain)
        var premiumPlan = provider == .claude ? "Claude Max" : provider == .openai ? "ChatGPT Pro" :
            provider == .antigravity ? "a paid Antigravity plan" : "\(service) Pro"
        if fresh, connection?.status == "connected", connection?.planContext == .personal,
           let label = connection?.planLabel {
            let words = label.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            if let tier = ["max", "ultra", "pro", "plus"].first(where: { words.contains($0) }) {
                premiumPlan = "\(service) \(tier.capitalized)"
            }
        }
        let earliest = all.compactMap { date($0.day) }.min()
        let span = earliest.map { calendar.dateComponents([.day], from: max(first, $0), to: today).day ?? 0 } ?? 0
        let scene: RoastScenario
        let status: String
        if context == .organization {
            if fresh && (busy || (!localUncertain && span >= 14 && activeDays >= 10)) {
                scene = .workActive; status = "USAGE CONFIRMED"
            } else if fresh && (wasted != nil || (current == nil && !localUncertain && span >= 14 && activeDays <= 4)) {
                scene = .workWaste; status = "REVIEW YOUR SEAT"
            } else { scene = .workUnknown; status = "WORK PLAN" }
        } else if context == .free {
            scene = .free; status = "FREE PLAN"
        } else if !fresh {
            scene = .stale; status = "RECEIPTS MISSING"
        } else if busy {
            scene = .active; status = "USAGE CONFIRMED"
        } else if wasted != nil {
            // An unidentified plan gets a question, not a claim of paid waste.
            scene = context == .personal ? .wasted : .unverified
            status = context == .personal ? "ON THIN ICE" : "PLAN UNVERIFIED"
        } else if expiring {
            scene = context == .personal ? .expiring : .remaining
            status = "RESET APPROACHING"
        } else if current != nil {
            scene = .remaining; status = "QUOTA STILL LEFT"
        } else if localUncertain {
            scene = .missing; status = "RECEIPTS MISSING"
        } else if span < 14 {
            scene = .warming; status = "WARMING UP"
        } else if activeDays <= 4 {
            scene = .localWaste; status = "ON THIN ICE"
        } else if activeDays >= 10 {
            scene = .active; status = "USAGE CONFIRMED"
        } else {
            scene = .localMixed; status = "SIDE-EYE"
        }
        func percentage(_ value: Double) -> String { "\(Int(value.rounded()))%" }
        let evidence: String
        if let wasted, [.wasted, .unverified, .workWaste].contains(scene) {
            evidence = "\(wasted.title): ~\(percentage(wasted.averageUnused!)) left near reset across \(wasted.eligibleExpired.count) windows."
        } else if let current {
            evidence = "\(percentage(current.remainingPercent)) left in the \(current.windowMinutes == 300 ? "5-hour" : current.windowMinutes == 10080 ? "weekly" : "current") window."
        } else if !fresh {
            evidence = "Usage needs a refresh."
        } else if !localUncertain {
            evidence = "Local logs: \(activeDays) active days / 30. Other usage may be missing."
        } else { evidence = "No reliable quota or complete local records." }
        let options = RoastCopy.lines(scene)
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let providerSeed = provider.rawValue.utf8.reduce(0) { $0 + Int($1) }
        let index = ((day + providerSeed) % options.count + variant % options.count + options.count) % options.count
        func render(_ text: String) -> String {
            text.replacingOccurrences(of: "{service}", with: service)
                .replacingOccurrences(of: "{plan}", with: premiumPlan)
                .replacingOccurrences(of: "{workplan}", with: connection?.planLabel?.lowercased().contains("enterprise") == true || connection?.planLabel?.lowercased() == "ent26" ? "Enterprise" : "Work")
                .replacingOccurrences(of: "{left}", with: current.map { percentage($0.remainingPercent) } ?? "Unverified quota")
                .replacingOccurrences(of: "{unused}", with: wasted.map { percentage($0.averageUnused!) } ?? "Unknown")
        }
        let (headline, punchline) = options[index]
        return UsageRoast(service: service, headline: render(headline), punchline: render(punchline), status: status,
                          activeDays: activeDays, tokens: recent.reduce(0) { $0 + $1.tokens },
                          records: recent.reduce(0) { $0 + $1.requests }, files: source?.files ?? 0,
                          lastUsed: all.map(\.day).max(), uncertain: uncertain, scenario: scene, evidence: evidence)
    }
}
