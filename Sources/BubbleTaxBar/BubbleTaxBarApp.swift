import SwiftUI
import AppKit
import BubbleTaxBarCore
import Combine
import QuartzCore

@main
struct BubbleTaxBarApp: App {
    @NSApplicationDelegateAdaptor(MenuBarDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class MenuBarDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var store: Store?
    private let login = LoginAtLaunch()
    private var subscriptions: Set<AnyCancellable> = []
    private var statusTimer: Timer?
    private var statusProvider: Provider?
    private var flipGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Local QA overrides; ordinary launches follow the system appearance.
        if CommandLine.arguments.contains("--appearance-light") { NSApp.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--appearance-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        let store = Store()
        self.store = store
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.title = "†"
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.toolTip = "Bubble Tax — review unused AI subscriptions"
        item.button?.setAccessibilityLabel("Bubble Tax")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        let panel = MenuPanel().environmentObject(store).environmentObject(login)
            .environment(\.locale, Locale(identifier: "en_US"))
            .preferredColorScheme(CommandLine.arguments.contains("--appearance-light") ? .light :
                CommandLine.arguments.contains("--appearance-dark") ? .dark : nil)
        let controller = NSViewController()
        controller.view = FirstClickHostingView(rootView: panel)
        popover.contentViewController = controller
        if CommandLine.arguments.contains("--show-popover") { togglePopover() }
        store.$data.sink { [weak self] data in self?.updateStatus(data) }.store(in: &subscriptions)
        statusTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let store = self.store else { return }
                self.updateStatus(store.data, advance: !self.popover.isShown)
            }
        }
        DispatchQueue.main.async { [weak self] in self?.login.askOnFirstLaunch() }
    }

    private func updateStatus(_ data: AppData, advance: Bool = false) {
        guard let button = statusItem?.button else { return }
        let entries = MenuBarQuota.entries(data: data)
        let index = entries.firstIndex { $0.provider == statusProvider } ?? 0
        let next = entries.isEmpty ? MenuBarQuota.empty : entries[(index + (advance && entries.count > 1 ? 1 : 0)) % entries.count]
        statusProvider = next.provider
        // Reserve the widest title so neighboring menu-bar icons do not move each tick.
        let font = button.font ?? NSFont.systemFont(ofSize: 12)
        statusItem?.length = ceil((entries.isEmpty ? [next] : entries).map {
            ($0.title as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 16) + 20
        button.toolTip = next.detail + (entries.count > 1 ? "\nCycles through paid plans every 8 seconds." : "")
        button.setAccessibilityLabel(next.detail)
        guard button.title != next.title else { return }
        flipGeneration += 1
        let generation = flipGeneration
        button.wantsLayer = true
        button.layer?.removeAnimation(forKey: "quotaFlip")
        guard advance, entries.count > 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = button.layer else { button.title = next.title; return }
        let fold = CABasicAnimation(keyPath: "transform.rotation.x")
        fold.fromValue = 0; fold.toValue = -Double.pi / 2; fold.duration = 0.13
        fold.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fold.fillMode = .forwards; fold.isRemovedOnCompletion = false
        layer.add(fold, forKey: "quotaFlip")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self, weak button] in
            guard let self, self.flipGeneration == generation, let button else { return }
            button.title = next.title
            let unfold = CABasicAnimation(keyPath: "transform.rotation.x")
            unfold.fromValue = Double.pi / 2; unfold.toValue = 0; unfold.duration = 0.17
            unfold.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button.layer?.add(unfold, forKey: "quotaFlip")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePopover() }
        return false
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Quit Bubble Tax", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
            NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: button)
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct MenuPanel: View {
    @EnvironmentObject var store: Store
    @State private var settings = CommandLine.arguments.contains("--show-connections")
    @State private var unusedHistory = CommandLine.arguments.contains("--show-unused-history")
    @State private var savings = CommandLine.arguments.contains("--show-savings")
    @State private var pageOrder: [Provider] = []
    @State private var userSelectedPage = CommandLine.arguments.contains("--demo-provider")
    @State private var expandedProviders: Set<Provider> = []
    @State private var selectedProvider: Provider = .openai

    init() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--demo-provider"), index + 1 < args.count,
           let provider = Provider(rawValue: args[index + 1]) {
            _selectedProvider = State(initialValue: provider)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if settings || savings || unusedHistory {
                    PanelToolbarButton(symbol: "chevron.left", label: "Back to overview") {
                        settings = false
                        savings = false
                        unusedHistory = false
                    }.keyboardShortcut(.cancelAction)
                }
                Text(settings ? "Settings" : savings ? "Savings" : unusedHistory ? "Unused history" : "Bubble Tax")
                    .font(.headline).lineLimit(1)
                if store.demoMode && !CommandLine.arguments.contains("--hide-demo-badge") {
                    Text("DEMO").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                        .help("Sample data for screenshots. Your real records are untouched.")
                }
                Spacer(minLength: 12)
                if !settings && !savings && !unusedHistory {
                    HStack(spacing: 8) {
                        PanelToolbarButton(symbol: "clock.arrow.circlepath", label: "Unused quota history") {
                            unusedHistory = true
                        }
                        PanelToolbarButton(symbol: "banknote", label: "Savings history") {
                            savings = true
                        }
                        PanelToolbarButton(symbol: "gearshape", label: "Settings") {
                            settings = true
                        }.disabled(store.demoMode)
                    }
                }
            }
            .frame(height: 28)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            if settings {
                Connections()
            } else if savings {
                SavingsHistory()
            } else if unusedHistory {
                UnusedHistoryView()
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            let fresh = store.data.scannedAt.map { Date().timeIntervalSince($0) < 900 } ?? false
                            PersonaHeader(assessment: PersonaAssessment.make(snapshot: store.data.snapshot,
                                providers: store.personaProviders, fresh: fresh), pendingChanges: store.pendingRecordedChanges)
                            if !store.changes.isEmpty { SavingsSummary { savings = true } }
                            if let provider = detailProvider {
                                if hasMultipleDetectedPlans {
                                    Text("Quota left").font(.caption).foregroundStyle(.secondary)
                                    ServiceStrip(providers: visibleProviders, selected: Binding(
                                        get: { provider }, set: { selectedProvider = $0; userSelectedPage = true }))
                                    Divider()
                                }
                                SubscriptionOverview(provider: provider, showConnections: { settings = true }, detailsChanged: { expanded in
                                    if expanded { expandedProviders.insert(provider) } else { expandedProviders.remove(provider) }
                                }).id(provider)
                                    .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
                                        if abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                                            movePage(value.translation.width < 0 ? 1 : -1)
                                        }
                                    })
                            } else {
                                Text("No services selected.").foregroundStyle(.secondary)
                                Button("Connect services…") { settings = true }
                            }
                            Text("* Unused: expired windows · last 30 days.")
                                .font(.caption2).foregroundStyle(.secondary)
                                .help("Requires an identified account and a check within 15 minutes of reset. Missing periods and detected early resets are excluded. Weekly and shorter limits are separate budgets.")
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                    }.frame(height: min(expandedProviders.contains(detailProvider ?? selectedProvider) ? 680 : 500,
                                        max(340, (NSScreen.main?.visibleFrame.height ?? 900) - 150)))
                    .onAppear {
                        // Demo-only capture aid: show the native receipts below the fold.
                        if store.demoMode, CommandLine.arguments.contains("--show-receipts") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                if let first = QuotaUsage.summaries(provider: selectedProvider,
                                    windows: store.data.snapshot?.quotaWindows ?? []).first {
                                    scrollProxy.scrollTo("quota-receipts-\(first.id)", anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
            }
            Divider()
            HStack {
                Button("Refresh") { Task { await store.scan() } }
                    .disabled(store.demoMode || store.scanning || (store.providers.isEmpty && store.data.piFolder == nil))
                if store.scanning {
                    ProgressView().controlSize(.small)
                } else if let scanned = store.data.scannedAt {
                    Text(scanned, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.controlSize(.small).padding(12)
        }.frame(width: 430)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                pageOrder = store.orderedProviders
                if !userSelectedPage, !CommandLine.arguments.contains("--demo-provider"), store.reviewFirst,
                   let first = pageOrder.first { selectedProvider = first }
            }
            .onChange(of: store.reviewFirst) { _ in
                pageOrder = store.orderedProviders
                userSelectedPage = true
            }
            .onChange(of: store.providers) { _ in pageOrder = store.orderedProviders }
            .onChange(of: store.data.scannedAt) { _ in
                pageOrder = store.orderedProviders
                if !userSelectedPage, store.reviewFirst, let first = pageOrder.first { selectedProvider = first }
            }
            .onChange(of: store.data.subscriptionChanges) { _ in pageOrder = store.orderedProviders }
    }
}

private extension MenuPanel {
    var detectedProviders: [Provider] {
        visibleProviders.filter { provider in
            guard let connection = store.connection(provider), connection.status == "connected" else { return false }
            return !(connection.planLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
    var hasMultipleDetectedPlans: Bool { detectedProviders.count > 1 }
    var detailProvider: Provider? {
        if detectedProviders.count == 1 { return detectedProviders.first }
        return visibleProviders.contains(selectedProvider) ? selectedProvider : visibleProviders.first
    }
    var visibleProviders: [Provider] {
        let retained = pageOrder.filter { store.providers.contains($0) }
        return retained + store.providers.filter { !retained.contains($0) }
    }
    func movePage(_ direction: Int) {
        guard hasMultipleDetectedPlans else { return }
        userSelectedPage = true
        let providers = visibleProviders
        guard !providers.isEmpty else { return }
        let index = providers.firstIndex(of: selectedProvider) ?? 0
        selectedProvider = providers[(index + direction + providers.count) % providers.count]
    }
}

private struct ServiceStrip: View {
    @EnvironmentObject var store: Store
    let providers: [Provider]
    @Binding var selected: Provider
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(providers) { provider in
                let fresh = store.data.scannedAt.map { Date().timeIntervalSince($0) < 900 } ?? false
                let roast = UsageRoast.make(provider: provider, snapshot: store.data.snapshot, fresh: fresh)
                let recorded = store.latestChange(provider)
                let review = ReviewPriority.isCandidate(roast) && recorded == nil
                let quotas = QuotaUsage.summaries(provider: provider, windows: store.data.snapshot?.quotaWindows ?? [])
                    .filter { $0.current != nil }
                Button { selected = provider } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name(provider)).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(recorded != nil ? "Recorded" : review ? "Review" : " ")
                            .font(.caption2.weight(.medium)).foregroundStyle(review ? .orange : .secondary)
                            .help(recorded?.kind.title ?? roast.status)
                        if quotas.isEmpty {
                            Text("—").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(quotas.prefix(2))) { quota in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(period(quota)) \(quota.current.map { quotaPercent($0.remainingPercent) } ?? "—")")
                                        .font(.caption2).monospacedDigit()
                                    if let current = quota.current { QuotaBalanceBar(remaining: current.remainingPercent) }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                        .padding(6)
                        .background(selected == provider ? Color.accentColor.opacity(0.13) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(selected == provider ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(provider.serviceName)
                    .accessibilityAddTraits(selected == provider ? .isSelected : [])
                    .help("\(provider.serviceName) · quota left · click to open" + (review ? "\nReview suggested: " + roast.evidence : ""))
            }
        }
    }
    private func name(_ provider: Provider) -> String {
        switch provider {
        case .openai: return "Codex"
        case .claude: return "Claude"
        case .copilot: return "Copilot"
        case .antigravity: return "Antigrav."
        default: return provider.title
        }
    }
    private func period(_ quota: QuotaUsage) -> String {
        switch quota.windowMinutes {
        case 300: return "5h"
        case 10080: return "Wk"
        case 1440: return "Day"
        case 43200: return "Mo"
        default: return "\(quota.windowMinutes)m"
        }
    }
}

private func quotaPercent(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US"))) + "%"
}

private func quotaDate(_ value: Date) -> String {
    value.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US")))
}

private struct SubscriptionOverview: View {
    @EnvironmentObject var store: Store
    let provider: Provider
    @State private var copied = false
    @State private var roastVariant = 0
    @State private var detailsExpanded: Bool
    @State private var recordSheet = CommandLine.arguments.contains("--show-record-change")
    @State private var billingSheet = false
    @State private var comparisonSheet = CommandLine.arguments.contains("--show-downgrade-comparison")
    let showConnections: () -> Void
    let detailsChanged: (Bool) -> Void

    init(provider: Provider, showConnections: @escaping () -> Void, detailsChanged: @escaping (Bool) -> Void) {
        self.provider = provider
        self.showConnections = showConnections
        self.detailsChanged = detailsChanged
        _detailsExpanded = State(initialValue: provider == .openai && CommandLine.arguments.contains("--show-details"))
    }

    var body: some View {
        let connection = store.connection(provider)
        let context = connection?.planContext ?? .unknown
        let fresh = store.data.scannedAt.map { Date().timeIntervalSince($0) < 900 } ?? false
        let roast = UsageRoast.make(provider: provider, snapshot: store.data.snapshot, fresh: fresh,
                                    context: context, variant: roastVariant)
        let quotas = QuotaUsage.summaries(provider: provider, windows: store.data.snapshot?.quotaWindows ?? [])
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(provider.serviceName).font(.headline)
                if context == .organization {
                    Text("Work plan").font(.caption).foregroundStyle(.secondary)
                } else if context == .free {
                    Text("Free").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Plan actions") {
                    Button(context == .organization ? "Review seat with provider…" : "Cancellation options…") {
                        if quotas.isEmpty && connection?.status != "connected" { showConnections() }
                        else { NSWorkspace.shared.open(managementURL) }
                    }.disabled(store.demoMode || context == .free)
                    if context == .personal {
                        Button("Compare downgrade…") { comparisonSheet = true }
                            .disabled(PlanPricing.lookup(provider: provider, label: connection?.planLabel)?.exact == nil)
                    }
                    Divider()
                    Button("Set renewal schedule…") { billingSheet = true }.disabled(store.demoMode)
                    Button("Record completed change…") { recordSheet = true }
                        .disabled(store.demoMode || store.changeConnection(provider) == nil ||
                            store.latestChange(provider)?.kind == .cancelled || store.latestChange(provider)?.kind == .releasedSeat)
                }.controlSize(.small)
                    .help("Review the plan with the provider, then record a completed change")
            }
            if let connection, connection.status == "connected",
               let price = PlanPricing.lookup(provider: provider, label: connection.planLabel) {
                Text("\(connection.planLabel ?? "Plan") · \(price.display) / mo · list price")
                    .font(.caption).foregroundStyle(.secondary)
                    .help(PlanPricing.caveat)
            }
            if let schedule = store.billingSchedule(provider) {
                Label("Renews \(schedule.nextRenewal().formatted(.dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US")))) · \(schedule.interval.title)", systemImage: "calendar")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Renewal schedule set by you. Independent of usage quota resets.")
            }
            RoastMessage(roast: roast, copied: copied, refreshing: store.scanning, completed: store.latestChange(provider), another: {
                Task {
                    await store.scan()
                    roastVariant = (roastVariant + 1) % 10_000; copied = false
                }
            }, copy: {
                NSPasteboard.general.clearContents()
                let text = store.latestChange(provider).map {
                    "\($0.kind.title), recorded by me · \($0.fromPlan) → \($0.toPlan)\n\(roast.evidence)\nBubble Tax"
                } ?? "\(roast.headline)\n\(roast.punchline)\n\(roast.evidence)\nBubble Tax"
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
            })
            if !quotas.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(quotas) { quota in QuotaOverviewRow(quota: quota) }
                }
            } else {
                Text(connection?.status == "connected" ? "Quota not reported by this account" : "Quota connection unavailable")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !quotas.isEmpty || roast.records > 0 || connection?.status == "connected" {
                DisclosureGroup("Details", isExpanded: $detailsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(roast.evidence).font(.caption).foregroundStyle(.secondary)
                        if let connection {
                            if let plan = connection.planLabel {
                                Text("Reported plan: \(plan)").font(.caption)
                                if let price = PlanPricing.lookup(provider: provider, label: plan), let url = URL(string: price.sourceURL) {
                                    Link("Pricing source · checked " + PlanPricing.checkedOn, destination: url).font(.caption)
                                    Label("US monthly list prices", systemImage: "info.circle")
                                        .font(.caption).foregroundStyle(.secondary).help(PlanPricing.caveat)
                                }
                            }
                            if connection.status == "connected" && connection.accountKey == nil {
                                Label("Unidentified account", systemImage: "person.crop.circle.badge.questionmark")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .help("Account identity unavailable. Historical snapshots aren't merged across refreshes.")
                            }
                            Text(connection.status == "connected" ? "Source: \(connection.source)" : "Refresh unavailable. Showing previous records.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if context == .organization {
                            Text(RealWorldSavings.workMessage).font(.callout)
                            Label("Shared limits · work plan", systemImage: "building.2")
                                .font(.caption).foregroundStyle(.secondary)
                                .help("Organization-managed plan. Limits may be shared. Review the license with your workspace owner.")
                        } else if context == .free {
                            Label("Free plan", systemImage: "checkmark.seal").font(.caption).foregroundStyle(.secondary)
                                .help("A free plan was reported. No paid subscription to cancel.")
                        }
                        ForEach(quotas) { quota in
                            QuotaReceipt(quota: quota).id("quota-receipts-\(quota.id)")
                        }
                        if provider.supportsCLI {
                            LocalActivityStrip(provider: provider, days: store.data.snapshot?.days ?? [],
                                               activeDays: roast.activeDays, tokens: roast.tokens)
                        }
                        PiActivity(provider: provider)
                        Label("Provider-reported plan", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                            .help("Plan labels don't establish who pays. Historical quota estimates start fresh when the reported account or plan changes.")
                    }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.caption)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .sheet(isPresented: $billingSheet) { BillingScheduleSheet(provider: provider).environmentObject(store) }
            .sheet(isPresented: $comparisonSheet) { DowngradeComparisonSheet(provider: provider).environmentObject(store) }
            .sheet(isPresented: $recordSheet) { RecordChangeSheet(provider: provider).environmentObject(store) }
            .onChange(of: store.data.scannedAt) { _ in copied = false }
            .onAppear { detailsChanged(detailsExpanded) }
            .onChange(of: detailsExpanded) { detailsChanged($0) }
    }
    private var managementURL: URL {
        if store.connection(provider)?.planContext == .organization {
            switch provider {
            case .openai: return URL(string: "https://chatgpt.com")!
            case .claude: return URL(string: "https://claude.ai/settings")!
            case .copilot: return URL(string: "https://github.com/settings/organizations")!
            case .gemini: return URL(string: "https://admin.google.com")!
            default: break
            }
        }
        switch provider {
        case .openai:
            return URL(string: "https://help.openai.com/en/articles/7232927-canceling-your-chatgpt-subscription")!
        case .claude:
            return URL(string: "https://support.claude.com/en/articles/8325617-cancel-your-pro-or-max-subscription")!
        case .cursor: return URL(string: "https://cursor.com/dashboard")!
        case .gemini: return URL(string: "https://one.google.com")!
        case .copilot: return URL(string: "https://github.com/settings/billing")!
        case .windsurf: return URL(string: "https://www.google.com")! // Legacy decoding only; not shown.
        case .antigravity: return URL(string: "https://antigravity.google")!
        case .other: return URL(string: "https://www.google.com")!
        }
    }
}

/// Equal label bounds keep native button bezels consistent across SF Symbols.
private struct PanelToolbarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(label)
        .accessibilityLabel(label)
    }
}
