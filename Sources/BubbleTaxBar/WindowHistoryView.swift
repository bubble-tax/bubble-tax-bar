import SwiftUI
import Charts
import BubbleTaxBarCore

struct WindowHistoryView: View {
    let provider: Provider
    @EnvironmentObject var store: Store
    @State private var selectedLimit = ""
    @State private var selectedModel = ""

    private func key(_ value: WindowComparison) -> String {
        "\(value.first.accountKey)|\(value.first.planLabel ?? "unknown")|\(value.first.weekly.limitID)|\(value.first.weekly.windowLabel ?? "")"
    }
    private func title(_ value: WindowComparison) -> String {
        let weekly = value.first.weekly
        let label = weekly.windowLabel ?? (weekly.limitID == "claude:secondary" ? "All models" : "Model-specific")
        if value.first.isLocalStream {
            return "Local session " + value.first.accountKey.suffix(6) + " · account unverified"
        }
        let previous = store.connection(provider)?.accountKey.map { $0 != value.first.accountKey } ?? false
        return "\(label) · \(value.first.planLabel ?? "Unknown plan")" + (previous ? " · Previous account" : "")
    }

    var body: some View {
        let verified = (provider == .claude ? store.data.claudeQuotaSamples : store.data.codexQuotaSamples) ?? []
        let local = provider == .claude ? (store.data.claudeLocalQuotaSamples ?? []) : []
        let all = WindowQuotaHistory.comparisons(verified + local)
        let choices = all.reversed().reduce(into: [WindowComparison]()) { result, value in
            if !result.contains(where: { key($0) == key(value) }) { result.append(value) }
        }
        let currentAccount = store.connection(provider)?.accountKey
        let preferred = choices.first { !$0.first.isLocalStream && $0.first.accountKey == currentAccount } ?? choices.first
        let active = choices.contains(where: { key($0) == selectedLimit }) ? selectedLimit : preferred.map(key) ?? ""
        let candidates = Array(all.filter { key($0) == active }.suffix(30))
        let events = store.data.modelUsageArchive ?? []
        let models = Set(candidates.flatMap { WindowModelActivity.summaries(events, window: $0).compactMap(\.model) }).sorted()
        let activeModel = models.contains(selectedModel) ? selectedModel : ""
        let rows = candidates.filter { activeModel.isEmpty || WindowModelActivity.summaries(events, window: $0).contains { $0.model == activeModel } }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(provider == .claude ? "Claude" : "Codex") · 5-hour → weekly").font(.headline)
                if let latest = rows.last {
                    Text("Last paired reading · " + Date(timeIntervalSince1970: latest.last.observedAt)
                        .formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US"))))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if provider == .claude, let connection = store.connection(provider) {
                    Text(connection.status == "connected" ? "Reading via " + (connection.source ?? "server") +
                         (connection.accountKey == nil ? " · account unverified" : " · account identified") :
                         "Live lookup unavailable · saved readings shown")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if rows.isEmpty {
                    Label("Waiting for paired readings", systemImage: "clock").font(.callout.weight(.medium))
                    Text("Connect \(provider == .claude ? "Claude" : "Codex") and keep Bubble Tax running. Each refresh records the 5-hour and weekly meters together. Local statusline sessions are stored separately; earlier unrecorded windows cannot be reconstructed.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    if choices.count > 1 {
                        Picker("Weekly meter", selection: Binding(get: { active }, set: { selectedLimit = $0 })) {
                            ForEach(Array(choices)) { value in Text(title(value)).tag(key(value)) }
                        }
                    } else if let value = rows.first {
                        Text(title(value)).font(.caption).foregroundStyle(.secondary)
                    }
                    if !models.isEmpty {
                        Picker("Local model", selection: Binding(get: { activeModel }, set: { selectedModel = $0 })) {
                            Text("All local mixes").tag("")
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }.help("Includes windows where local logs contain this model, including mixed-model windows.")
                    }
                    let comparable = rows.filter { $0.weeklyPerFullSession != nil }
                    if !comparable.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Observed weekly cost").font(.callout.weight(.medium))
                                let rates = comparable.compactMap(\.weeklyPerFullSession)
                                let low = rates.min()!.formatted(.number.precision(.fractionLength(1)))
                                let high = rates.max()!.formatted(.number.precision(.fractionLength(1)))
                                Text("\(low == high ? low : low + "–" + high) weekly pp / full 5-hour quota")
                                    .font(.caption).monospacedDigit()
                                if comparable.count > 1 {
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
                                .frame(height: 116)
                                Text("Different slopes mean different observed cost. This is not a fixed conversion rule.")
                                    .font(.caption2).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ForEach(rows.reversed()) { row in
                        WindowReceipt(row: row, models: WindowModelActivity.summaries(events, window: row), logsConnected: store.logFolder(provider) != nil)
                    }
                }
                if rows.first?.first.isLocalStream == true {
                    Text("Measured statusline quotas for this local session. Account ownership is unverified; these readings are never merged into account history or subscription recommendations.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("Local model activity adds context; quota changes are account-wide.")
                    .font(.caption2).foregroundStyle(.secondary)
                DisclosureGroup("About these records") {
                    Text("Latest 30 segments · 180 days · refresh every 5 minutes. pp = percentage points. Resets and plan changes start new segments. Gaps and small changes are excluded from rate comparisons. Local logs may be incomplete and their account ownership isn't verified. Token mix isn't quota share.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.font(.caption)

            }.padding(16)
        }.frame(height: 490)
    }
}

private struct WindowReceipt: View {
    let row: WindowComparison
    let models: [ModelUsageSummary]
    let logsConnected: Bool
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
                    Text("5-hour \(number(row.last.session.usedPercent))% used · weekly \(number(row.last.weekly.usedPercent))% used")
                        .font(.caption).monospacedDigit()
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
                    ModelMixView(models: models, logsConnected: logsConnected)
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

private struct ModelMixView: View {
    let models: [ModelUsageSummary]
    let logsConnected: Bool
    private var total: Int { models.reduce(0) { $0 + $1.tokens } }
    private func color(_ model: ModelUsageSummary) -> Color {
        guard let name = model.model else { return .secondary }
        if name.contains("opus") { return .orange }
        if name.contains("sonnet") { return .blue }
        if name.contains("haiku") { return .green }
        let index = name.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fffffff }
        return [Color.blue, .orange, .purple, .green][index % 4]
    }
    var body: some View {
        if models.isEmpty {
            Text(logsConnected ? "No local model records in this interval" : "Connect code logs in Settings for model context")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("Local model mix").font(.caption.weight(.medium))
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        ForEach(models) { model in
                            Rectangle().fill(color(model))
                                .frame(width: max(0, (geometry.size.width - CGFloat(models.count - 1)) * Double(model.tokens) / Double(total)))
                                .help("\(model.title): \(model.tokens.formatted()) local tokens")
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 3))
                }.frame(height: 7).accessibilityLabel("Local token mix")
                ForEach(models) { model in
                    HStack(spacing: 5) {
                        Circle().fill(color(model)).frame(width: 5, height: 5)
                        Text(model.title).lineLimit(1).truncationMode(.middle).help(model.title)
                        Spacer(minLength: 3)
                        Text("\(Int((100 * Double(model.tokens) / Double(total)).rounded()))% · \(model.tokens.formatted(.number.notation(.compactName).locale(Locale(identifier: "en_US"))))")
                            .monospacedDigit()
                    }.font(.caption2)
                }
                DisclosureGroup("Token details") {
                    ForEach(models) { model in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(model.title) · \(model.requests) \(model.requests == 1 ? "record" : "records")")
                                .font(.caption2.weight(.medium))
                            if model.breakdownKnown {
                                Text("Input \(model.input.formatted()) · Output \(model.output.formatted())\nCache read \(model.cacheRead.formatted()) · Cache write \(model.cacheWrite.formatted())")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text("Token breakdown unavailable").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                    }
                    Text("Local code logs only · token share, not quota share")
                        .font(.caption2).foregroundStyle(.secondary)
                }.font(.caption2)
            }.padding(.vertical, 4)
        }
    }
}
