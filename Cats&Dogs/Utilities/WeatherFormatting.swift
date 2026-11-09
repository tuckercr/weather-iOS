import Foundation

enum WeatherFormatting {
    /// Whole degrees: forecasts aren't accurate to a tenth, and other weather apps don't show one.
    /// "89°", or "89 °F" with `temperature_units_shown` on in Remote Config (off by default). Every
    /// temperature that can show its unit comes through here, so that switch is read in this one place.
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
        case .metric where speed < wholeMetersPerSecondFrom: String(localized: "\(String(format: "%.1f", speed)) m/s", comment: "Wind speed with its unit")
        case .metric: String(localized: "\(Int(speed.rounded())) m/s", comment: "Wind speed with its unit")
        case .imperial: isCalm(speed, units: units) ? String(localized: "0 mph", comment: "Wind speed with its unit") : String(localized: "\(Int(speed.rounded())) mph", comment: "Wind speed with its unit")
        }
    }

    /// A chance of rain as shown: nil under 10%, where it's noise (most dry hours forecast 1%), and
    /// otherwise to the nearest 10%, like Apple and Google Weather, since the forecast isn't more precise.
    static func rainChance(_ percent: Int) -> Int? {
        percent < 10 ? nil : (percent + 5) / 10 * 10
    }

    /// An hour's chance of rain as the hourly strip shows it, with a hidden chance (under 10%) as 0.
    /// Every rule that weighs an hour's chance (the walk limit, "rain" against "maybe rain") reads
    /// this, so an hour shown as 60% is "rain" and one shown as 30% meets a 30% walk limit.
    static func shownRainChance(_ percent: Int) -> Int {
        rainChance(percent) ?? 0
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

    static func todayLabel(timeZone: TimeZone = .current, on date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    /// The WHO exposure category for a UV index, e.g. "High" for 6.
    static func uvLevel(_ uv: Double) -> String {
        switch Int(uv.rounded()) {
        case ...2: String(localized: "Low", comment: "UV exposure category (WHO)")
        case 3...5: String(localized: "Moderate", comment: "UV exposure category (WHO), or air quality band name on the Air Quality tile")
        case 6...7: String(localized: "High", comment: "UV exposure category (WHO)")
        case 8...10: String(localized: "Very high", comment: "UV exposure category (WHO)")
        default: String(localized: "Extreme", comment: "UV exposure category (WHO)")
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
