import Foundation

public struct UnusedQuotaGroup: Identifiable {
    public let id: String
    public let provider: Provider
    public let accountKey: String
    public let limitID: String
    public let windowMinutes: Int
    public let title: String
    public let windows: [QuotaWindow]
    public var averageUnused: Double { windows.reduce(0) { $0 + $1.remainingPercent } / Double(windows.count) }
    // Comparable only inside the same account and limit. Not tokens or money.
    public var fullWindowEquivalent: Double { windows.reduce(0) { $0 + $1.remainingPercent / 100 } }
}

public enum UnusedQuotaHistory {
    public static func eligibleWindows(_ windows: [QuotaWindow], now: Date = Date()) -> [QuotaWindow] {
        let time = now.timeIntervalSince1970
        let valid = windows.filter {
            $0.windowMinutes > 0 && $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) &&
            $0.resetsAt.isFinite && $0.observedAt.isFinite &&
            $0.observedAt <= time && $0.observedAt < $0.resetsAt &&
            !($0.accountKey?.isEmpty ?? true)
        }
        // Include current readings when detecting interrupted/early resets.
        return QuotaUsage.compact(valid).filter {
            $0.resetsAt <= time && $0.interrupted != true && $0.resetsAt - $0.observedAt <= 900
        }
    }

    public static func groups(_ windows: [QuotaWindow], since: Date? = nil, now: Date = Date()) -> [UnusedQuotaGroup] {
        let eligible = eligibleWindows(windows, now: now).filter { since == nil || $0.resetDate >= since! }
        let grouped = Dictionary(grouping: eligible) {
            "\($0.provider.rawValue)|\($0.accountKey!)|\($0.limitID)|\($0.windowMinutes)"
        }
        return grouped.map { key, values in
            let sorted = values.sorted { $0.resetsAt < $1.resetsAt }
            let last = sorted.last!
            let title: String
            switch last.windowMinutes {
            case 10080: title = "Weekly quota"
            case 300: title = "5-hour quota"
            case 1440: title = "Daily quota"
            case 43200: title = "Monthly quota"
            default: title = "\(last.windowMinutes) min quota"
            }
            return UnusedQuotaGroup(id: key, provider: last.provider, accountKey: last.accountKey!,
                limitID: last.limitID, windowMinutes: last.windowMinutes,
                title: last.windowLabel.map { $0 == title ? title : title + " · " + $0 } ?? title, windows: sorted)
        }.sorted {
            if $0.provider != $1.provider { return $0.provider.rawValue < $1.provider.rawValue }
            if $0.windowMinutes != $1.windowMinutes { return $0.windowMinutes > $1.windowMinutes }
            return $0.id < $1.id
        }
    }
}
