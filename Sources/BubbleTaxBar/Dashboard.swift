import SwiftUI
import BubbleTaxBarCore
import ServiceManagement

struct Connections: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var login: LoginAtLaunch
    @AppStorage(NotchController.preference) private var notchEnabled = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("General").font(.headline)
                Toggle("Cancellation candidates first", isOn: Binding(
                    get: { store.reviewFirst }, set: { store.setReviewFirst($0) }))
                    .toggleStyle(.checkbox).disabled(store.demoMode)
                    .help("Show services with evidence supporting a plan review first. Your selected service stays open.")
                Toggle("Use MacBook notch", isOn: $notchEnabled)
                    .toggleStyle(.checkbox).disabled(store.demoMode)
                    .help("Click the quota beside the notch to expand. Displays without a notch use the menu bar.")
                Toggle("Open at Login", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                    .disabled(store.demoMode)
                if login.needsApproval {
                    Button("Approve in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
                        .disabled(store.demoMode)
                }
                if let error = login.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                Divider()
                Text("Connections").font(.headline)
                Text("Use existing signed-in sessions to read quota and plan metadata. No plan form.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Provider.supported) { provider in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(provider.serviceName, isOn: Binding(
                            get: { store.providers.contains(provider) },
                            set: { store.setEnabled(provider, enabled: $0) }))
                            .disabled(store.scanning)
                        let connection = store.connection(provider)
                        Text(connection?.status == "connected" ? "Connected · \(connection?.source ?? "server")" : "Sign in to the service, then refresh")
                            .font(.caption).foregroundStyle(.secondary)
                        if let plan = connection?.planLabel {
                            Text("Reported plan: \(plan)").font(.caption).foregroundStyle(.secondary)
                        }
                        if provider.supportsCLI {
                            let folder = store.logFolder(provider)
                            let defaultFolder = store.defaultLogFolder(provider).path
                            Text(folder.map { "Logs: \($0)" } ?? "Default: \(defaultFolder)")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                .help(folder ?? defaultFolder)
                            HStack {
                                Button(folder == nil ? "Connect default logs" : "Use default folder") {
                                    store.connectDefaultLogs(provider)
                                }.disabled(folder == defaultFolder)
                                Button("Choose folder…") { store.chooseFolder(provider) }
                                if folder != nil {
                                    Button("Disconnect logs") { store.disconnect(provider) }
                                }
                            }.controlSize(.small).disabled(store.scanning || store.configuringStatusline)
                        }
                        if provider == .claude {
                            Button(store.claudeStatuslineEnabled ? "Remove quota fallback" : "Enable Claude Code quota fallback") {
                                Task { await store.configureClaudeStatusline(store.claudeStatuslineEnabled ? "remove" : "install") }
                            }.controlSize(.small).disabled(store.scanning || store.configuringStatusline)
                            Text("Captures quota from Claude Code. Backs up settings and keeps your existing statusline. Updates when Claude Code runs.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if provider != Provider.supported.last { Divider() }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pi coding agent").font(.headline)
                    Text(store.data.piFolder.map { "Sessions: \($0)" } ?? "Default: \(store.defaultPiFolder.path)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Connect default sessions") { store.connectPi() }
                            .disabled(store.data.piFolder == store.defaultPiFolder.path)
                        Button("Choose folder…") { store.choosePiFolder() }
                        if store.data.piFolder != nil { Button("Disconnect") { store.disconnectPi() } }
                    }.controlSize(.small).disabled(store.demoMode || store.scanning)
                    PiActivity()
                    Text("Pi uses your provider subscriptions or API keys. Session tokens are local activity; remaining quota comes from the provider. Billing cannot be inferred from a model name.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Powered by CodexBar collectors. Refreshes every 5 minutes. Availability depends on service authentication and permissions. Workspace limits may be shared; a plan label doesn't prove who pays.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.frame(height: 490).onAppear { login.refresh() }
    }
}
