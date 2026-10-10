import SwiftUI
import BubbleTaxBarCore

private func usd(_ amount: Double) -> String {
    amount.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
}

struct CostComparison: View {
    let before: Double
    let after: Double
    var scale: Double? = nil
    private var maximum: Double { max(1, scale ?? max(before, after)) }
    var body: some View {
        VStack(spacing: 5) {
            row("Before", value: before, color: Color.secondary.opacity(0.5))
            row("After", value: after, color: Color.accentColor)
        }.accessibilityElement(children: .combine)
            .accessibilityLabel("Monthly list price")
            .accessibilityValue("Before \(usd(before)), after \(usd(after))")
    }
    private func row(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 35, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1))
                    Capsule().fill(color).frame(width: geometry.size.width * max(0, min(1, value / maximum)))
                }
            }.frame(height: 6)
            Text(usd(value)).font(.caption.monospacedDigit()).frame(width: 66, alignment: .trailing)
        }
    }
}

struct SavingsSummary: View {
    @EnvironmentObject var store: Store
    let open: () -> Void
    var body: some View {
        let reduction = SavingsLedger.monthlyReduction(store.changes)
        let priced = SavingsLedger.latestRecords(store.changes).contains { $0.monthlyReduction != nil }
        Button(action: open) {
            HStack {
                Image(systemName: "banknote")
                Text(priced ? "\(usd(reduction)) / mo less" : "\(store.changes.count) completed changes").fontWeight(.medium).monospacedDigit()
                Spacer()
                Text(priced ? "Estimated" : "Recorded").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.font(.caption).padding(9)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
            .help("Recorded changes at public monthly list prices. Not accumulated cash saved.")
    }
}

struct SavingsHistory: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let latest = SavingsLedger.latestRecords(store.changes)
        let priced = latest.contains { $0.monthlyReduction != nil }
        let pricedRecords = latest.filter { $0.monthlyReduction != nil }
        let baseline = pricedRecords.compactMap(\.baselineMonthlyUSD).reduce(0, +)
        let after = pricedRecords.compactMap(\.afterMonthlyUSD).reduce(0, +)
        let scale = max(max(1, baseline), store.changes.compactMap(\.beforeMonthlyUSD).max() ?? 1)
        let unpriced = latest.filter { $0.kind != .releasedSeat && $0.monthlyReduction == nil }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(priced || store.changes.isEmpty ? "\(usd(SavingsLedger.monthlyReduction(store.changes))) / month" : "Estimate unavailable")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text("Monthly reduction · list-price estimate").font(.caption).foregroundStyle(.secondary)
                        .help("Changes recorded by you. Public monthly list prices, not invoices or accumulated cash saved.")
                    if priced { CostComparison(before: baseline, after: after, scale: scale).padding(.top, 6) }
                    if unpriced > 0 {
                        Text("\(unpriced) unpriced change\(unpriced == 1 ? "" : "s") excluded")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if priced { RealWorldSavingsView(monthly: SavingsLedger.monthlyReduction(store.changes)) }
                if store.changes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No completed changes yet", systemImage: "checkmark.circle")
                        Text("Plan actions → Record completed change")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(.vertical, 16)
                } else {
                    ForEach(store.changes.sorted { $0.completedAt > $1.completedAt }) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: record.kind == .downgraded ? "arrow.down.right" : "checkmark.circle")
                                    .foregroundStyle(.secondary)
                                    .help(record.kind.title)
                                Text(record.provider.serviceName).font(.callout.weight(.medium))
                                Spacer()
                                Text(record.completedAt, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption).foregroundStyle(.secondary)
                                    .help(record.completedAt.formatted(.dateTime.year().month().day()))
                            }
                            Text("\(record.fromPlan) → \(record.toPlan)").font(.caption).foregroundStyle(.secondary)
                            if let before = record.beforeMonthlyUSD, let after = record.afterMonthlyUSD {
                                CostComparison(before: before, after: after, scale: scale)
                            } else {
                                Text(record.kind == .releasedSeat ? "Work seat · excluded from personal savings" : "Price unavailable · excluded from estimate")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text(record.kind.title).font(.caption2).foregroundStyle(.secondary)
                                    .help("Completed change recorded by you")
                                Spacer()
                                if SavingsLedger.latest(store.changes, provider: record.provider, accountKey: record.accountKey)?.id == record.id {
                                    Button("Undo record") { store.removeLatestChange(record) }
                                        .controlSize(.small).disabled(store.demoMode)
                                        .help("Remove this record. This does not restore a subscription with the provider.")
                                }
                            }
                        }
                        Divider()
                    }
                }
                Label("List prices · recorded changes", systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary)
                    .help(PlanPricing.caveat + " Monthly rate reduction, not accumulated cash saved.")
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: 500)
    }
}

