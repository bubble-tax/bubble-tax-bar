import SwiftUI
import BubbleTaxBarCore

struct AllocationSummary: View {
    @EnvironmentObject var store: Store
    let open: () -> Void
    var body: some View {
        let next = Allocation.options(data: store.data, work: store.data.allocationPreferences?.recentWork ?? .coding).first(where: \.ready)
        Button(action: open) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.map { "Suggested next · " + $0.title } ?? "Plan your AI work").font(.caption.weight(.semibold))
                    Text("Keep headroom for the work that matters.").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

enum AllocationPage: String, CaseIterable, Identifiable {
    case next = "Use next", reserve = "Reserve", forecast = "Forecast", patterns = "Patterns", plans = "Plans"
    var id: String { rawValue }
}

struct AllocationView: View {
    var selectProvider: ((Provider) -> Void)?
    @EnvironmentObject var store: Store
    @State private var page: AllocationPage = CommandLine.arguments.contains("plans") ? .plans : CommandLine.arguments.contains("patterns") ? .patterns : CommandLine.arguments.contains("forecast") ? .forecast : CommandLine.arguments.contains("reserve") ? .reserve : .next
    @State private var addingReservation = false
    @State private var work: WorkKind = .coding
    @State private var workAccount = false
    private var options: [AllocationOption] { Allocation.options(data: store.data, work: work, workAccount: workAccount) }
    private var budgetOptions: [AllocationOption] { Allocation.options(data: store.data, workAccount: workAccount, respectEligibility: false) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if page != .patterns {
                    Picker("Budget", selection: $workAccount) {
                        Text("Personal").tag(false); Text("Work").tag(true)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                Picker("Section", selection: $page) { ForEach(AllocationPage.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                switch page {
                case .next: recommendation
                case .reserve: reservations
                case .forecast: AllocationForecastView(options: budgetOptions)
                case .patterns: UsagePatternsView()
                case .plans: PortfolioReviewView(workAccount: workAccount)
                }
            }.padding(16)
        }.frame(height: 500)
            .onAppear { work = store.data.allocationPreferences?.recentWork ?? .coding }
            .onChange(of: work) { value in
                var preferences = store.data.allocationPreferences ?? AllocationPreferences()
                guard preferences.recentWork != value else { return }
                preferences.recentWork = value; store.setAllocationPreferences(preferences)
            }
            .sheet(isPresented: $addingReservation) { ReservationSheet(workAccount: workAccount).environmentObject(store) }
    }
    private var reservations: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Save room for real work.").font(.title3.weight(.semibold))
                Spacer()
                Button("Set aside…") { addingReservation = true }.disabled(store.demoMode || budgetOptions.isEmpty)
            }
            ForEach(budgetOptions) { option in
                let records = (store.data.quotaReservations ?? []).filter { $0.matches(option.weekly, plan: option.connection.planLabel, now: Date()) }
                GroupBox {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Text(option.title).font(.headline); Spacer(); Text("\(Int(option.weekly.remainingPercent))% weekly left").font(.caption) }
                        GeometryReader { proxy in
                            HStack(spacing: 0) {
                                Rectangle().fill(.primary.opacity(0.08)).frame(width: proxy.size.width * option.weekly.usedPercent / 100)
                                Rectangle().fill(.primary.opacity(0.8)).frame(width: proxy.size.width * min(option.protected, option.weekly.remainingPercent) / 100)
                                Rectangle().fill(.primary.opacity(0.3))
                            }.clipShape(Capsule())
                        }.frame(height: 8)
                        Text("\(Int(option.protected))% set aside · \(Int(option.available))% unallocated").font(.caption).monospacedDigit()
                        if option.protected > option.weekly.remainingPercent {
                            Label("Reserved target is at risk", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                        ForEach(records) { record in
                            Divider()
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.title).font(.callout.weight(.medium))
                                    Text("\(Int(record.percent))% · \(record.deadline.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US"))))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Done") { store.finishReservation(record.id) }.disabled(store.demoMode)
                                Menu { Button("Remove reservation") { store.finishReservation(record.id, remove: true) } } label: { Image(systemName: "ellipsis") }.disabled(store.demoMode)
                            }.controlSize(.small)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if budgetOptions.isEmpty { Text("A fresh overall weekly quota is needed. Check the selected Personal / Work budget.").font(.caption) }
            Text("Local planning targets. Reservations don't lock provider quota. Marking work done releases its target; only provider readings change actual usage.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var recommendation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Task", selection: $work) { ForEach(WorkKind.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            if let next = options.first(where: \.ready) {
                Text("Use \(next.title) next.").font(.title2.weight(.semibold))
                Text("Weekly headroom for your \(work.rawValue.lowercased()) queue.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("View \(next.title) quota") { selectProvider?(next.provider) }.controlSize(.small)
            } else {
                Text("Check availability first.").font(.title2.weight(.semibold))
                Text(options.isEmpty ? ((store.data.allocationPreferences ?? AllocationPreferences()).providers(for: work).isEmpty ? "Choose a suitable service in Settings for this work type." : "Connect fresh overall weekly and session meters for Claude or Codex.") : "Current session limits or protected budgets leave no ready option.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(options) { option in
                GroupBox {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(option.title).font(.headline)
                            Spacer()
                            Text("\(Int(option.weekly.remainingPercent.rounded()))% weekly left").font(.caption).monospacedDigit()
                        }
                        ProgressView(value: option.weekly.remainingPercent, total: 100).tint(.primary)
                        HStack {
                            Text(option.session.map { "\(Int($0.remainingPercent.rounded()))% session left" } ?? "Session unknown")
                            Spacer()
                            Text("Resets \(option.weekly.resetDate, style: .relative)")
                        }.font(.caption2).foregroundStyle(.secondary)
                        if option.protected > 0 { Text("\(Int(option.protected))% set aside · \(Int(option.available))% unallocated").font(.caption2) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Recommendations use available quota, not equivalent work capacity or model quality. Choose suitable services in Settings. Work budgets stay separate.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
