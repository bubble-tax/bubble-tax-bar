import Foundation

public enum Assessor {
    // Preserve the original billing day: Jan 31 -> Feb 28 -> Mar 31.
    public static func cycle(for subscription: Subscription, now: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let anchorDay = calendar.component(.day, from: subscription.billingAnchor)
        let month = calendar.dateInterval(of: .month, for: now)!.start
        func billing(in monthStart: Date) -> Date {
            let count = calendar.range(of: .day, in: .month, for: monthStart)!.count
            return calendar.date(byAdding: .day, value: min(anchorDay, count) - 1, to: monthStart)!
        }
        let current = billing(in: month)
        if now < current {
            return (billing(in: calendar.date(byAdding: .month, value: -1, to: month)!), current)
        }
        return (current, billing(in: calendar.date(byAdding: .month, value: 1, to: month)!))
    }

    public static func assess(_ subscription: Subscription, snapshot: CollectorSnapshot?, now: Date = Date(), calendar: Calendar = .current) -> Assessment {
        let cycle = cycle(for: subscription, now: now, calendar: calendar)
        let since = max(calendar.startOfDay(for: subscription.observedSince), cycle.start)
        let today = calendar.startOfDay(for: now)
        // Only completed days count toward the observation threshold.
        let observed = max(0, calendar.dateComponents([.day], from: since, to: today).day ?? 0)
        var active = Set(subscription.manualDays.filter { $0 >= cycle.start && $0 < cycle.end && $0 <= now }.map { calendar.startOfDay(for: $0) })
        var tokens = 0
        if subscription.includesCLI, let snapshot {
            for usage in snapshot.days where usage.provider == subscription.provider {
                let parts = usage.day.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3, let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), day >= cycle.start, day < cycle.end, day <= now else { continue }
                if usage.requests > 0 { active.insert(day) }
                tokens += usage.tokens
            }
        }
        let completedActive = active.filter { $0 >= since && $0 < today }.count
        let rate = observed > 0 ? Double(completedActive) / Double(observed) : 0
        let valuable = subscription.valuableThisCycle && (subscription.valueMarkedAt.map { $0 >= cycle.start && $0 < cycle.end } ?? false)
        let recentCoverage = subscription.coverageConfirmed && (subscription.coverageConfirmedAt.map {
            $0 >= cycle.start && $0 <= now && now.timeIntervalSince($0) <= 7 * 24 * 60 * 60
        } ?? false)
        var verdict: Verdict
        var explanation: String
        var score: Int?
        if subscription.cancelledAt != nil {
            verdict = .buried; explanation = "Cancellation recorded. Confirm it with the service."
        } else if valuable {
            verdict = .keep; explanation = "You marked this cycle as worth it. Value beats frequency."
        } else if observed < 14 {
            verdict = .observing; explanation = "\(observed) completed observation days / 14 needed. Too early to call."
        } else if !recentCoverage || (subscription.includesCLI && snapshot?.sources.first(where: { $0.provider == subscription.provider })?.status != "ok") {
            verdict = .incomplete; explanation = "Confirm recent web, mobile and other-device usage. Local logs cannot prove non-use."
        } else {
            score = Int(((1 - min(rate, 1)) * 100).rounded())
            if rate <= 0.15 {
                verdict = .review; explanation = "Used on \(completedActive) of \(observed) completed days. Review before renewal."
            } else {
                verdict = .keep; explanation = "Used on \(completedActive) of \(observed) completed days. Putting it to work."
            }
        }
        return Assessment(verdict: verdict, activeDays: active.count, observationDays: observed, tokens: tokens,
                          riskScore: score, nextBilling: cycle.end, explanation: explanation)
    }
}
