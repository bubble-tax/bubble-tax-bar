import AppKit
import SwiftUI
import BubbleTaxBarCore
import UniformTypeIdentifiers

struct Tombstone: View {
    let name: String
    let monthly: String
    let assessment: Assessment
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Bubble Tax").font(.system(size: 24, weight: .black, design: .rounded)); Spacer(); Text("Subscription funeral †").font(.caption) }
                .foregroundStyle(.white.opacity(0.6))
            Spacer().frame(height: 38)
            VStack(spacing: 22) {
                Text("†").font(.system(size: 82, weight: .light)).foregroundStyle(Color(red: 0.69, green: 0.94, blue: 0.58))
                Text(assessment.verdict == .buried ? "R.I.P." : "Still paying for this?").font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(.white.opacity(0.55))
                Text(name).font(.system(size: 34, weight: .bold, design: .rounded)).multilineTextAlignment(.center).lineLimit(2)
                Rectangle().fill(.white.opacity(0.15)).frame(width: 90, height: 1)
                Text("\(monthly) every month").font(.system(size: 24, weight: .medium))
                Text(assessment.verdict == .buried ? "Cancellation recorded." : "Used on \(assessment.activeDays) days this cycle")
                    .font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
                Text(assessment.verdict.rawValue).font(.caption.bold()).padding(.horizontal, 18).padding(.vertical, 9)
                    .background(.white.opacity(0.1), in: Capsule())
            }.padding(30).frame(width: 380, height: 450)
                .background(Color(red: 0.14, green: 0.17, blue: 0.14), in: UnevenTombstone())
            Spacer().frame(height: 30)
            Text(assessment.verdict == .buried ? "Give your unused subscriptions a proper goodbye." : "Your subscription is on a paid vacation.")
                .font(.system(size: 19, weight: .semibold))
            Spacer()
            Text("Local and manual usage records · No quota or waste-cost estimate")
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
            Text("Check your plan, cost and usage before sharing.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Close") { dismiss() }
                Button("Save PNG") { export() }.buttonStyle(.borderedProminent).tint(.mint)
            }
        }.padding(24).frame(width: 430).preferredColorScheme(.dark)
    }
    @MainActor private func export() {
        let renderer = ImageRenderer(content: Tombstone(name: item.name, monthly: store.money(item.monthlyPrice, currency: item.currency), assessment: assessment))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let bytes = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            error = "Could not render the share card."; return
        }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "BubbleTaxBar-tombstone.png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            do { try bytes.write(to: url, options: .atomic) } catch { self.error = error.localizedDescription }
        }
    }
}