struct RecordChangeSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let provider: Provider
    @State private var kind: SubscriptionChangeKind = .cancelled
    @State private var target = "Free"
    @State private var confirmed = false
    @State private var failed = false

    private var connection: ProviderConnection? { store.changeConnection(provider, kind: kind) }
    private var work: Bool { connection?.planContext == .organization }
    private var options: [String] {
        let before = store.latestChange(provider)?.afterMonthlyUSD ?? PlanPricing.lookup(provider: provider, label: connection?.planLabel)?.exact
        return PlanPricing.recordingOptions(provider: provider).filter { label in
            let price = label == "Free" ? 0 : PlanPricing.lookup(provider: provider, label: label)?.exact
            return price.map { value in before.map { value < $0 } ?? true } ?? false
        }
    }
    private var preview: SubscriptionChange? {
        connection.flatMap { SubscriptionChange.make(connection: $0, kind: work ? .releasedSeat : kind,
            targetPlan: kind == .downgraded ? target : nil, previous: store.latestChange(provider)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Record completed change").font(.headline)
            Text(provider.serviceName).font(.subheadline).foregroundStyle(.secondary)
            Text("From: " + (store.latestChange(provider)?.toPlan ?? connection?.planLabel ?? "Plan not reported"))
                .font(.caption).foregroundStyle(.secondary)
            if work {
                Label("Seat released", systemImage: "person.crop.circle.badge.minus")
                Text(RealWorldSavings.workMessage).font(.callout)
                Text("Work budget · not personal savings").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Completed action", selection: $kind) {
                    Text("Cancelled").tag(SubscriptionChangeKind.cancelled)
                    Text("Downgraded").tag(SubscriptionChangeKind.downgraded)
                }.pickerStyle(.segmented)
                if kind == .downgraded {
                    Picker("New plan", selection: $target) {
                        ForEach(options, id: \.self) { label in Text(label).tag(label) }
                    }
                    Text("Choose the plan you actually switched to.").font(.caption).foregroundStyle(.secondary)
                }
                if let reduction = preview?.monthlyReduction {
                    RealWorldSavingsView(monthly: reduction)
                } else {
                    Text(preview == nil ? "Choose a valid completed change." : "Price unavailable. The change can still be recorded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Label("Monthly list-price estimate", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Future monthly rate reduction, not cash already saved. " + PlanPricing.caveat)
            }
            Toggle("I completed this with the provider", isOn: $confirmed)
                .toggleStyle(.checkbox).font(.callout)
            Text("Local record only").font(.caption2).foregroundStyle(.secondary)
                .help("Recording here doesn't change your subscription with the provider.")
            if failed { Text(store.error ?? "Could not record this change. Check the reported plan.").font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Back") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save record") {
                    if store.recordChange(provider, kind: work ? .releasedSeat : kind, targetPlan: kind == .downgraded ? target : nil) {
                        dismiss()
                    } else { failed = true }
                }.keyboardShortcut(.defaultAction).disabled(!confirmed || preview == nil || store.demoMode)
            }
        }.padding(20).frame(width: 350)
            .onAppear {
                if let reported = store.connection(provider)?.planLabel, options.contains(reported) { target = reported }
                else if !options.contains(target), let first = options.first { target = first }
            }
    }
}
