import SwiftUI
import BubbleTaxBarCore

struct BillingScheduleSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let provider: Provider
    @State private var date = Date()
    @State private var interval: BillingInterval = .monthly
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Renewal schedule").font(.headline)
            Text(provider.serviceName).font(.subheadline).foregroundStyle(.secondary)
            Picker("Billing cycle", selection: $interval) {
                ForEach(BillingInterval.allCases, id: \.self) { value in Text(value.title).tag(value) }
            }.pickerStyle(.segmented)
            DatePicker("Renewal date", selection: $date, displayedComponents: .date)
            Text("Next: " + BillingSchedule(provider: provider, accountKey: nil, anchor: date, interval: interval)
                .nextRenewal().formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.caption).monospacedDigit()
            Text("Set by you · quota resets stay provider-controlled.")
                .font(.caption).foregroundStyle(.secondary)
            if store.connection(provider)?.planContext == .organization {
                Text("Use your organization's renewal date if known.").font(.caption).foregroundStyle(.secondary)
            }
            if failed { Text(store.error ?? "Could not save the schedule.").font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Back") { dismiss() }.keyboardShortcut(.cancelAction)
                if store.billingSchedule(provider) != nil {
                    Button("Clear") {
                        if store.setBillingSchedule(provider, anchor: nil) { dismiss() } else { failed = true }
                    }.disabled(store.demoMode)
                }
                Spacer()
                Button("Save") {
                    if store.setBillingSchedule(provider, anchor: date, interval: interval) { dismiss() } else { failed = true }
                }.keyboardShortcut(.defaultAction).disabled(store.demoMode || !store.ready)
            }
        }.padding(20).frame(width: 350)
            .onAppear {
                if let schedule = store.billingSchedule(provider) {
                    // Keep the original anchor to preserve month-end anniversaries.
                    date = schedule.anchor; interval = schedule.interval
                }
            }
    }
}
