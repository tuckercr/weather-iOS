import SwiftUI

/// Shown in place of the weather when a fetch fails and there's nothing cached to fall back to: the
/// pets (with the router knocked over when offline), what went wrong, and a way to try again.
struct WeatherErrorStateView: View {
    let errorKey: String
    let canRetry: Bool
    let onRetry: () -> Void
    /// When the weather on file is too old to show: "yesterday at 10:10 AM".
    var lastUpdated: String?

    private var offline: Bool { errorKey == "offline" }

    var body: some View {
        VStack(spacing: 12) {
            PetScene(mood: .cloudy, knockedOverRouter: offline)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                .background(PetMood.cloudy.skyColor, in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 24)
            Text(offline ? "No connection" : "Weather unavailable")
                .font(.brand(.title2))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            Text(WeatherErrorMessages.message(for: errorKey))
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
            if let lastUpdated {
                Text("Last updated \(lastUpdated).")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
            }
            if canRetry {
                Button(action: onRetry) {
                    Text("Try again")
                        .frame(maxWidth: .infinity)
                }
                .accentButtonStyle()
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.horizontal, 8)
    }
}

/// Above cached weather when the last refresh failed: when the data is from, and why it's old.
/// Pull to refresh tries again, and the banner goes once a refresh succeeds.
struct StaleWeatherBanner: View {
    let weather: CurrentWeather
    let errorKey: String
    /// The reading is past the cutoff and the screen shows the cached forecast for this hour.
    var showingForecast = false
    var now = Date()

    // Fixed in both appearances, like the hero card it sits above (text 8.9:1).
    private static let background = Color(hex: 0xFAEEDA)
    private static let foreground = Color(hex: 0x633806)

    private var lead: String {
        guard let readingTime = StaleWeather.readingTime(weather, now: now) else { return String(localized: "Showing saved weather.", comment: "Banner over old weather when a refresh fails. The argument is when it was observed.") }
        return showingForecast ? String(localized: "Showing the forecast from \(readingTime).", comment: "Banner over old weather when a refresh fails. The argument is when it was observed.") : String(localized: "Showing weather from \(readingTime).", comment: "Banner over old weather when a refresh fails. The argument is when it was observed.")
    }

    /// The banner has no button, so the offline message says how to retry; the other messages
    /// already say when to try again.
    private var bannerText: String {
        [lead, WeatherErrorMessages.message(for: errorKey), errorKey == "offline" ? WeatherErrorMessages.pullToRetry : nil]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: errorKey == "offline" ? "wifi.slash" : "clock.arrow.circlepath")
                .accessibilityHidden(true)
            Text(bannerText)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Self.foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Self.background, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Offline, nothing cached") {
    WeatherErrorStateView(errorKey: "offline", canRetry: true, onRetry: {})
        .padding()
}

#Preview("Server error, nothing cached") {
    WeatherErrorStateView(errorKey: "server_error", canRetry: true, onRetry: {})
        .padding()
}
