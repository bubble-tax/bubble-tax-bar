import SwiftUI
import BubbleTaxBarCore

struct PiActivity: View {
    @EnvironmentObject var store: Store
    var provider: Provider? = nil

    private var days: [PiUsageDay] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -29, to: Date())!
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return (store.data.snapshot?.piUsage?.days ?? []).filter { day in
            guard let date = formatter.date(from: day.day), date >= Calendar.current.startOfDay(for: cutoff),
                  date <= Date() else { return false }
            guard let provider else { return true }
            switch provider {
            case .openai: return ["openai-codex", "openai"].contains(day.providerID)
            case .claude: return day.providerID == "anthropic"
            case .copilot: return day.providerID == "github-copilot"
            default: return false
            }
        }
    }
    var body: some View {
        if let usage = store.data.snapshot?.piUsage {
            let groups = Dictionary(grouping: days, by: \.providerID)
            VStack(alignment: .leading, spacing: 4) {
                if provider == nil || !groups.isEmpty {
                    Text("Pi activity · 30d\(usage.status == "partial" ? " · partial" : "")")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    ForEach(groups.keys.sorted(), id: \.self) { id in
                        HStack {
                            Text(name(id)).font(.caption)
                            Spacer()
                            Text("\((groups[id] ?? []).reduce(0) { $0 + $1.tokens }.formatted()) tokens")
                                .font(.caption).monospacedDigit()
                        }
                    }
                    if groups.isEmpty { Text(usage.status == "no_usage" || usage.status == "ok" ? "No recorded activity in this period." : "Session data unavailable.").font(.caption).foregroundStyle(.secondary) }
                    if !groups.isEmpty { Text("Recorded tokens · not quota remaining or an invoice").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
    }
    private func name(_ id: String) -> String {
        switch id {
        case "openai-codex": return "ChatGPT / Codex"
        case "github-copilot": return "GitHub Copilot"
        case "anthropic": return "Claude · billing unverified"
        case "openai": return "OpenAI API"
        case "kimi-coding": return "Kimi Coding"
        case "zai", "zai-coding-cn": return "Z.ai"
        case "minimax", "minimax-cn": return "MiniMax"
        case "qwen-token-plan", "qwen-token-plan-cn": return "Qwen Token Plan"
        case "radius": return "Radius"
        case "other": return "Other provider"
        default: return id
        }
    }
}
