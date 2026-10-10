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
            verdict = .buried; explanation = "사용자가 해지를 기록했어요. 서비스 해지 여부는 직접 확인해야 해요."
        } else if valuable {
            verdict = .keep; explanation = "이번 결제 주기에 중요한 가치를 얻었다고 표시했어요. 사용 횟수보다 가치가 우선이에요."
        } else if observed < 14 {
            verdict = .observing; explanation = "완료된 관찰일 \(observed)일 / 최소 14일. 지금은 해지 판단을 보류해요."
        } else if !recentCoverage || (subscription.includesCLI && snapshot?.sources.first(where: { $0.provider == subscription.provider })?.status != "ok") {
            verdict = .incomplete; explanation = "최근 7일 내 웹·모바일·다른 기기의 기록을 확인해 주세요. 편집에서 기록 확인을 다시 저장할 수 있어요. 로컬 로그만으로 미사용을 단정할 수 없어요."
        } else {
            score = Int(((1 - min(rate, 1)) * 100).rounded())
            if rate <= 0.15 {
                verdict = .review; explanation = "완료된 관찰일 \(observed)일 중 사용 \(completedActive)일. 다음 결제 전에 해지·다운그레이드를 검토해 보세요."
            } else {
                verdict = .keep; explanation = "완료된 관찰일 \(observed)일 중 사용 \(completedActive)일. 꾸준히 사용하고 있어요."
            }
        }
        return Assessment(verdict: verdict, activeDays: active.count, observationDays: observed, tokens: tokens,
                          riskScore: score, nextBilling: cycle.end, explanation: explanation)
    }
}
