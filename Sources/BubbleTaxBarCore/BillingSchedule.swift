import Foundation

public enum BillingInterval: String, Codable, CaseIterable {
    case monthly, yearly
    public var title: String { self == .monthly ? "Monthly" : "Yearly" }
}

/// User-entered calendar dates, independent of provider quota resets and billing APIs.
public struct BillingSchedule: Codable, Equatable {
    public var provider: Provider
    public var accountKey: String?
    public var anchor: Date
    public var interval: BillingInterval

    public init(provider: Provider, accountKey: String?, anchor: Date, interval: BillingInterval) {
        self.provider = provider; self.accountKey = accountKey
        self.anchor = anchor; self.interval = interval
    }

    public static func matching(_ schedules: [BillingSchedule], provider: Provider, accountKey: String?) -> BillingSchedule? {
        schedules.last { $0.provider == provider && $0.accountKey == accountKey }
    }

    public func nextRenewal(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: anchor)
        let today = calendar.startOfDay(for: now)
        guard start < today else { return start }
        let component: Calendar.Component = interval == .monthly ? .month : .year
        var steps = max(0, calendar.dateComponents([component], from: start, to: today).value(for: component) ?? 0)
        // Always advance from the original date, so a February clamp doesn't
        // move a January 31 renewal permanently to the 28th.
        var candidate = calendar.date(byAdding: component, value: steps, to: start) ?? start
        while candidate < today {
            steps += 1
            guard let next = calendar.date(byAdding: component, value: steps, to: start), next > candidate else { return today }
            candidate = next
        }
        return candidate
    }
}
