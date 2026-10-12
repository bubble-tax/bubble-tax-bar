import SwiftUI
import Charts
import BubbleTaxBarCore

struct ClaudeWindowHistoryView: View {
    @EnvironmentObject var store: Store
    @State private var selectedLimit = ""

    private func key(_ value: ClaudeWindowComparison) -> String {
        "\(value.first.accountKey)|\(value.first.planLabel ?? "unknown")|\(value.first.weekly.limitID)"
    }
    private func title(_ value: ClaudeWindowComparison) -> String {
        let weekly = value.first.weekly
        let label = weekly.windowLabel ?? (weekly.limitID == "claude:secondary" ? "All models" : "Model-specific")
        let previous = store.connection(.claude)?.accountKey != value.first.accountKey
        return "\(label) · \(value.first.planLabel ?? "Unknown plan")" + (previous ? " · Previous account" : "")
    }

    var body: some View {
        let all = ClaudeWindowHistory.comparisons(store.data.claudeQuotaSamples ?? [])
        let choices = all.reduce(into: [ClaudeWindowComparison]()) { result, value in
            if !result.contains(where: { key($0) == key(value) }) { result.append(value) }
        }.reversed()
        let active = choices.contains(where: { key($0) == selectedLimit }) ? selectedLimit : choices.first.map(key) ?? ""
        let rows = Array(all.filter { key($0) == active }.suffix(30))
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("5-hour → weekly").font(.headline)
                if rows.isEmpty {
                    Label("Waiting for paired readings", systemImage: "clock").font(.callout.weight(.medium))
                    Text("Connect Claude and keep Bubble Tax running. Each refresh records the 5-hour and weekly meters together; earlier windows can't be reconstructed.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    if choices.count > 1 {
                        Picker("Weekly meter", selection: Binding(get: { active }, set: { selectedLimit = $0 })) {
                            ForEach(Array(choices)) { value in Text(title(value)).tag(key(value)) }
                        }
                    } else if let value = rows.first {
                        Text(title(value)).font(.caption).foregroundStyle(.secondary)
                    }
                    let comparable = rows.filter { $0.weeklyPerFullSession != nil }
                    if !comparable.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Observed weekly cost").font(.callout.weight(.medium))
                                let rates = comparable.compactMap(\.weeklyPerFullSession)
                                Text("\(rates.min()!.formatted(.number.precision(.fractionLength(1))))–\(rates.max()!.formatted(.number.precision(.fractionLength(1)))) weekly pp / full 5-hour quota")
                                    .font(.caption).monospacedDigit()
                                Chart(comparable) { row in
                                    PointMark(x: .value("5-hour used (pp)", row.sessionDelta),
                                              y: .value("Weekly used (pp)", row.weeklyDelta))
                                        .foregroundStyle(Color.primary).symbolSize(45)
                                        .accessibilityLabel(row.first.session.resetDate.formatted())
                                        .accessibilityValue("5-hour \(row.sessionDelta) points, weekly \(row.weeklyDelta) points")
                                }
                                .chartXScale(domain: 0...100)
                                .chartYAxisLabel("Weekly pp")
                                .chartXAxisLabel("5-hour pp · one dot per observed window segment")
                                .frame(height: 150)
                                Text("Different slopes mean different observed cost. This is not a fixed conversion rule.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ForEach(rows.reversed()) { row in
                        ClaudeWindowReceipt(row: row)
                    }
                }
                Text("Local history · last 180 days · latest 30 segments shown. Refreshes every 5 minutes while running. pp = percentage points.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Changes cover the observed interval, not an entire window. Reset, meter decrease and plan changes start a new segment. Gaps over 15 minutes and changes under 10 session pp are excluded from rate comparisons. Rounded meters and reporting delays affect ratios. Claude-wide usage is included; models and unobserved activity aren't inferred.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(16)
        }.frame(height: 490)
    }
}

private struct ClaudeWindowReceipt: View {
    let row: ClaudeWindowComparison
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(row.first.session.resetDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text(row.last.session.resetsAt > Date().timeIntervalSince1970 ? "In progress" : "Recorded")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("5-hour reset · \(row.samples.count) \(row.samples.count == 1 ? "reading" : "readings")").font(.caption2).foregroundStyle(.secondary)
                if row.samples.count < 2 {
                    Text("One reading · waiting for a change").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("+\(number(row.sessionDelta)) pp").font(.title3.weight(.medium))
                        Text("5-hour").font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text("+\(number(row.weeklyDelta)) pp").font(.title3.weight(.medium))
                        Text("weekly").font(.caption).foregroundStyle(.secondary)
                    }.monospacedDigit()
                    if let rate = row.weeklyPerFullSession {
                        Text("≈ \(number(rate)) weekly pp per full 5-hour quota")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(row.hasGap ? "Collection gap · rate unavailable" : "Too little observed usage to compare rates")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Observed interval") {
                        Text("\(Date(timeIntervalSince1970: row.first.observedAt).formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US")))) → \(Date(timeIntervalSince1970: row.last.observedAt).formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US"))))")
                            .font(.caption2).foregroundStyle(.secondary)
                        Chart {
                            ForEach(Array(row.samples.enumerated()), id: \.offset) { _, sample in
                                let date = Date(timeIntervalSince1970: sample.observedAt)
                                if row.hasGap {
                                    PointMark(x: .value("Time", date), y: .value("Change", sample.session.usedPercent - row.first.session.usedPercent))
                                        .foregroundStyle(by: .value("Meter", "5-hour"))
                                    PointMark(x: .value("Time", date), y: .value("Change", sample.weekly.usedPercent - row.first.weekly.usedPercent))
                                        .foregroundStyle(by: .value("Meter", "Weekly"))
                                } else {
                                    LineMark(x: .value("Time", date), y: .value("Change", sample.session.usedPercent - row.first.session.usedPercent))
                                        .foregroundStyle(by: .value("Meter", "5-hour"))
                                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                                    LineMark(x: .value("Time", date), y: .value("Change", sample.weekly.usedPercent - row.first.weekly.usedPercent))
                                        .foregroundStyle(by: .value("Meter", "Weekly"))
                                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                }
                            }
                        }
                        .chartForegroundStyleScale(["5-hour": Color.primary, "Weekly": Color.orange])
                        .chartYAxisLabel("Change (pp)").frame(height: 130)
                        Text("Weekly reset: " + row.first.weekly.resetDate.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US"))))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("Used meters: 5-hour \(number(row.first.session.usedPercent)) → \(number(row.last.session.usedPercent))%; weekly \(number(row.first.weekly.usedPercent)) → \(number(row.last.weekly.usedPercent))%")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
