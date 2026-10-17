import SwiftUI
import BubbleTaxBarCore

struct RoutingPreferencesView: View {
    @EnvironmentObject var store: Store
    @State private var work: WorkKind = .coding
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task routing").font(.headline)
            Picker("Work type", selection: $work) { ForEach(WorkKind.allCases) { Text($0.rawValue).tag($0) } }
            Text("Choose services you trust for this work. Suggestions use their current quota, not an assumed quality ranking.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach([Provider.openai, .claude]) { provider in
                Toggle(provider == .openai ? "Codex" : "Claude", isOn: Binding(get: {
                    (store.data.allocationPreferences ?? AllocationPreferences()).providers(for: work).contains(provider)
                }, set: { enabled in
                    var preferences = store.data.allocationPreferences ?? AllocationPreferences()
                    var selected = preferences.providers(for: work); selected.removeAll { $0 == provider }
                    if enabled { selected.append(provider) }
                    preferences.eligible[work.rawValue] = selected; store.setAllocationPreferences(preferences)
                })).toggleStyle(.checkbox).disabled(store.demoMode)
            }
        }
    }
}
