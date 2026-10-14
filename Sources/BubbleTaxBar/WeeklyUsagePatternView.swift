import SwiftUI
import BubbleTaxBarCore

struct WeeklyUsagePatternView: View {
    @EnvironmentObject var store: Store
    let provider: Provider
    private func number(_ value: Double?) -> String {
        (value ?? 0).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
    }
    var body: some View {
        let pattern = WeeklyUsagePattern.make(provider: provider, connection: store.connection(provider),
            windows: store.data.snapshot?.quotaWindows ?? [],
            samples: (provider == .claude ? store.data.claudeQuotaSamples : store.data.codexQuotaSamples) ?? [],
            modelEvents: store.data.modelUsageArchive ?? [])
        GroupBox {
            VStack(alignment: .leading, spacing: 5) {
                Text("To finish this week's quota").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                switch pattern.status {
                case .insufficient:
                    Text("Can't estimate yet").font(.callout.weight(.medium))
                    Text(pattern.reason ?? "").font(.caption2).foregroundStyle(.secondary)
                case .exhausted:
                    Text("Weekly quota already used").font(.callout.weight(.medium))
                case .feasible:
                    HStack(alignment: .firstTextBaseline) {
                        Text((pattern.hoursPerDay ?? 0) < 1 ? "≈ \(Int(ceil((pattern.hoursPerDay ?? 0) * 60))) min / day" : "≈ \(number(pattern.hoursPerDay))h / day").font(.title3.weight(.semibold)).monospacedDigit()
                        Spacer()
                        Text((pattern.hoursLeft ?? 0) >= 24 ? "\(number(pattern.hoursLeft.map { $0 / 24 })) days left" : "\(number(pattern.hoursLeft))h left").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text((pattern.fullQuotasPerDay ?? 0) < 0.1 ? "≈ \(number(pattern.fullQuotasPerDay.map { $0 * 100 }))% of one 5-hour quota / day" : "≈ \(number(pattern.fullQuotasPerDay)) full 5-hour quotas / day")
                        .font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: min(1, (pattern.hoursPerDay ?? 0) / 24)).tint(.secondary)
                        .accessibilityLabel("Estimated share of each day")
                        .help("Hours per day divided by 24. Recent observed pace includes idle time.")
                    Text("If that feels excessive, review the plan.").font(.caption2).foregroundStyle(.secondary)
                case .paceTooSlow:
                    Text("Not possible at your recent pace").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                    Text("Needs ≈ \(number(pattern.hoursNeeded))h · \(number(pattern.hoursLeft))h before reset")
                        .font(.caption).monospacedDigit()
                    Text("A faster pattern would be needed to finish.").font(.caption2).foregroundStyle(.secondary)
                case .windowsTooFew:
                    Text("Won't fit at observed rates").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                    Text("Even the highest observed conversion exceeds the remaining 5-hour quota capacity.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if pattern.intervals > 0 {
                    if pattern.availableFullQuotas == nil {
                        Text("5-hour capacity not currently reported").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(pattern.intervals == 1 ? "Early estimate · includes idle time" : "Observed pace · includes idle time")
                        .font(.caption2).foregroundStyle(.secondary)
                        .help("Based on elapsed observed time, including idle time. Rounded meters, model changes and other devices can change the result. Capacity assumes the highest observed weekly/5-hour conversion stays valid. This is not an absolute statement about what other models could consume.")
                    if !pattern.models.isEmpty {
                        Text("Local models seen: " + pattern.models.joined(separator: " + "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            .help("Local models seen during the measured intervals. Their exact share of account-wide quota isn't known.")
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
