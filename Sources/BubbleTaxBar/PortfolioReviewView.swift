import SwiftUI
import BubbleTaxBarCore

struct PortfolioReviewView: View {
    @EnvironmentObject var store: Store
    let workAccount: Bool
    @State private var compare: Provider?
    var body: some View {
        let rows = PortfolioReview.rows(data: store.data, workAccount: workAccount)
        VStack(alignment: .leading, spacing: 14) {
            Text("A plan for every real need.").font(.title3.weight(.semibold))
            let prices = rows.compactMap(\.monthlyListPrice)
            if !workAccount, !prices.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(prices.reduce(0, +), format: .currency(code: "USD").locale(Locale(identifier: "en_US"))).font(.title.weight(.semibold)).monospacedDigit()
                    Text("/ mo · known list prices").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(rows) { row in
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(row.provider == .openai ? "Codex" : row.provider.serviceName).font(.headline)
                            Spacer()
                            Text(row.plan).font(.caption).foregroundStyle(.secondary)
                        }
                        Label(title(row.action), systemImage: symbol(row.action)).font(.callout.weight(.medium))
                        Text(row.reason).font(.caption).foregroundStyle(.secondary)
                        if let average = row.averageUnused {
                            HStack {
                                Text("\(Int(average.rounded()))% average left at reset")
                                Spacer()
                                Text("\(row.eligibleResets) resets")
                            }.font(.caption2).foregroundStyle(.secondary)
                            ProgressView(value: average, total: 100).tint(.secondary)
                        }
                        if row.action == .compare, row.monthlyListPrice != nil {
                            Button("Compare tiers…") { compare = row.provider }.controlSize(.small)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if rows.isEmpty { Text("No confirmed plans in this budget. Connect usage in Settings.").font(.caption) }
            Text(workAccount ? "Shared-seat capacity isn't personal savings. Review decisions with the workspace owner." : "Capacity review, not a quality score. Check model access, features and your actual tasks before changing plans. Prices aren't invoices.")
                .font(.caption2).foregroundStyle(.secondary)
        }.sheet(item: $compare) { provider in DowngradeComparisonSheet(provider: provider).environmentObject(store) }
    }
    private func title(_ action: PortfolioReview.Action) -> String {
        switch action {
        case .protect: return "Protect planned work"
        case .keep: return "Keep headroom"
        case .compare: return "Compare a smaller tier"
        case .observe: return "More evidence needed"
        case .seat: return "Review shared seat"
        case .free: return "Free capacity"
        }
    }
    private func symbol(_ action: PortfolioReview.Action) -> String {
        switch action {
        case .protect: return "calendar.badge.clock"
        case .keep: return "checkmark.circle"
        case .compare: return "arrow.down.circle"
        case .observe: return "clock"
        case .seat: return "building.2"
        case .free: return "leaf"
        }
    }
}
