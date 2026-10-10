import AppKit
import ServiceManagement

@MainActor
final class LoginAtLaunch: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var error: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = "Could not change launch at login: \(error.localizedDescription)" }
        refresh()
    }

    func askOnFirstLaunch() {
        guard !CommandLine.arguments.contains("--demo-data"),
              Bundle.main.bundleURL.pathExtension == "app",
              !UserDefaults.standard.bool(forKey: "launchAtLoginPromptAnswered"),
              // Answered under the pre-rename SubRIP bundle identifier.
              UserDefaults(suiteName: "app.subrip.local")?.bool(forKey: "launchAtLoginPromptAnswered") != true else { return }
        refresh()
        if !enabled {
            let alert = NSAlert()
            alert.messageText = "Open Bubble Tax when you log in?"
            alert.informativeText = "Keep your unused AI quota in the menu bar after every restart. You can change this in Settings."
            alert.addButton(withTitle: "Open at Login")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { setEnabled(true) }
        }
        UserDefaults.standard.set(true, forKey: "launchAtLoginPromptAnswered")
    }
}
