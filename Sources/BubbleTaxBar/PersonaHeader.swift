import SwiftUI
import BubbleTaxBarCore

struct PersonaHeader: View {
    let assessment: PersonaAssessment
    var pendingChanges = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                PersonaPortrait(persona: pendingChanges ? .pending : assessment.persona)
                VStack(alignment: .leading, spacing: 5) {
                    Text(pendingChanges ? "Changes recorded" : assessment.persona.title).font(.headline)
                    Text(pendingChanges ? "Provider updates pending." : (assessment.pendingReason ?? assessment.persona.weeklyMessage)).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                if let remaining = pendingChanges ? nil : assessment.remainingPercent {
                    QuotaRing(value: remaining)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("~\(Int(remaining.rounded()))% left").font(.callout.weight(.semibold)).monospacedDigit()
                        Text(assessment.coveredPlans < (assessment.personalPlans > 0 ? assessment.personalPlans : assessment.workPlans)
                             ? "Weekly · \(assessment.coveredPlans)/\(assessment.personalPlans > 0 ? assessment.personalPlans : assessment.workPlans) plans"
                             : "Weekly · current")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.help("\(assessment.coveredPlans) plans with fresh weekly quota. " + assessment.scope + ". Remaining quota can still be used before reset; this is not expired waste.")
                }
                Spacer(minLength: 4)
                if !pendingChanges, let range = assessment.monthlyRange, let currency = assessment.currency {
                    let low = range.lowerBound.formatted(.currency(code: currency).locale(Locale(identifier: "en_US")))
                    let high = range.upperBound.formatted(.currency(code: currency).locale(Locale(identifier: "en_US")))
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(low)\(range.lowerBound == range.upperBound ? "" : "–" + high) / mo")
                            .font(.callout.weight(.medium)).monospacedDigit()
                        Text(assessment.usesListPrices ? "List-price estimate" : "Verified billing")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.help((assessment.priceWeighted ? "Price-weighted current weekly quota left. " : "Weekly quota-based persona. ") + PlanPricing.caveat)
                } else if !pendingChanges, assessment.personalPlans > 0 {
                    Label("Price unavailable", systemImage: "questionmark.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if !pendingChanges, assessment.workPlans > 0 {
                    Label("Work plans", systemImage: "building.2")
                        .font(.caption2).foregroundStyle(.secondary)
                        .help("Organization plans are excluded from personal billing.")
                }
            }

        }.padding(.bottom, 6)
            .accessibilityElement(children: .contain)
    }
}

struct PersonaPortrait: View {
    let persona: SubscriptionPersona
    private var portrait: NSImage? {
        let url = Bundle.main.url(forResource: persona.rawValue, withExtension: "png", subdirectory: "Personas")
            ?? Bundle.module.url(forResource: persona.rawValue, withExtension: "png", subdirectory: "Personas")
        return url.flatMap { NSImage(contentsOf: $0) }
    }
    var body: some View {
        Group {
            if let portrait {
                Image(nsImage: portrait).renderingMode(.original).resizable()
                    .interpolation(.high).scaledToFit()
            } else {
                Image(systemName: persona.symbol).resizable().scaledToFit().padding(12)
            }
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true) // The adjacent title already names the persona.
    }
}
