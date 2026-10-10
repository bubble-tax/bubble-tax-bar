import SwiftUI
import Charts
import BubbleTaxBarCore

struct QuotaBalanceBar: View {
    let remaining: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.14))
                Capsule().fill(Color.accentColor)
                    .frame(width: geometry.size.width * max(0, min(1, remaining / 100)))
            }
        }.frame(height: 4)
            .accessibilityLabel("Quota left")
            .accessibilityValue("\(Int(remaining.rounded())) percent")
    }
}

private func percent(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US"))) + "%"
}

struct QuotaOverviewRow: View {
    let quota: QuotaUsage
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(quota.title).font(.caption.weight(.medium))
                Spacer()
                if let current = quota.current {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        let seconds = max(0, current.resetsAt - timeline.date.timeIntervalSince1970)
                        Label(seconds > 0 ? quotaDuration(seconds) : "Refresh", systemImage: "clock")
                            .font(.caption2).foregroundStyle(.secondary)
                            .help("Resets " + current.resetDate.formatted(.dateTime.month().day().hour().minute()))
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(quota.current.map { percent($0.remainingPercent) } ?? "—")
                            .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                        Text("left").font(.caption).foregroundStyle(.secondary)
                    }
                    if let current = quota.current { QuotaBalanceBar(remaining: current.remainingPercent) }
                    else {
                        Rectangle().fill(Color.secondary.opacity(0.12)).frame(height: 4)
                            .help("No fresh reading. Refresh to check this limit.")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(quota.averageUnused.map { "~" + percent($0) } ?? "—")
                            .font(.caption.weight(.semibold)).monospacedDigit()
                        Text("unused*").font(.caption2).foregroundStyle(.secondary)
                    }
                    QuotaHistoryMini(readings: Array(quota.eligibleExpired.suffix(8)))
                }.frame(width: 114)
                    .help("Expired windows: average left near reset. \(quota.eligibleExpired.count) eligible windows in the last 30 days.")
            }
        }.padding(.vertical, 3)
            .accessibilityElement(children: .contain)
            .help("Current Left and historical unused are separate readings. Weekly and shorter budgets are never added together.")
    }
}

struct QuotaHistoryMini: View {
    let readings: [QuotaWindow]
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            if readings.isEmpty {
                Text("No history").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(readings, id: \.resetsAt) { reading in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: reading.remainingPercent == 0 ? 0 : max(1, 18 * reading.remainingPercent / 100))
                        .help("\(reading.resetDate.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "en_US")))) · \(percent(reading.remainingPercent)) left near reset")
                }
            }
        }.frame(height: 18, alignment: .bottom)
            .accessibilityLabel("Expired-window history")
            .accessibilityValue(readings.map { percent($0.remainingPercent) }.joined(separator: ", "))
    }
}

struct QuotaRing: View {
    let value: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 5)
            Circle().trim(from: 0, to: max(0, min(1, value / 100)))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }.frame(width: 34, height: 34).padding(3)
            .accessibilityHidden(true)
    }
}

private func quotaDuration(_ seconds: Double) -> String {
    let minutes = max(1, Int(ceil(seconds / 60)))
    if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
    if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
    return "\(minutes)m"
}

