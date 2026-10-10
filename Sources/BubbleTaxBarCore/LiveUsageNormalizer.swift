import Foundation
import CryptoKit
import CoreFoundation

/// Converts the bundled usage helper's response to privacy-safe app metadata.
public enum LiveUsageNormalizer {
    public static func helperID(_ provider: Provider) -> String? {
        switch provider {
        case .openai: return "codex"
        case .claude: return "claude"
        case .cursor: return "cursor"
        case .copilot: return "copilot"
        case .antigravity: return "antigravity"
        default: return nil
        }
    }

    public static func normalize(_ data: Data, provider: Provider) throws -> (ProviderConnection, [QuotaWindow]) {
        let document = try JSONSerialization.jsonObject(with: data)
        let row = (document as? [[String: Any]])?.first ?? (document as? [String: Any])
        var connection: [String: Any] = ["provider": provider.rawValue, "status": "unavailable", "source": "server"]
        var quotas: [QuotaWindow] = []
        if let row, row["error"] == nil || row["error"] is NSNull || (row["error"] as? Bool) == false || (row["error"] as? String) == "",
           let usage = row["usage"] as? [String: Any], let helper = helperID(provider) {
            let identity = usage["identity"] as? [String: Any] ?? [:]
            if let label = (identity["loginMethod"] ?? usage["loginMethod"]) as? String, label.count <= 160 {
                connection["planLabel"] = label
            }
            var account: String?
            if let subject = (identity["accountEmail"] ?? usage["accountEmail"]) as? String, !subject.isEmpty {
                let organization = (identity["accountOrganization"] ?? usage["accountOrganization"]) as? String ?? ""
                account = SHA256.hash(data: Data((subject + "|" + organization).utf8))
                    .map { String(format: "%02x", $0) }.joined().prefix(24).description
                connection["accountKey"] = account
            }
            let observed = epoch(usage["updatedAt"])
            connection["status"] = "connected"
            connection["source"] = String((row["source"] as? String ?? "server").prefix(40))
            if let observed { connection["observedAt"] = observed }
            let labels = row["rateWindowLabels"] as? [String: Any] ?? [:]
            for key in ["primary", "secondary", "tertiary"] {
                guard let window = usage[key] as? [String: Any],
                      let used = number(window["usedPercent"]), (0...100).contains(used),
                      let minutes = number(window["windowMinutes"]), minutes > 0,
                      minutes < Double(Int.max), minutes.rounded(.down) == minutes,
                      let observed, let reset = epoch(window["resetsAt"]), reset > observed else { continue }
                quotas.append(QuotaWindow(provider: provider, limitID: helper + ":" + key,
                    windowMinutes: Int(minutes), resetsAt: reset, observedAt: observed,
                    usedPercent: used, accountKey: account, windowLabel: labels[key] as? String))
            }
        }
        return (try JSONDecoder().decode(ProviderConnection.self, from: JSONSerialization.data(withJSONObject: connection)), quotas)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private static func epoch(_ value: Any?) -> Double? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)?.timeIntervalSince1970
    }
}
