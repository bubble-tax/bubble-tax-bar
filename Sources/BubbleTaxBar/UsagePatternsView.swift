import SwiftUI
import BubbleTaxBarCore

struct UsagePatternsView: View {
    @EnvironmentObject var store: Store
    @State private var provider: Provider = .claude
    var body: some View {
        let summary = UsagePatternSummary.make(events: store.data.modelUsageArchive ?? [], provider: provider)
        VStack(alignment: .leading, spacing: 14) {
            Text("A closer look at the input.").font(.title3.weight(.semibold))
            Picker("Local logs", selection: $provider) { Text("Claude").tag(Provider.claude); Text("Codex").tag(Provider.openai) }.pickerStyle(.segmented).labelsHidden()
            Text("Local logs · last 7 days · across accounts").font(.caption2).foregroundStyle(.secondary)
            if summary.requests > 0 {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Repeated large inputs").font(.headline); Spacer(); Text("\(summary.largeNewInputs) / \(summary.knownRequests)").monospacedDigit() }
                        ProgressView(value: Double(summary.largeNewInputs), total: Double(max(1, summary.knownRequests))).tint(.secondary)
                        Text(summary.largeNewInputs >= 3 ? "Several requests carried at least 32K new input tokens. Check repeated files or instructions if unexpected." : "No repeated large-input pattern in the measured requests.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Reused input").font(.headline)
                            Spacer()
                            Text(summary.reuseShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "Unknown").font(.title3.weight(.semibold)).monospacedDigit()
                        }
                        if let share = summary.reuseShare { ProgressView(value: share).tint(.secondary) }
                        Text("Cache reads as a share of known input tokens. Reuse is context; its billing and quota effect depends on the provider.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local model mix").font(.headline)
                        ForEach(Array(summary.models.prefix(3).enumerated()), id: \.offset) { _, model in
                            HStack {
                                Text(model.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(Int((Double(model.tokens) / Double(max(1, summary.totalTokens)) * 100).rounded()))%")
                            }.font(.caption)
                            ProgressView(value: Double(model.tokens), total: Double(max(1, summary.totalTokens))).tint(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("\(summary.requests) local events · \(summary.knownRequests) with token breakdowns. Large inputs may be necessary. These records don't reveal retries, task success, or which account paid.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("No local activity yet", systemImage: "chart.bar.xaxis", description: Text("Connect code logs in Settings. Quota readings alone can't explain request patterns."))
            }
        }
    }
}
