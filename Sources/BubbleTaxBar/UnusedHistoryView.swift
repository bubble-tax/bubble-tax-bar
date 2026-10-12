import SwiftUI
import Charts
import BubbleTaxBarCore

struct UnusedHistoryView: View {
    @EnvironmentObject var store: Store
    @State private var last30Days = false
    @State private var claudeWindows = CommandLine.arguments.contains("--show-claude-windows")

    var body: some View {
        VStack(spacing: 0) {
            Picker("History", selection: $claudeWindows) {
                Text("Unused quota").tag(false)
                Text("Claude windows").tag(true)
            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.top, 8)
            if claudeWindows { ClaudeWindowHistoryView() } else { unusedHistory }
        }
    }

    @ViewBuilder private var unusedHistory: some View {
        let now = Date()
        let windows = (store.data.unusedQuotaArchive ?? []) + (store.data.snapshot?.quotaWindows ?? [])
        let groups = UnusedQuotaHistory.groups(windows,
            since: last30Days ? now.addingTimeInterval(-30 * 86400) : nil, now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Period", selection: $last30Days) {
                    Text("All recorded").tag(false)
                    Text("Last 30 days").tag(true)
                }.pickerStyle(.segmented)
                if groups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No recorded resets yet", systemImage: "clock")
                            .font(.headline)
                        Text("Keep Bubble Tax running near quota resets to collect what was left.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(.vertical, 16)
                } else {
                    Text("\(groups.reduce(0) { $0 + $1.windows.count }) recorded \(groups.reduce(0) { $0 + $1.windows.count } == 1 ? "reset" : "resets")")
                        .font(.callout.weight(.medium))
                    ForEach(groups) { group in
                        UnusedHistoryGroup(group: group,
                            previousAccount: store.connection(group.provider)?.accountKey != group.accountKey)
                    }
                }
                Text("Left near reset · checks within 15 minutes. Missing periods and early resets are excluded. Separate limits aren't added together.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("History is kept locally from observed resets. Earlier unrecorded usage can't be recovered.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(16)
        }.frame(height: 490)
    }
}