struct QuotaReceipt: View {
    let quota: QuotaUsage
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let current = quota.current {
                    HStack(alignment: .firstTextBaseline) {
                        Text(percent(current.remainingPercent)).font(.title2.weight(.semibold)).monospacedDigit()
                        Text("left").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(percent(current.usedPercent)) used").foregroundStyle(.secondary)
                    }
                    QuotaBalanceBar(remaining: current.remainingPercent)
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        let seconds = max(0, current.resetsAt - timeline.date.timeIntervalSince1970)
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(seconds > 0 ? "Resets in \(quotaDuration(seconds))" : "Reset reached · refresh")
                            Spacer()
                            Text(current.resetDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                        }.foregroundStyle(.secondary)
                    }
                    Text("Checked \(current.observedDate.formatted(Date.FormatStyle().hour().minute().locale(Locale(identifier: "en_US"))))")
                        .foregroundStyle(.secondary)
                } else {
                    Label("No fresh quota reading", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
                if !quota.eligibleExpired.isEmpty {
                    Divider()
                    HStack {
                        Text("Expired unused").fontWeight(.medium)
                        Spacer()
                        if let average = quota.averageUnused {
                            Text("\(percent(average)) avg.").fontWeight(.semibold).monospacedDigit()
                        }
                    }
                    let samples = Array(quota.eligibleExpired.suffix(14))
                    Chart {
                        ForEach(samples, id: \.resetsAt) { reading in
                            BarMark(x: .value("Reset", reading.resetDate),
                                    y: .value("Left near reset", reading.remainingPercent))
                                .foregroundStyle(Color.orange)
                                .accessibilityLabel(reading.resetDate.formatted(.dateTime.month().day().hour().minute()))
                                .accessibilityValue("\(percent(reading.remainingPercent)) left near reset")
                        }
                        if let average = quota.averageUnused {
                            RuleMark(y: .value("30-day average", average))
                                .foregroundStyle(Color.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis { AxisMarks(values: [0, 50, 100]) { axis in
                        AxisGridLine()
                        AxisValueLabel { if let value = axis.as(Int.self) { Text("\(value)%") } }
                    } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                    .frame(height: 90)
                    HStack {
                        Text("\(quota.eligibleExpired.count) windows")
                        Spacer()
                        Text("┄ 30d average")
                    }.foregroundStyle(.secondary)
                        .help("Last \(samples.count) eligible windows shown. Dashed line: 30-day average left near reset.")
                } else {
                    Label("No history", systemImage: "chart.bar.xaxis")
                        .foregroundStyle(.secondary)
                }
                if quota.expired.count > quota.eligibleExpired.count {
                    Label("\(quota.expired.count - quota.eligibleExpired.count) excluded", systemImage: "slash.circle")
                        .foregroundStyle(.secondary).help("Windows excluded: stale, unidentified, or interrupted.")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(quota.title).font(.caption.weight(.semibold))
        }.font(.caption)
    }

}

struct LocalActivityStrip: View {
    let provider: Provider
    let days: [UsageDay]
    let activeDays: Int
    let tokens: Int
    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter: DateFormatter = {
            let value = DateFormatter()
            value.calendar = calendar; value.locale = Locale(identifier: "en_US_POSIX")
            value.timeZone = calendar.timeZone; value.dateFormat = "yyyy-MM-dd"
            return value
        }()
        let active = Set(days.filter { $0.provider == provider && $0.requests > 0 }.map(\.day))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Local activity", systemImage: "terminal").fontWeight(.medium)
                Spacer()
                Text("\(activeDays) / 30 days").foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                ForEach(0..<30, id: \.self) { offset in
                    let date = calendar.date(byAdding: .day, value: offset - 29, to: today)!
                    let recorded = active.contains(formatter.string(from: date))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(recorded ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(height: 15)
                        .help("\(formatter.string(from: date)): \(recorded ? "local activity recorded" : "no local record")")
                        .accessibilityLabel("\(formatter.string(from: date)), \(recorded ? "local activity recorded" : "no local record")")
                }
            }
            HStack {
                Text("29 days ago")
                Spacer()
                Text("Today")
            }.foregroundStyle(.secondary)
            HStack {
                Text("\(tokens.formatted(.number.notation(.compactName).locale(Locale(identifier: "en_US")))) tokens · local only")
                Spacer()
                Label("No record", systemImage: "square.fill")
            }.foregroundStyle(.secondary)
                .help("Gray means no local record, not no usage. Other devices and web usage may be missing.")
        }.font(.caption).padding(.vertical, 4)
    }
}
