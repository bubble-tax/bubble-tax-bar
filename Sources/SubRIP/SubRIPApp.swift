import SwiftUI
import AppKit
import SubRIPCore

@main
@MainActor
struct SubRIPApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup("SubRIP", id: "dashboard") {
            Dashboard().environmentObject(store).preferredColorScheme(.dark)
                .frame(minWidth: 860, minHeight: 640)
        }
        .defaultSize(width: 980, height: 760)
        MenuBarExtra {
            MenuPanel().environmentObject(store).preferredColorScheme(.dark)
        } label: {
            Text("† \(store.active.filter { store.assessment($0).verdict == .review }.count)")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuPanel: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SubRIP †").font(.title2.bold())
            Text("안 쓰는 AI 구독, 편히 보내드리세요.").foregroundStyle(.secondary)
            let candidates = store.active.filter { store.assessment($0).verdict == .review }
            Text("장례 후보 \(candidates.count)개").font(.headline)
            Text("다음 달 절약 후보: \(store.totals(candidates))")
            ForEach(candidates.prefix(3)) { item in
                Text("† \(item.name) · \(store.assessment(item).nextBilling.formatted(date: .abbreviated, time: .omitted)) 갱신")
                    .font(.caption)
            }
            Button("구독 장례식 열기") {
                openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true)
            }.buttonStyle(.borderedProminent).tint(.mint)
            Button("종료") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
        }.padding(22).frame(width: 340)
    }
}
