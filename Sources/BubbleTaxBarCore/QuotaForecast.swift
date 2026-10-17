import Foundation

public struct QuotaForecast {
    public let weeklyPerObservedHour: Double
    public let plannedHoursPerDay: Double
    public let weeklyPerDay: Double
    public let daysToEmpty: Double
    public let daysToProtectedFloor: Double
    public let daysBeforeReset: Double
    public let reserveAtRisk: Bool
    public let observations: Int

    public static func make(option: AllocationOption, samples: [WindowQuotaSample], reservations: [QuotaReservation],
                            hoursPerDay: Double, now: Date = Date()) -> Self? {
        guard hoursPerDay.isFinite, hoursPerDay > 0, hoursPerDay <= 24 else { return nil }
        let rows = WindowQuotaHistory.comparisons(samples, now: now).filter {
            $0.first.session.provider == option.provider && $0.first.accountKey == option.connection.accountKey &&
            $0.first.planLabel == option.connection.planLabel && $0.first.weekly.limitID == option.weekly.limitID &&
            $0.first.weekly.windowLabel == option.weekly.windowLabel &&
            abs($0.first.weekly.resetsAt - option.weekly.resetsAt) <= 60 &&
            $0.last.observedAt <= option.weekly.observedAt + 60 &&
            $0.weeklyPerFullSession != nil && $0.weeklyDelta >= 1 &&
            $0.last.observedAt - $0.first.observedAt >= 900
        }
        let duration = rows.reduce(0) { $0 + ($1.last.observedAt - $1.first.observedAt) / 3600 }
        let change = rows.reduce(0) { $0 + $1.weeklyDelta }
        guard duration > 0, change > 0 else { return nil }
        let rate = change / duration, daily = rate * hoursPerDay
        let resetDays = max(0, (option.weekly.resetsAt - now.timeIntervalSince1970) / 86400)
        let active = reservations.filter { $0.matches(option.weekly, plan: option.connection.planLabel, now: now) }
        let atRisk = active.contains { target in
            let days = max(0, target.deadline.timeIntervalSince(now) / 86400)
            // Protect all still-pending targets until their deadlines. Completing
            // work releases its target; provider readings account for actual use.
            let outstanding = active.filter { $0.deadline >= target.deadline }.reduce(0) { $0 + $1.percent }
            return option.weekly.remainingPercent - days * daily < outstanding
        }
        return Self(weeklyPerObservedHour: rate, plannedHoursPerDay: hoursPerDay, weeklyPerDay: daily,
            daysToEmpty: option.weekly.remainingPercent / daily,
            daysToProtectedFloor: option.available / daily, daysBeforeReset: resetDays,
            reserveAtRisk: atRisk || option.protected > option.weekly.remainingPercent, observations: rows.count)
    }
}
