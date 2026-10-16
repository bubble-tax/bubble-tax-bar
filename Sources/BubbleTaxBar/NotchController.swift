import AppKit
import SwiftUI
import Combine
import BubbleTaxBarCore

/// Uses only the screen's public safe-area geometry. No camera or accessibility access.
@MainActor
final class NotchController {
    static let preference = "bubbleTaxNotchEnabled"
    private let store: Store
    private let login: LoginAtLaunch
    private let state = NotchQuotaState()
    private var compact: NotchPanel?
    private var expanded: NotchPanel?
    private var screen: NSScreen?
    private var observers: [NSObjectProtocol] = []
    private var outsideClick: Any?
    private var escapeKey: Any?
    private var enabled: Bool { UserDefaults.standard.object(forKey: Self.preference) as? Bool ?? true }
    var isExpanded: Bool { expanded?.isVisible == true }
    var isAvailable: Bool { compact?.isVisible == true }
    var availabilityChanged: (() -> Void)?

    init(store: Store, login: LoginAtLaunch) {
        self.store = store
        self.login = login
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.reconfigure() } })
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.reconfigure() } })
        reconfigure()
    }

    func update(_ entry: MenuBarQuota) { state.entry = entry }

    private func reconfigure() {
        let preview = CommandLine.arguments.contains("--preview-notch")
        let next = preview ? NSScreen.main : enabled ? NSScreen.screens.first(where: {
            $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil
        }) : nil
        guard let next else { disable(); return }
        let inset = preview ? CGFloat(32) : next.safeAreaInsets.top
        let left = preview ? NSRect(x: next.frame.minX, y: next.frame.maxY - inset,
            width: next.frame.width / 2 - 90, height: inset) : next.auxiliaryTopLeftArea
        let right = preview ? NSRect(x: next.frame.midX + 90, y: next.frame.maxY - inset,
            width: next.frame.width / 2 - 90, height: inset) : next.auxiliaryTopRightArea
        guard let left, let right, let geometry = NotchGeometry.make(screen: next.frame,
            left: left, right: right, topInset: inset) else { disable(); return }
        if let compact, screen === next, compact.frame == geometry.compact { return }
        close(); compact?.orderOut(nil); screen = next

        let panel = NotchPanel(contentRect: geometry.compact, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(panel)
        panel.contentView = NotchHostingView(rootView: NotchQuotaView(state: state, notchWidth: geometry.notchWidth,
            height: geometry.compact.height, wingWidth: geometry.wingWidth, action: { [weak self] in self?.toggle() }))
        compact = panel
        panel.setFrame(geometry.compact, display: true)
        panel.orderFrontRegardless()
        availabilityChanged?()
    }

    private func disable() {
        close(); compact?.orderOut(nil); compact = nil; screen = nil
        availabilityChanged?()
    }

    private func configure(_ panel: NSPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
    }

    func toggle() {
        if isExpanded { close(); return }
        guard let screen, let compact else { return }
        let width = min(CGFloat(430), screen.visibleFrame.width - 24)
        let height = min(CGFloat(620), screen.visibleFrame.height - 24)
        let x = min(max(compact.frame.midX - width / 2, screen.visibleFrame.minX + 12), screen.visibleFrame.maxX - width - 12)
        let frame = NSRect(x: x, y: compact.frame.minY - height - 6, width: width, height: height)
        let panel = NotchPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        configure(panel)
        panel.acceptsKeyboard = true
        panel.hasShadow = true
        panel.contentView = NotchHostingView(rootView:
            ScrollView {
                MenuPanel(provider: state.entry.provider, collapseNotch: { [weak self] in self?.close() })
                    .environmentObject(store).environmentObject(login)
                    .environment(\.locale, Locale(identifier: "en_US"))
            }.scrollIndicators(.hidden)
            .frame(width: width, height: height, alignment: .top)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
        expanded = panel
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Only mouse events are observed; no input-monitoring permission is needed.
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.close() }
        }
        escapeKey = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53, self?.expanded?.attachedSheet == nil { self?.close(); return nil }
            return event
        }
    }

    func close() {
        expanded?.orderOut(nil)
        expanded = nil
        if let outsideClick { NSEvent.removeMonitor(outsideClick); self.outsideClick = nil }
        if let escapeKey { NSEvent.removeMonitor(escapeKey); self.escapeKey = nil }
    }
}

private final class NotchPanel: NSPanel {
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
private final class NotchQuotaState: ObservableObject {
    @Published var entry = MenuBarQuota.empty
}

private struct NotchQuotaView: View {
    @ObservedObject var state: NotchQuotaState
    let notchWidth: CGFloat
    let height: CGFloat
    let wingWidth: CGFloat
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var pieces: [String] { state.entry.title.components(separatedBy: " · ") }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(state.entry.provider.map { $0 == .openai ? "Codex" : $0.serviceName } ?? "Bubble Tax")
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .frame(width: wingWidth)
                Color.clear.frame(width: notchWidth)
                Text(pieces.count > 1 ? pieces[1].replacingOccurrences(of: " quota ", with: " ") : "Open")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: wingWidth)
                    .id(state.entry.title)
                    .transition(.opacity)
            }.frame(height: height)
                .foregroundStyle(.white)
                .background(.black)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        }
        .buttonStyle(.plain)
        .help(state.entry.detail + "\nClick to expand.")
        .accessibilityLabel(state.entry.detail)
        .accessibilityHint("Click to expand Bubble Tax")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.entry.title)
    }
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
