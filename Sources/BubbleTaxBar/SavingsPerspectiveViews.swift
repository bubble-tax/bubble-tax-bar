import SwiftUI
import BubbleTaxBarCore

struct RealWorldSavingsView: View {
    let monthly: Double
    @State private var period: SavingsPeriod = .month
    var body: some View {
        if monthly > 0, monthly.isFinite {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Budget period", selection: $period) {
                    ForEach(SavingsPeriod.allCases) { item in Text(item.title).tag(item) }
                }.pickerStyle(.segmented).labelsHidden()
                if let idea = RealWorldSavings.make(monthly: monthly, period: period) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: idea.symbol).font(.title3).frame(width: 24)
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("~" + idea.amount.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) + " / " + period.rawValue)
                                .font(.callout.weight(.semibold)).monospacedDigit()
                            Text(idea.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }.help("Illustrative budget ideas, not product price quotes. Monthly list-price reduction projected at 12 months / 52 weeks. Not accumulated cash saved.")
        }
    }
}

struct DowngradeComparisonSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let provider: Provider
    @State private var target = ""
    private var connection: ProviderConnection? { store.connection(provider) }
    private var current: Double? { PlanPricing.lookup(provider: provider, label: connection?.planLabel)?.exact }
    private var options: [DowngradeOption] { current.map { DowngradeOption.cheaper(provider: provider, currentPrice: $0) } ?? [] }
    private var selected: DowngradeOption? { options.first { $0.label == target } ?? options.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Less plan. More real life.").font(.headline)
            Text(provider.serviceName + " · " + (connection?.planLabel ?? "Plan unavailable"))
                .font(.caption).foregroundStyle(.secondary)
            if let current, let selected {
                Picker("Compare with", selection: $target) {
                    ForEach(options) { item in Text(item.label).tag(item.label) }
                }
                CostComparison(before: current, after: selected.monthlyPrice)
                Divider()
                RealWorldSavingsView(monthly: current - selected.monthlyPrice)
                Text("If this tier covers your work · list-price estimate")
                    .font(.caption2).foregroundStyle(.secondary).help(PlanPricing.caveat)
            } else {
                Label("Exact tier price unavailable", systemImage: "questionmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 350)
            .onAppear { if target.isEmpty { target = options.first?.label ?? "" } }
    }
}
