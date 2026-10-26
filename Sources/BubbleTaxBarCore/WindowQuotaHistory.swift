import Foundation

/// Paired server meters, never transcript estimates. Keep the original observations;
/// compacted reset receipts cannot reconstruct within-window changes.
public struct WindowQuotaSample: Codable, Equatable {
    public let accountKey: String
    public let planLabel: String?
    public let session: QuotaWindow
    public let weekly: QuotaWindow
    public var observedAt: Double { max(session.observedAt, weekly.observedAt) }
    public var isLocalStream: Bool { accountKey.hasPrefix("local-session:") }
}

public struct WindowComparison: Identifiable {
    public let id: String
    public let samples: [WindowQuotaSample]
    public let hasGap: Bool
    public var first: WindowQuotaSample { samples.first! }
    public var last: WindowQuotaSample { samples.last! }
    public var sessionDelta: Double { last.session.usedPercent - first.session.usedPercent }
    public var weeklyDelta: Double { last.weekly.usedPercent - first.weekly.usedPercent }
    /// Weekly percentage points consumed per 100 session percentage points.
    /// At tiny deltas, rounded server percentages make ratios misleading.
    public var weeklyPerFullSession: Double? {
        samples.count >= 2 && !hasGap && sessionDelta >= 10 ? weeklyDelta / sessionDelta * 100 : nil
    }
}

public enum WindowQuotaHistory {
    public static let retentionDays = 180
    public static let maximumGap: Double = 900

    public static func record(_ existing: [WindowQuotaSample], windows: [QuotaWindow],
                              connection: ProviderConnection?, provider: Provider = .claude, now: Date = Date()) -> [WindowQuotaSample] {
        let time = now.timeIntervalSince1970
        var result = existing.filter { $0.session.provider == provider && valid($0, time: time) && $0.observedAt >= time - Double(retentionDays) * 86400 }
        if let connection, connection.provider == provider, connection.status == "connected",
           let account = connection.accountKey, !account.isEmpty {
            let fresh = windows.filter {
                $0.provider == provider && $0.accountKey == account &&
                $0.observedAt <= time && time - $0.observedAt <= maximumGap &&
                $0.resetsAt > time && $0.interrupted != true
            }
            // Only the server's primary 5-hour meter; never a model-specific one.
            if let session = fresh.filter({ $0.limitID == primaryID(provider) && $0.windowMinutes == 300 })
                .max(by: { $0.observedAt < $1.observedAt }) {
                for weekly in fresh where weekly.windowMinutes == 10080 && abs(weekly.observedAt - session.observedAt) <= 60 {
                    let value = WindowQuotaSample(accountKey: account, planLabel: connection.planLabel, session: session, weekly: weekly)
                    guard valid(value, time: time), !result.contains(value) else { continue }
                    result.append(value)
                }
            }
        }
        return result.sorted { $0.observedAt < $1.observedAt }
    }

    private static func primaryID(_ provider: Provider) -> String { provider == .claude ? "claude:primary" : "codex:primary" }

    private static func valid(_ sample: WindowQuotaSample, time: Double) -> Bool {
        guard [.claude, .openai].contains(sample.session.provider), !sample.accountKey.isEmpty, sample.session.limitID == primaryID(sample.session.provider),
              sample.session.windowMinutes == 300, sample.weekly.windowMinutes == 10080,
              abs(sample.session.observedAt - sample.weekly.observedAt) <= 60 else { return false }
        for window in [sample.session, sample.weekly] {
            guard window.provider == sample.session.provider, window.accountKey == sample.accountKey,
                  window.interrupted != true else { return false }
            guard window.usedPercent.isFinite, (0.0...100.0).contains(window.usedPercent) else { return false }
            guard window.observedAt.isFinite, window.resetsAt.isFinite,
                  window.observedAt <= time, window.resetsAt > window.observedAt else { return false }
        }
        return true
    }

    public static func comparisons(_ samples: [WindowQuotaSample], now: Date = Date()) -> [WindowComparison] {
        let groups = Dictionary(grouping: samples.filter { valid($0, time: now.timeIntervalSince1970) }) {
            "\($0.session.provider.rawValue)|\($0.accountKey)|\($0.weekly.limitID)|\($0.weekly.windowLabel ?? "")"
        }
        var result: [WindowComparison] = []
        for (key, values) in groups {
            var segment: [WindowQuotaSample] = []
            func finish() {
                guard let first = segment.first else { return }
                let gap = zip(segment, segment.dropFirst()).contains { $1.observedAt - $0.observedAt > maximumGap }
                result.append(WindowComparison(id: "\(key)|\(first.observedAt)", samples: segment, hasGap: gap))
            }
            for sample in values.sorted(by: { $0.observedAt < $1.observedAt }) {
                if let previous = segment.last {
                    let changed = sample.planLabel != previous.planLabel || abs(sample.session.resetsAt - previous.session.resetsAt) > 60 ||
                        abs(sample.weekly.resetsAt - previous.weekly.resetsAt) > 60 ||
                        sample.session.usedPercent < previous.session.usedPercent ||
                        sample.weekly.usedPercent < previous.weekly.usedPercent ||
                        sample.observedAt >= previous.session.resetsAt || sample.observedAt >= previous.weekly.resetsAt
                    if changed { finish(); segment = [] }
                    if sample == previous { continue }
                }
                segment.append(sample)
            }
            finish()
        }
        return result.sorted { $0.first.observedAt < $1.first.observedAt }
    }
}

// Existing state files and callers keep their Claude names.
public typealias ClaudeQuotaSample = WindowQuotaSample
public typealias ClaudeWindowComparison = WindowComparison
public enum ClaudeWindowHistory {
    public static let retentionDays = WindowQuotaHistory.retentionDays
    public static let maximumGap = WindowQuotaHistory.maximumGap
    public static func record(_ existing: [ClaudeQuotaSample], windows: [QuotaWindow],
                              connection: ProviderConnection?, now: Date = Date()) -> [ClaudeQuotaSample] {
        WindowQuotaHistory.record(existing, windows: windows, connection: connection, provider: .claude, now: now)
    }
    public static func comparisons(_ samples: [ClaudeQuotaSample], now: Date = Date()) -> [ClaudeWindowComparison] {
        WindowQuotaHistory.comparisons(samples, now: now)
    }
}
