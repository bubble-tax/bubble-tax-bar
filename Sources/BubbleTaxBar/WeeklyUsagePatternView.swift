import SwiftUI
import BubbleTaxBarCore

/// The old quota-exhaustion challenge is now a planning and headroom forecast.
struct WeeklyUsagePatternView: View {
    let provider: Provider
    var body: some View { WeeklyRunwayCard(provider: provider) }
}
