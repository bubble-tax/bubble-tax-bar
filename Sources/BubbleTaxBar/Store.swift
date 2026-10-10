import AppKit
import SwiftUI
import BubbleTaxBarCore

@MainActor
final class Store: ObservableObject {
    @Published var data = AppData()
    @Published var error: String?
    @Published var scanning = false
    @Published var ready = true
    @Published var claudeStatuslineEnabled = false
    @Published var configuringStatusline = false
    let demoMode = CommandLine.arguments.contains("--demo-data")
    private let location: URL
    private var timer: Timer?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        location = support.appendingPathComponent("BubbleTaxBar/state.json")
        // Renamed from SubRIP. Copy, never move, so the old record stays as a backup.
        let legacy = support.appendingPathComponent("SubRIP/state.json")
        if !demoMode, !FileManager.default.fileExists(atPath: location.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: legacy, to: location)
        }
        // Screenshot fixtures never read/write the user's state or run collectors.
        if demoMode {
            do {
                let args = CommandLine.arguments
                guard let index = args.firstIndex(of: "--demo-data"), index + 1 < args.count else {
                    throw CocoaError(.fileReadNoSuchFile)
                }
                data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: URL(fileURLWithPath: args[index + 1])))
            } catch { self.error = "Could not load demo data."; ready = false }
            return
        }
        do {
            if FileManager.default.fileExists(atPath: location.path) {
                data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: location))
                guard data.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            }
        } catch {
            self.error = "Could not read saved data. Original preserved: \(location.path)"
            ready = false
        }
        if ready {
            if let selected = data.enabledProviders {
                let migrated = Set(selected.map { $0 == .gemini ? Provider.antigravity : $0 })
                data.enabledProviders = Provider.supported.filter { migrated.contains($0) }
            }
            // Gemini CLI quotas and Antigravity quotas are separate budgets.
            // Migrate the choice, never relabel the old quota observations.
            data.snapshot?.connections?.removeAll { $0.provider == .windsurf || $0.provider == .gemini }
            data.snapshot?.quotaWindows?.removeAll { $0.provider == .windsurf || $0.provider == .gemini }
            data.unusedQuotaArchive = UnusedQuotaHistory.eligibleWindows(
                (data.unusedQuotaArchive ?? []) + (data.snapshot?.quotaWindows ?? []))
            rememberPaidPlans(data.snapshot?.connections ?? [])
            save()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.scan() }
        }
        let recentlyRefreshed = data.snapshot?.connections != nil &&
            (data.scannedAt.map { Date().timeIntervalSince($0) < 120 } ?? false)
        if (!providers.isEmpty || data.piFolder != nil) && !recentlyRefreshed {
            Task { await scan() }
        }
        Task { await configureClaudeStatusline("status") }
    }

    var providers: [Provider] { (data.enabledProviders ?? Provider.supported).filter { Provider.supported.contains($0) } }
    var fresh: Bool { data.scannedAt.map { (0..<900).contains(Date().timeIntervalSince($0)) } ?? false }
    var changes: [SubscriptionChange] { data.subscriptionChanges ?? [] }
    var reviewFirst: Bool { data.reviewFirst ?? true }
    var personaProviders: [Provider] {
        providers.filter { provider in
            guard let record = latestChange(provider) else { return true }
            let connection = connection(provider)
            if connection?.planContext == .free { return true }
            // Do not keep roasting the old tier while the provider still reports it.
            return record.kind == .downgraded &&
                PlanPricing.lookup(provider: provider, label: connection?.planLabel)?.exact == record.afterMonthlyUSD
        }
    }
    var pendingRecordedChanges: Bool { personaProviders.count < providers.count }
    var orderedProviders: [Provider] {
        reviewFirst ? ReviewPriority.ordered(providers, snapshot: data.snapshot, fresh: fresh, changes: changes) : providers
    }
    func setReviewFirst(_ enabled: Bool) { data.reviewFirst = enabled; save() }
    func latestChange(_ provider: Provider) -> SubscriptionChange? {
        SavingsLedger.latest(changes, provider: provider, accountKey: connection(provider)?.accountKey)
    }
    func changeConnection(_ provider: Provider, kind: SubscriptionChangeKind = .cancelled) -> ProviderConnection? {
        SavingsLedger.recordingConnection(connection(provider), remembered: data.recordingPlans ?? [], records: changes, kind: kind)
    }
    private func rememberPaidPlans(_ connections: [ProviderConnection]) {
        data.recordingPlans = SavingsLedger.rememberPlans(data.recordingPlans ?? [], connections: connections)
    }
    func billingSchedule(_ provider: Provider) -> BillingSchedule? {
        BillingSchedule.matching(data.billingSchedules ?? [], provider: provider, accountKey: connection(provider)?.accountKey)
    }
    func setBillingSchedule(_ provider: Provider, anchor: Date?, interval: BillingInterval = .monthly) -> Bool {
        guard ready, !demoMode, anchor?.timeIntervalSince1970.isFinite ?? true else { return false }
        let account = connection(provider)?.accountKey
        let old = data.billingSchedules
        var schedules = old ?? []
        schedules.removeAll { $0.provider == provider && $0.accountKey == account }
        if let anchor { schedules.append(BillingSchedule(provider: provider, accountKey: account, anchor: anchor, interval: interval)) }
        data.billingSchedules = schedules
        guard save() else { data.billingSchedules = old; return false }
        return true
    }
    func recordChange(_ provider: Provider, kind: SubscriptionChangeKind, targetPlan: String?) -> Bool {
        guard ready, !demoMode, let connection = changeConnection(provider, kind: kind),
              let record = SubscriptionChange.make(connection: connection, kind: kind, targetPlan: targetPlan,
                previous: latestChange(provider)) else { return false }
        let old = data.subscriptionChanges
        data.subscriptionChanges = changes + [record]
        guard save() else { data.subscriptionChanges = old; return false }
        return true
    }
    func removeLatestChange(_ record: SubscriptionChange) {
        guard ready, !demoMode,
              SavingsLedger.latest(changes, provider: record.provider, accountKey: record.accountKey)?.id == record.id else { return }
        let old = data.subscriptionChanges
        data.subscriptionChanges = changes.filter { $0.id != record.id }
        if !save() { data.subscriptionChanges = old }
    }

    func configureClaudeStatusline(_ action: String) async {
        guard !demoMode, ready, !configuringStatusline else { return }
        configuringStatusline = true
        defer { configuringStatusline = false }
        do {
            let enabled = try await Task.detached(priority: .utility) {
                guard let helper = CollectorProcess.localHelper() else {
                    if action == "status" { return false }
                    throw NSError(domain: "BubbleTaxBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "The bundled local collector is missing. Reinstall Bubble Tax."])
                }
                let output = try CollectorProcess.run(helper, arguments: ["statusline", action], timeout: 15)
                return (try JSONSerialization.jsonObject(with: output) as? [String: Bool])?["enabled"] ?? false
            }.value
            claudeStatuslineEnabled = enabled
            if action != "status" { error = nil }
        } catch { self.error = error.localizedDescription }
    }
    func connection(_ provider: Provider) -> ProviderConnection? {
        data.snapshot?.connections?.first { $0.provider == provider }
    }
    func setEnabled(_ provider: Provider, enabled: Bool) {
        guard !scanning, Provider.supported.contains(provider) else { return }
        var selected = providers
        if enabled && !selected.contains(provider) { selected.append(provider) }
        if !enabled { selected.removeAll { $0 == provider } }
        data.enabledProviders = Provider.supported.filter { selected.contains($0) }
        save()
        if enabled { Task { await scan() } }
    }

    var active: [Subscription] { data.subscriptions.filter { $0.cancelledAt == nil } }
    var buried: [Subscription] { data.subscriptions.filter { $0.cancelledAt != nil } }
    func assessment(_ subscription: Subscription) -> Assessment {
        let fresh = data.scannedAt.map { Date().timeIntervalSince($0) < 900 } ?? false
        return Assessor.assess(subscription, snapshot: fresh ? data.snapshot : nil)
    }
    func money(_ amount: Double, currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }
    func totals(_ subscriptions: [Subscription], multiplier: Double = 1) -> String {
        let groups = Dictionary(grouping: subscriptions, by: \.currency)
        if groups.isEmpty { return "—" }
        return groups.keys.sorted().map { currency in
            money(groups[currency]!.reduce(0) { $0 + $1.monthlyPrice } * multiplier, currency: currency)
        }.joined(separator: " + ")
    }
    @discardableResult
    func save() -> Bool {
        guard ready, !demoMode else { return false }
        do {
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: location, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
            return true
        } catch { self.error = "Could not save: \(error.localizedDescription)"; return false }
    }
    func upsert(_ subscription: Subscription) {
        guard ready else { return }
        if subscription.includesCLI && active.contains(where: { $0.id != subscription.id && $0.provider == subscription.provider && $0.includesCLI }) {
            error = "CLI logs can link to only one active subscription per service."; return
        }
        if let index = data.subscriptions.firstIndex(where: { $0.id == subscription.id }) {
            var updated = subscription
            let old = data.subscriptions[index]
            if old.provider != subscription.provider || old.includesCLI != subscription.includesCLI {
                updated.observedSince = Date(); updated.coverageConfirmed = false
                updated.coverageConfirmedAt = nil
                updated.manualDays = []; updated.valuableThisCycle = false; updated.valueMarkedAt = nil
            }
            data.subscriptions[index] = updated
        } else { data.subscriptions.append(subscription) }
        save()
    }
    func used(_ subscription: Subscription, on day: Date) {
        var item = subscription
        let day = Calendar.current.startOfDay(for: day)
        if !item.manualDays.contains(where: { Calendar.current.isDate($0, inSameDayAs: day) }) { item.manualDays.append(day) }
        upsert(item)
    }
    func markValue(_ subscription: Subscription) {
        var item = subscription; item.valuableThisCycle = true; item.valueMarkedAt = Date(); upsert(item)
    }
    func cancel(_ subscription: Subscription) {
        var item = subscription; item.cancelledAt = Date(); upsert(item)
    }
    func restore(_ subscription: Subscription) {
        var item = subscription; item.cancelledAt = nil; item.observedSince = Date()
        item.coverageConfirmed = false; item.coverageConfirmedAt = nil
        item.valuableThisCycle = false; item.valueMarkedAt = nil; upsert(item)
    }
    func logFolder(_ provider: Provider) -> String? {
        switch provider {
        case .claude: return data.claudeFolder
        case .openai: return data.codexFolder
        default: return nil
        }
    }
    func defaultLogFolder(_ provider: Provider) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        let key = provider == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
        let configured = environment[key].flatMap { $0.isEmpty ? nil : $0 }
        let root = configured.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ??
            home.appendingPathComponent(provider == .claude ? ".claude" : ".codex")
        return root.appendingPathComponent(provider == .claude ? "projects" : "sessions")
    }
    func connectDefaultLogs(_ provider: Provider) {
        guard ready, !scanning, provider.supportsCLI else { return }
        let folder = defaultLogFolder(provider)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &directory), directory.boolValue else {
            error = "Default log folder not found: \(folder.path). Choose a folder instead."
            return
        }
        connectLogs(provider, folder: folder)
    }
    private func connectLogs(_ provider: Provider, folder: URL) {
        if provider == .claude { data.claudeFolder = folder.path } else { data.codexFolder = folder.path }
        clearLocalRecords(provider)
        error = nil; save()
        Task { await scan() }
    }
    private func clearLocalRecords(_ provider: Provider) {
        data.snapshot?.days.removeAll { $0.provider == provider }
        data.snapshot?.sources.removeAll { $0.provider == provider }
    }
    func chooseFolder(_ provider: Provider) {
        guard ready, !scanning, provider.supportsCLI else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.message = provider == .claude ? "Choose your Claude Code projects folder. Chat text is never saved or sent." : "Choose your Codex sessions folder. Chat text is never saved or sent."
        panel.directoryURL = logFolder(provider).map { URL(fileURLWithPath: $0) } ?? defaultLogFolder(provider)
        if panel.runModal() == .OK, let url = panel.url {
            connectLogs(provider, folder: url)
        }
    }
    func disconnect(_ provider: Provider) {
        guard ready, !scanning, provider.supportsCLI else { return }
        if provider == .claude { data.claudeFolder = nil } else { data.codexFolder = nil }
        clearLocalRecords(provider)
        error = nil; save()
    }
    var defaultPiFolder: URL {
        let env = ProcessInfo.processInfo.environment
        if let folder = env["PI_CODING_AGENT_SESSION_DIR"], !folder.isEmpty {
            return URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
        }
        let root = env["PI_CODING_AGENT_DIR"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent")
        return root.appendingPathComponent("sessions")
    }
    func connectPi(folder: URL? = nil) {
        guard ready, !demoMode, !scanning else { return }
        let folder = folder ?? defaultPiFolder
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &directory), directory.boolValue else {
            error = "Pi sessions folder not found: \(folder.path). Choose a folder instead."; return
        }
        data.piFolder = folder.path; data.snapshot?.piUsage = nil
        error = nil; save()
        Task { await scan() }
    }
    func choosePiFolder() {
        guard ready, !demoMode, !scanning else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.message = "Choose Pi's sessions folder. Only usage metadata is saved."
        panel.directoryURL = data.piFolder.map { URL(fileURLWithPath: $0) } ?? defaultPiFolder
        if panel.runModal() == .OK, let url = panel.url { connectPi(folder: url) }
    }
    func disconnectPi() {
        guard ready, !demoMode, !scanning else { return }
        data.piFolder = nil; data.snapshot?.piUsage = nil; error = nil; save()
    }
    func scan() async {
        guard !demoMode, ready, !scanning, !providers.isEmpty || data.piFolder != nil else { return }
        scanning = true
        defer { scanning = false }
        let claude = providers.contains(.claude) ? data.claudeFolder : nil
        let codex = providers.contains(.openai) ? data.codexFolder : nil
        let pi = data.piFolder
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexBarCLI").path
        let developerHelper = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("vendor/codexbar/CodexBarCLI").path
        let binary = [helper, developerHelper].first { FileManager.default.isExecutableFile(atPath: $0) }
        let live = if let binary {
            await NativeUsageCollector.collect(binary: binary, providers: providers)
        } else {
            ([ProviderConnection](), [QuotaWindow]())
        }
        let local = await Task.detached(priority: .utility) { () -> (CollectorSnapshot, String?) in
            var snapshot = try! JSONDecoder().decode(CollectorSnapshot.self, from: Data("{\"days\":[],\"sources\":[],\"quotaWindows\":[]}".utf8))
            guard claude != nil || codex != nil || pi != nil else { return (snapshot, nil) }
            guard let helper = CollectorProcess.localHelper() else {
                return (snapshot, "The bundled local collector is missing. Reinstall Bubble Tax.")
            }
            var arguments = ["collect", "--timezone", TimeZone.current.identifier]
            if let claude { arguments += ["--claude-folder", claude] }
            if let codex { arguments += ["--codex-folder", codex] }
            if let pi { arguments += ["--pi-folder", pi] }
            do {
                let bytes = try CollectorProcess.run(helper, arguments: arguments, timeout: 30)
                snapshot = try JSONDecoder().decode(CollectorSnapshot.self, from: bytes)
                return (snapshot, nil)
            } catch {
                return (snapshot, "Local log collection failed; check the selected folders and their access permissions.")
            }
        }.value
        var output = local.0
        output.connections = live.0
        let connected = Set(live.0.filter { $0.status == "connected" }.map(\.provider))
        output.quotaWindows = (output.quotaWindows ?? []).filter { !connected.contains($0.provider) } + live.1
        // Archive before removing old-account/plan observations from live data.
        // Retain observed expired quota beyond the rolling 30-day snapshot.
        data.unusedQuotaArchive = UnusedQuotaHistory.eligibleWindows(
            (data.unusedQuotaArchive ?? []) + (data.snapshot?.quotaWindows ?? []) + (output.quotaWindows ?? []))
        var snapshot = output
        var previous = data.snapshot?.quotaWindows ?? []
        for connection in output.connections ?? [] where connection.status == "connected" {
            let old = data.snapshot?.connections?.first { $0.provider == connection.provider }
            if connection.accountKey == nil || old?.accountKey != connection.accountKey || old?.planLabel != connection.planLabel {
                previous.removeAll { $0.provider == connection.provider }
            }
            // Anonymous transcript history is separate from a verified live account.
            previous.removeAll { $0.provider == connection.provider && $0.accountKey != connection.accountKey }
        }
        let history = previous + (output.quotaWindows ?? [])
        snapshot.quotaWindows = QuotaUsage.compact(history.filter {
            $0.resetsAt >= Date().timeIntervalSince1970 - 30 * 86400
        })
        rememberPaidPlans(snapshot.connections ?? [])
        data.snapshot = snapshot; data.scannedAt = Date(); error = local.1 ?? (binary == nil ? "The bundled provider collector is missing. Reinstall Bubble Tax." : nil); save()
    }
}
