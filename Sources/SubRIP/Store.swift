import AppKit
import SwiftUI
import SubRIPCore

@MainActor
final class Store: ObservableObject {
    @Published var data = AppData()
    @Published var error: String?
    @Published var scanning = false
    @Published var ready = true
    private let location: URL
    private var timer: Timer?

    init() {
        location = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubRIP/state.json")
        do {
            if FileManager.default.fileExists(atPath: location.path) {
                data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: location))
                guard data.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            }
        } catch {
            self.error = "저장된 파일을 읽지 못했어요. 원본을 보존했어요: \(location.path)"
            ready = false
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.scan() }
        }
        if data.codexFolder != nil || data.claudeFolder != nil {
            Task { await scan() }
        }
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
    func save() {
        guard ready else { return }
        do {
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: location, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        } catch { self.error = "저장 실패: \(error.localizedDescription)" }
    }
    func upsert(_ subscription: Subscription) {
        guard ready else { return }
        if subscription.includesCLI && active.contains(where: { $0.id != subscription.id && $0.provider == subscription.provider && $0.includesCLI }) {
            error = "같은 서비스의 CLI 로그는 활성 구독 하나에만 연결할 수 있어요."; return
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
    func chooseFolder(_ provider: Provider) {
        guard ready, !scanning else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.message = provider == .claude ? "Claude Code의 projects 폴더를 선택하세요. 대화 내용은 저장하거나 전송하지 않아요." : "Codex의 sessions 폴더를 선택하세요. 대화 내용은 저장하거나 전송하지 않아요."
        if panel.runModal() == .OK, let url = panel.url {
            if provider == .claude { data.claudeFolder = url.path } else { data.codexFolder = url.path }
            data.snapshot = nil; data.scannedAt = nil; save()
            Task { await scan() }
        }
    }
    func disconnect(_ provider: Provider) {
        guard !scanning else { return }
        if provider == .claude { data.claudeFolder = nil } else { data.codexFolder = nil }
        data.snapshot = nil; data.scannedAt = nil; save()
    }
    func scan() async {
        guard ready, !scanning, data.codexFolder != nil || data.claudeFolder != nil else { return }
        scanning = true
        defer { scanning = false }
        guard let script = Bundle.main.url(forResource: "collector", withExtension: "py") ?? Bundle.module.url(forResource: "collector", withExtension: "py") else {
            error = "사용량 수집기를 찾지 못했어요."; return
        }
        let claude = data.claudeFolder, codex = data.codexFolder
        do {
            let output = try await Task.detached(priority: .utility) {
                let process = Process()
                // CLT supplies /usr/bin/python3. Other installs are supported as fallbacks.
                let candidates = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
                guard let python = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                    throw NSError(domain: "SubRIP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Python 3.9+가 필요해요. xcode-select --install을 실행하세요."])
                }
                process.executableURL = URL(fileURLWithPath: python)
                var arguments = [script.path, "--timezone", TimeZone.current.identifier]
                if let claude { arguments += ["--claude-folder", claude] }
                if let codex { arguments += ["--codex-folder", codex] }
                process.arguments = arguments
                let output = Pipe(); process.standardOutput = output
                // Parser failures can include local paths: don't echo raw stderr into the UI.
                process.standardError = FileHandle.nullDevice
                try process.run()
                let bytes = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw NSError(domain: "SubRIP", code: 2, userInfo: [NSLocalizedDescriptionKey: "수집 실패. Python 3.9+와 선택한 로그 폴더를 확인해 주세요."])
                }
                return try JSONDecoder().decode(CollectorSnapshot.self, from: bytes)
            }.value
            data.snapshot = output; data.scannedAt = Date(); save()
        } catch {
            data.snapshot = nil; data.scannedAt = nil; save()
            self.error = error.localizedDescription
        }
    }
}
