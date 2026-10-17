import SwiftUI
import BubbleTaxBarCore

struct ReservationSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let workAccount: Bool
    @State private var provider: Provider = .claude
    @State private var title = ""
    @State private var deadline = Date().addingTimeInterval(86400)
    @State private var percent = 10.0
    @State private var error: String?
    private var options: [AllocationOption] { Allocation.options(data: store.data, workAccount: workAccount, respectEligibility: false) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set aside weekly quota").font(.title3.weight(.semibold))
            Picker("Service", selection: $provider) { ForEach(options) { Text($0.title).tag($0.provider) } }
            TextField("Work to protect", text: $title)
            DatePicker("Needed by", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
            Stepper("\(Int(percent))% of this weekly quota", value: $percent, in: 1...100, step: 1)
            if let option = options.first(where: { $0.provider == provider }) {
                Text("\(Int(option.available))% unallocated · resets \(option.weekly.resetDate.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US"))))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("A planning target, not a provider-side lock.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Set aside") { save() }.keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || options.isEmpty || store.demoMode)
            }
        }.padding(22).frame(width: 390)
            .onAppear { if !options.contains(where: { $0.provider == provider }), let first = options.first { provider = first.provider } }
    }
    private func save() {
        guard let option = options.first(where: { $0.provider == provider }), let account = option.connection.accountKey else { return }
        let record = QuotaReservation(provider: provider, accountKey: account, planLabel: option.connection.planLabel,
            limitID: option.weekly.limitID, resetsAt: option.weekly.resetsAt,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), deadline: deadline, percent: percent)
        error = store.reserveQuota(record)
        if error == nil { dismiss() }
    }
}
