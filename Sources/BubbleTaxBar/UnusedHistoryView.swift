import SwiftUI
import Charts
import BubbleTaxBarCore

struct UnusedHistoryView: View {
    @EnvironmentObject var store: Store
    @State private var last30Days = false

    var body: some View {
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
                    Text("\(groups.reduce(0) { $0 + $1.windows.count }) recorded resets")
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
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("~\(Int(group.averageUnused.rounded()))%")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text("avg. unused").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(group.windows.count) resets").font(.caption).foregroundStyle(.secondary)
                }
                Text("≈ \(group.fullWindowEquivalent.formatted(.number.precision(.fractionLength(1)))) full windows left")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Sum of the remaining fractions for this exact account and limit. Not a token count or a cash amount; quota capacity may change between resets.")
                let samples = Array(group.windows.suffix(30))
                Chart(samples, id: \.resetsAt) { reading in
                    BarMark(x: .value("Reset", reading.resetDate), y: .value("Unused", reading.remainingPercent))
                        .foregroundStyle(Color.orange.opacity(0.8))
                }.chartYScale(domain: 0...100)
                    .chartYAxis { AxisMarks(values: [0, 50, 100]) { axis in
                        AxisGridLine()
                        AxisValueLabel { if let value = axis.as(Int.self) { Text("\(value)%") } }
                    } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                    .frame(height: 100)
                    .help("Last \(samples.count) recorded resets shown")
                DisclosureGroup("Reset receipts") {
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
                Text(group.title + (previousAccount ? " · Previous account" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
