import Foundation

enum WeatherFormatting {
    /// Whole degrees: forecasts aren't accurate to a tenth, and other weather apps don't show one.
    /// "89 °F", or "89°" with `temperature_units_shown` off in Remote Config. Every temperature shown
    /// with its unit comes through here, so that switch is read in this one place.
    static func temperature(
        _ value: Double,
        units: WeatherUnits,
        showsUnit: Bool = RemoteConfigRepository.temperatureUnitsShown
    ) -> String {
        let degrees = Int(value.rounded())
        guard showsUnit else { return "\(degrees)°" }
        return switch units {
        case .metric: "\(degrees) °C"
        case .imperial: "\(degrees) °F"
        }
    }

    /// At and above this many m/s (what rounds to 10.0), wind speeds show without a decimal.
    private static let wholeMetersPerSecondFrom = 9.95

    /// Whole mph, and whole m/s from 10 up; below that a whole m/s is too coarse (3 m/s is anything
    /// from a light to a gentle breeze), so it keeps one decimal.
    static func wind(_ speed: Double, units: WeatherUnits) -> String {
        switch units {
        case .metric where isCalm(speed, units: units): "0 m/s"
        case .metric where speed < wholeMetersPerSecondFrom: String(format: "%.1f m/s", speed)
        case .metric: "\(Int(speed.rounded())) m/s"
        case .imperial: isCalm(speed, units: units) ? "0 mph" : "\(Int(speed.rounded())) mph"
        }
    }

    /// A chance of rain as shown: nil under 10%, where it's noise (most dry hours forecast 1%), and
    /// otherwise to the nearest 10%, like Apple and Google Weather, since the forecast isn't more precise.
    static func rainChance(_ percent: Int) -> Int? {
        percent < 10 ? nil : (percent + 5) / 10 * 10
    }

    /// A speed that would show as 0 (whole mph, or m/s to one decimal): written as a plain 0, and calm.
    static func isCalm(_ speed: Double, units: WeatherUnits) -> Bool {
        speed < (units == .imperial ? 0.5 : 0.05)
    }

    /// Whether distances (visibility) read in miles: the app's unit choice, or for "Use system
    /// setting" the system's measurement system (Settings › General › Language & Region), where the
    /// US and UK use miles.
    static func usesMiles(override: UnitOverride, locale: Locale = .current) -> Bool {
        switch override {
        case .metric: false
        case .imperial: true
        case .system: locale.measurementSystem != .metric
        }
    }

    static func todayLabel(timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: Date())
    }

    /// The WHO exposure category for a UV index, e.g. "High" for 6.
    static func uvLevel(_ uv: Double) -> String {
        switch Int(uv.rounded()) {
        case ...2: "Low"
        case 3...5: "Moderate"
        case 6...7: "High"
        case 8...10: "Very high"
        default: "Extreme"
        }
    }

    static func epochTime(_ epochSeconds: Int, timeZone: TimeZone = .current) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
