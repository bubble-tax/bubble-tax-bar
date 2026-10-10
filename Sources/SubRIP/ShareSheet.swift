import AppKit
import SwiftUI
import SubRIPCore
import UniformTypeIdentifiers

struct Tombstone: View {
    let name: String
    let monthly: String
    let assessment: Assessment
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("SubRIP").font(.system(size: 24, weight: .black, design: .rounded)); Spacer(); Text("구독 장례식 †").font(.caption) }
                .foregroundStyle(.white.opacity(0.6))
            Spacer().frame(height: 38)
            VStack(spacing: 22) {
                Text("†").font(.system(size: 82, weight: .light)).foregroundStyle(Color(red: 0.69, green: 0.94, blue: 0.58))
                Text(assessment.verdict == .buried ? "R.I.P." : "아직 살아 계신가요?").font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(.white.opacity(0.55))
                Text(name).font(.system(size: 34, weight: .bold, design: .rounded)).multilineTextAlignment(.center).lineLimit(2)
                Rectangle().fill(.white.opacity(0.15)).frame(width: 90, height: 1)
                Text("매달 \(monthly)").font(.system(size: 24, weight: .medium))
                Text(assessment.verdict == .buried ? "사용자가 해지를 기록했습니다." : "이번 결제 주기 사용 \(assessment.activeDays)일")
                    .font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
                Text(assessment.verdict.rawValue).font(.caption.bold()).padding(.horizontal, 18).padding(.vertical, 9)
                    .background(.white.opacity(0.1), in: Capsule())
            }.padding(30).frame(width: 380, height: 450)
                .background(Color(red: 0.14, green: 0.17, blue: 0.14), in: UnevenTombstone())
            Spacer().frame(height: 30)
            Text(assessment.verdict == .buried ? "안 쓰는 AI 구독, 편히 보내드리세요." : "돈은 나가는데, AI는 쉬고 있나요?")
                .font(.system(size: 19, weight: .semibold))
            Spacer()
            Text("사용일은 로컬·직접 기록 기준 · 할당량/낭비 금액 추정 아님")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        }.padding(36).frame(width: 540, height: 700)
            .foregroundStyle(.white).background(Color(red: 0.055, green: 0.065, blue: 0.06))
    }
}

// Custom shape works on macOS 13; avoid macOS 14 UnevenRoundedRectangle.
struct UnevenTombstone: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = rect.width / 2
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath(); return p
    }
}

struct ShareSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let item: Subscription
    let assessment: Assessment
    @State private var error: String?
    var body: some View {
        VStack(spacing: 16) {
            Tombstone(name: item.name, monthly: store.money(item.monthlyPrice, currency: item.currency), assessment: assessment)
                .scaleEffect(0.65).frame(width: 351, height: 455)
            Text("공유 전에 플랜 이름·금액·사용일을 확인해 주세요.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("닫기") { dismiss() }
                Button("PNG 저장") { export() }.buttonStyle(.borderedProminent).tint(.mint)
            }
        }.padding(24).frame(width: 430).preferredColorScheme(.dark)
    }
    @MainActor private func export() {
        let renderer = ImageRenderer(content: Tombstone(name: item.name, monthly: store.money(item.monthlyPrice, currency: item.currency), assessment: assessment))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let bytes = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            error = "공유 카드를 만들지 못했어요."; return
        }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "SubRIP-tombstone.png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            do { try bytes.write(to: url, options: .atomic) } catch { self.error = error.localizedDescription }
        }
    }
}
