import SwiftUI
import BubbleTaxBarCore

struct AllocationForecastView: View {
    @EnvironmentObject var store: Store
    let options: [AllocationOption]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Will your plan fit?").font(.title2.weight(.semibold))
            Text("Set daily time, then check weekly headroom at your recorded window pace.").font(.caption).foregroundStyle(.secondary)
            ForEach(options) { option in
                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: Binding(get: { plannedHours(option, data: store.data) }, set: { value in
                        var prefs = store.data.allocationPreferences ?? AllocationPreferences()
                        prefs.hoursPerDay[hoursKey(option)] = value; store.setAllocationPreferences(prefs)
                    }), in: 0...24, step: 0.5) {
                        Text("\(option.title) · \(plannedHours(option, data: store.data), specifier: "%.1f")h / day plan").font(.caption.weight(.medium))
                    }.disabled(store.demoMode)
                    WeeklyRunwayCard(provider: option.provider)
                }
            }
            if options.isEmpty { Text("Refresh Claude or Codex usage to build a plan.").font(.caption) }
            Text("Daily time starts at an editable 2h assumption. Estimates use observed window hours, including idle time, and aren't guarantees of future work capacity.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private func hoursKey(_ option: AllocationOption) -> String { option.provider.rawValue + "|" + (option.connection.accountKey ?? "") }
private func plannedHours(_ option: AllocationOption, data: AppData) -> Double {
    let value = data.allocationPreferences?.hoursPerDay[hoursKey(option)] ?? 2
    return value.isFinite && value >= 0 && value <= 24 ? value : 2
}

struct WeeklyRunwayCard: View {
    @EnvironmentObject var store: Store
    let provider: Provider
    private var option: AllocationOption? {
        Allocation.options(data: store.data, workAccount: store.connection(provider)?.planContext == .organization,
                           respectEligibility: false).first { $0.provider == provider }
    }
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Weekly runway").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text(provider == .openai ? "Codex" : "Claude").font(.caption.weight(.medium))
                }
                if let option {
                    let hours = plannedHours(option, data: store.data)
                    let samples = (provider == .claude ? store.data.claudeQuotaSamples : store.data.codexQuotaSamples) ?? []
                    if option.weekly.remainingPercent <= 0 {
                        Text("Weekly quota used up").font(.headline)
                    } else if hours == 0 {
                        Text("No daily time scheduled").font(.headline)
                    } else if let forecast = QuotaForecast.make(option: option, samples: samples,
                        reservations: store.data.quotaReservations ?? [], hoursPerDay: hours) {
                        Text(forecast.reserveAtRisk ? "Reserved work may be at risk" : forecast.daysToEmpty < forecast.daysBeforeReset ? "Plan a service switch" : "Headroom through reset")
                            .font(.headline).foregroundStyle(forecast.reserveAtRisk ? Color.orange : Color.primary)
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading) {
                                if forecast.daysToProtectedFloor >= forecast.daysBeforeReset {
                                    Text("≈ \(max(0, option.weekly.remainingPercent - forecast.weeklyPerDay * forecast.daysBeforeReset - option.protected), specifier: "%.0f")%")
                                        .font(.title2.weight(.semibold)).monospacedDigit()
                                    Text(option.protected > 0 ? "above targets at reset" : "left at reset").font(.caption2).foregroundStyle(.secondary)
                                } else {
                                    Text(forecast.daysToProtectedFloor < 1 ? "≈ \(forecast.daysToProtectedFloor * hours, specifier: "%.1f")h of use" : "≈ \(forecast.daysToProtectedFloor, specifier: "%.1f") planned days")
                                        .font(.title2.weight(.semibold)).monospacedDigit()
                                    Text(option.protected > 0 ? "unallocated buffer" : "until weekly empty").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(forecast.daysBeforeReset, specifier: "%.1f") days").font(.callout).monospacedDigit()
                                Text("until reset").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        ProgressView(value: min(1, forecast.daysToProtectedFloor / max(0.001, forecast.daysBeforeReset))).tint(forecast.reserveAtRisk ? .orange : .secondary)
                        Text("\(hours, specifier: "%.1f")h/day plan · ≈ \(forecast.weeklyPerDay, specifier: "%.1f") weekly pp/day").font(.caption2).foregroundStyle(.secondary)
                        Text(forecast.observations == 1 ? "Early estimate · one recorded window" : "\(forecast.observations) recorded windows")
                            .font(.caption2).foregroundStyle(.secondary)
                        if option.session?.remainingPercent == 0 { Text("Current session full; check its reset before starting.").font(.caption2) }
                    } else {
                        Text("More paired observations needed").font(.callout.weight(.medium))
                        Text("A 5-hour and weekly meter must rise together across a measured interval.").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Refresh overall weekly usage").font(.callout.weight(.medium))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
