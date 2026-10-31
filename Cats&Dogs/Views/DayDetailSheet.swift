import SwiftUI

struct DayDetailSheet: View {
    let day: DayForecast
    @Environment(\.dismiss) private var dismiss
    /// Landscape phones have little height, so the hours run sideways instead.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Divider()
                    if day.hourlySlots.isEmpty {
                        Text("Hourly data not available for this day.")
                            .foregroundStyle(Color.secondaryText)
                            .padding(.vertical, 8)
                    } else if verticalSizeClass == .compact {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(day.hourlySlots) { slot in
                                    HourlySlotColumn(slot: slot)
                                }
                            }
                        }
                    } else {
                        ForEach(day.hourlySlots) { slot in
                            HourlySlotRow(slot: slot)
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle(day.dateLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Open fully: a half-height sheet leaves almost nothing visible in landscape.
        .presentationDetents([.large])
        .presentationBackground(Color.brandSurface)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            WeatherIconView(iconCode: day.iconCode, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(day.description)
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(WeatherFormatting.temperature(day.tempMax, units: day.units))
                    .font(.brand(.title2, weight: .bold))
                    .fontWeight(.bold)
                Text(WeatherFormatting.temperature(day.tempMin, units: day.units))
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding(.top, 8)
    }

}

private struct HourlySlotRow: View {
    let slot: HourlySlot

    var body: some View {
        HStack(spacing: 8) {
            Text(slot.timeLabel)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Rain before the icon, so the temperatures line up at the end.
            PrecipChance(percent: slot.precipitationChance)
            WeatherIconView(iconCode: slot.iconCode, size: 28, description: slot.description, date: slot.date)
            Text(WeatherFormatting.temperature(slot.temperature, units: slot.units))
                .fontWeight(.semibold)
        }
        .padding(.vertical, 8)
    }
}

/// One hour as a vertical cell, for the sideways landscape layout.
private struct HourlySlotColumn: View {
    let slot: HourlySlot

    var body: some View {
        VStack(spacing: 6) {
            Text(slot.timeLabel)
                .fontWeight(.medium)
            WeatherIconView(iconCode: slot.iconCode, size: 28, description: slot.description, date: slot.date)
            Text(WeatherFormatting.temperature(slot.temperature, units: slot.units))
                .fontWeight(.semibold)
            PrecipChance(percent: slot.precipitationChance)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
