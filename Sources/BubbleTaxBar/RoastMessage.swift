import SwiftUI
import BubbleTaxBarCore

struct RoastMessage: View {
    let roast: UsageRoast
    let copied: Bool
    let refreshing: Bool
    var completed: SubscriptionChange? = nil
    let another: () -> Void
    let copy: () -> Void
    @State private var expanded = false

    private var completedHeadline: String? {
        guard let completed else { return nil }
        switch completed.kind {
        case .cancelled: return "Auto-renew lost a customer. Allegedly, you."
        case .downgraded: return "Same main character. Smaller subscription bill."
        case .releasedSeat: return "Procurement got a chair back."
        }
    }
    private var completedMessage: String? {
        guard let completed else { return nil }
        return "\(completed.kind.title), recorded by you. Provider readings may still reflect the previous plan."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Label("Bubble Tax", systemImage: "text.bubble")
                Spacer()
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "info.circle.fill" : "info.circle") }
                    .help("Show context and receipts").accessibilityLabel("Show roast context")
                Button(action: another) {
                    if refreshing { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.clockwise") }
                }.disabled(refreshing)
                    .help("Refresh usage and roast").accessibilityLabel("Refresh usage and roast")
                Button(action: copy) { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .help(copied ? "Copied" : "Copy roast and receipts")
                    .accessibilityLabel(copied ? "Copied" : "Copy roast")
            }.font(.caption).foregroundStyle(.secondary).buttonStyle(.borderless)
                .padding(.leading, 10)
            VStack(alignment: .leading, spacing: 5) {
                Text(completedHeadline ?? roast.headline).font(.callout.weight(.medium))
                if expanded {
                    Text(completedMessage ?? roast.punchline).font(.caption).foregroundStyle(.secondary)
                    Text(roast.evidence).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8).padding(.leading, 18).padding(.trailing, 12)
            .background(IncomingBubble().fill(Color(nsColor: .controlColor)))
            .overlay(IncomingBubble().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
            .accessibilityElement(children: .combine)
            .help(roast.evidence)
        }.padding(.trailing, 16).padding(.vertical, 2)
    }
}

private struct IncomingBubble: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 20, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 12, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 12), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 12))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 12, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 20, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 1), control: CGPoint(x: rect.minX + 9, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 16), control: CGPoint(x: rect.minX + 9, y: rect.maxY - 6))
        path.addLine(to: CGPoint(x: rect.minX + 8, y: rect.minY + 12))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 20, y: rect.minY), control: CGPoint(x: rect.minX + 8, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
