import Foundation

/// Actual statusline quota meters, isolated by a hashed Claude session ID.
/// These scopes are not accounts and must never enter subscription forecasts.
public enum ClaudeLocalQuotaJournal {
    private struct Entry: Decodable {
        let streamID: String?
        let windows: [QuotaWindow]
    }

    public static func merge(_ existing: [WindowQuotaSample], data: Data?, now: Date = Date()) -> [WindowQuotaSample] {
        var result = existing.filter { $0.isLocalStream }
        if let data, data.count <= 16 * 1024 * 1024,
           let entries = try? JSONDecoder().decode([Entry].self, from: data), entries.count <= 10000 {
            for entry in entries {
                guard let stream = entry.streamID, stream.count == 64,
                      stream.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { continue }
                let scope = "local-session:" + stream
                let windows = entry.windows.filter { value in
                    [300, 10080].contains(value.windowMinutes) && value.provider == .claude && value.accountKey == nil && value.interrupted != true &&
                    value.usedPercent.isFinite && (0...100).contains(value.usedPercent) &&
                    value.observedAt.isFinite && value.observedAt <= now.timeIntervalSince1970 &&
                    value.resetsAt.isFinite && value.resetsAt > value.observedAt &&
                    value.resetsAt <= value.observedAt + Double(value.windowMinutes * 60 + 60)
                }
                guard var session = windows.first(where: { $0.limitID == "claude:primary" && $0.windowMinutes == 300 }),
                      var weekly = windows.first(where: { $0.limitID == "claude:secondary" && $0.windowMinutes == 10080 }),
                      abs(session.observedAt - weekly.observedAt) <= 60 else { continue }
                session.accountKey = scope; weekly.accountKey = scope
                session.windowLabel = "Session"; weekly.windowLabel = "Weekly"
                result.append(WindowQuotaSample(accountKey: scope, planLabel: nil, session: session, weekly: weekly))
            }
        }
        // Reuse validation and retention, including reset/gap boundaries. Deduplicate
        // journal reimports without relying on local account ownership.
        let valid = WindowQuotaHistory.record(result, windows: [], connection: nil, now: now)
        var keys = Set<String>()
        return valid.filter {
            keys.insert("\($0.accountKey)|\($0.observedAt)|\($0.session.resetsAt)|\($0.weekly.resetsAt)|\($0.session.usedPercent)|\($0.weekly.usedPercent)").inserted
        }.suffix(20000).map { $0 }
    }
}