private struct UnusedHistoryGroup: View {
    let group: UnusedQuotaGroup
    let previousAccount: Bool
    private var subtitle: String {
        let parts = group.title.components(separatedBy: " · ")
        if parts.count == 2, parts[0].localizedCaseInsensitiveContains(parts[1]) || (group.windowMinutes == 300 && parts[1] == "Session") { return parts[0] }
        return group.title
    }
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("~\(Int(group.averageUnused.rounded()))%")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text("avg. unused").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(group.windows.count) \(group.windows.count == 1 ? "reset" : "resets")").font(.caption).foregroundStyle(.secondary)
                }
                UnusedResetChart(windows: group.windows, average: group.averageUnused)
                DisclosureGroup("Reset receipts") {
                    Text("≈ \(group.fullWindowEquivalent.formatted(.number.precision(.fractionLength(1)))) full windows left across these resets")
                        .font(.caption2).foregroundStyle(.secondary)
                        .help("Sum of remaining fractions for this exact account and limit. Not tokens or money; quota capacity may change between resets.")
                    ForEach(group.windows.reversed(), id: \.resetsAt) { reading in
                        HStack(spacing: 10) {
                            Text(reading.resetDate, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            QuotaBalanceBar(remaining: reading.remainingPercent).frame(width: 65)
                            Text("\(Int(reading.remainingPercent.rounded()))%")
                                .font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                        }.padding(.vertical, 3)
                            .help("Checked " + reading.observedDate.formatted(.dateTime.year().month().day().hour().minute()))
                    }
                }.font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.provider.serviceName).font(.callout.weight(.semibold))
                Text(subtitle + (previousAccount ? " · Previous account" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Each bar is one observed reset, placed at its actual time. The faint track
/// represents the full limit; only the colored portion was left near reset.
private struct UnusedResetChart: View {
    let windows: [QuotaWindow]
    let average: Double
    @State private var hoveredReset: Date?

    private var samples: [QuotaWindow] { Array(windows.suffix(30)) }
    private var selected: QuotaWindow? {
        guard let hoveredReset else { return nil }
        return samples.min { abs($0.resetDate.timeIntervalSince(hoveredReset)) < abs($1.resetDate.timeIntervalSince(hoveredReset)) }
    }
    private var domain: ClosedRange<Date> {
        let first = samples.first!.resetDate
        let last = samples.last!.resetDate
        let padding = max(1800, last.timeIntervalSince(first) * 0.06)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }
    private var axisDates: [Date] {
        guard let first = samples.first, let last = samples.last else { return [] }
        if samples.count == 1 { return [first.resetDate] }
        if samples.count < 5 { return [first.resetDate, last.resetDate] }
        return [first.resetDate, samples[samples.count / 2].resetDate, last.resetDate]
    }
    private var dateFormat: Date.FormatStyle {
        if let first = samples.first, let last = samples.last,
           last.resetDate.timeIntervalSince(first.resetDate) < 86400 {
            return .dateTime.hour().minute().locale(Locale(identifier: "en_US"))
        }
        return .dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US"))
    }

    var body: some View {
        if !samples.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    if let selected {
                        Text(selected.resetDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                        Spacer()
                        Text("\(Int(selected.remainingPercent.rounded()))% left at reset")
                            .foregroundStyle(.primary).fontWeight(.medium)
                    } else {
                        HStack(spacing: 4) {
                            Path { path in
                                path.move(to: .zero)
                                path.addLine(to: CGPoint(x: 12, y: 0))
                            }.stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(width: 12, height: 1)
                            Text("Period average")
                        }
                        Spacer()
                        Text(samples.count < windows.count ? "Latest \(samples.count) of \(windows.count) resets" : "Each bar is a reset")
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
                .monospacedDigit().frame(height: 14)

                GeometryReader { geometry in
                    let barWidth = max(4, min(22, (geometry.size.width - 32) / CGFloat(samples.count) * 0.6))
                    Chart {
                        ForEach(samples, id: \.resetsAt) { reading in
                            BarMark(x: .value("Reset", reading.resetDate),
                                    yStart: .value("Baseline", 0), yEnd: .value("Full quota", 100), width: .fixed(barWidth))
                                .foregroundStyle(Color.primary.opacity(0.045))
                                .cornerRadius(3)
                                .accessibilityHidden(true)
                            BarMark(x: .value("Reset", reading.resetDate),
                                    yStart: .value("Baseline", 0), yEnd: .value("Left near reset", reading.remainingPercent), width: .fixed(barWidth))
                                .foregroundStyle(Color.orange.opacity(selected == nil || selected?.resetsAt == reading.resetsAt ? 0.8 : 0.3))
                                .cornerRadius(3)
                                .accessibilityLabel(reading.resetDate.formatted(.dateTime.month().day().hour().minute()))
                                .accessibilityValue("\(Int(reading.remainingPercent.rounded())) percent left near reset")
                        }
                        RuleMark(y: .value("Period average", average))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        if let selected {
                            RuleMark(x: .value("Selected reset", selected.resetDate))
                                .foregroundStyle(Color.secondary.opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        }
                    }
                    .chartXScale(domain: domain)
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 50, 100]) { axis in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.secondary.opacity(0.18))
                            AxisValueLabel {
                                if let value = axis.as(Int.self) {
                                    Text("\(value)%").font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: axisDates) { axis in
                            if let date = axis.as(Date.self) {
                                AxisValueLabel(anchor: samples.count == 1 ? .top : date == samples.last?.resetDate ? .topTrailing : date == samples.first?.resetDate ? .topLeading : .top) {
                                    Text(date, format: dateFormat)
                                        .font(.caption2).foregroundStyle(.secondary).fixedSize()
                                }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { overlay in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        guard let frame = proxy.plotFrame else { hoveredReset = nil; return }
                                        let plot = overlay[frame]
                                        guard plot.contains(location) else { hoveredReset = nil; return }
                                        hoveredReset = proxy.value(atX: location.x - plot.minX, as: Date.self)
                                    case .ended: hoveredReset = nil
                                    }
                                }
                        }
                    }
                }.frame(height: 116)
            }
            .onChange(of: windows.map(\.resetsAt)) { _, _ in hoveredReset = nil }
        }
    }
}
