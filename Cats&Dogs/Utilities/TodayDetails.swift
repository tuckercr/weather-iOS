import Foundation

/// The rules behind the Today tiles, kept out of the views so they can be tested. Same rules as
/// Android's `util/TodayDetails.kt`.
/// Which Today tiles show, from Remote Config. UV starts off.
struct TodayTileSwitches: Equatable {
    var feelsLike = true
    var wind = true
    var humidity = true
    var pawCheck = true
    var uv = false
    var daylight = true
    var sky = true
}

enum TodayDetails {
    /// The UV tile's line: today's peak while it's still ahead ("Peak 8 at 1 PM"); from the peak hour
    /// on, shade for pale-nosed dogs on a high day (6 and up) with a dog, otherwise "At today's peak"
    /// or "Easing off now".
    /// `isPetLine` is set for the dog's line, which takes the pets' colour.
    static func uvLine(
        peak: HourlySlot?,
        now: Date,
        hasDog: Bool
    ) -> (text: String, isPetLine: Bool) {
        guard let peak, let peakUV = peak.uvIndex else { return ("", false) }
        let rounded = Int(peakUV.rounded())
        guard let start = peak.date else { return ("Peak \(rounded) today", false) }
        if start > now { return ("Peak \(rounded) at \(peak.timeLabel)", false) }
        if hasDog, rounded >= 6 { return ("Shade for pale noses", true) }
        return start.addingTimeInterval(60 * 60) > now ? ("At today's peak", false) : ("Easing off now", false)
    }

    /// How far you can see, in the bands the Sky tile names.
    enum VisibilityBand: Equatable {
        case excellent, good, moderate, poor

        var name: String {
            switch self {
            case .excellent: "Excellent visibility"
            case .good: "Good visibility"
            case .moderate: "Moderate visibility"
            case .poor: "Poor visibility"
            }
        }

        /// Misty, watching from the window.
        var mistyLine: String {
            switch self {
            case .excellent: "Misty can see the whole street"
            case .good: "Misty can see down the block"
            case .moderate: "The end of the street looks fuzzy"
            case .poor: "Misty can't see past the garden"
            }
        }
    }

    /// OpenWeather reports visibility up to 10 km and no further, so 10 km means "at least 10 km".
    static func visibilityBand(meters: Int) -> VisibilityBand {
        switch meters {
        case 10_000...: .excellent
        case 5_000...: .good
        case 1_000...: .moderate
        default: .poor
        }
    }

    private static let metersPerMile = 1609.344

    /// Visibility as a number to show beside its band, or nil at OpenWeather's 10 km cap, where
    /// "Excellent visibility" says it all (and 10 km would read as an odd 6.2 mi). Whole kilometres
    /// or miles, except under 1 km: tenths of a mile, or metres to the nearest 100.
    static func visibilityDistance(meters: Int, inMiles: Bool) -> String? {
        guard visibilityBand(meters: meters) != .excellent else { return nil }
        let miles = Double(meters) / metersPerMile
        if inMiles, meters < 1_000 {
            return String(format: "%.1f mi", max(1, (miles * 10).rounded()) / 10)
        }
        if inMiles {
            return "\(max(1, Int(miles.rounded()))) mi"
        }
        if meters < 1_000 {
            return "\(max(1, Int((Double(meters) / 100).rounded())) * 100) m"
        }
        return "\(Int((Double(meters) / 1_000).rounded())) km"
    }

    /// The Sky tile's word for the sky.
    enum SkyCondition: String, Equatable {
        case clear = "Clear"
        case partlyCloudy = "Partly cloudy"
        case mostlyCloudy = "Mostly cloudy"
        case overcast = "Overcast"
        case mist = "Mist"
        case haze = "Hazy"
        case fog = "Fog"
        case smoke = "Smoky"
        case dust = "Dusty"
    }

    /// Mist, haze, fog, smoke and dust come from OpenWeather's condition group, since they are what
    /// limits the view; otherwise the cloud cover decides. Without a cloud cover (the forecast
    /// standing in for an old reading has none), the icon's cloud level decides instead.
    static func skyCondition(conditionMain: String, cloudPercent: Int?, iconCode: String) -> SkyCondition {
        switch conditionMain.lowercased() {
        case "mist": return .mist
        case "haze": return .haze
        case "fog": return .fog
        case "smoke", "ash": return .smoke
        case "dust", "sand": return .dust
        default: break
        }
        guard let cloudPercent else {
            switch iconCode.prefix(2) {
            case "01": return .clear
            case "02": return .partlyCloudy
            case "03": return .mostlyCloudy
            default: return .overcast
            }
        }
        switch cloudPercent {
        case ...10: return .clear
        case ...50: return .partlyCloudy
        case ...84: return .mostlyCloudy
        default: return .overcast
        }
    }

    /// What the pavement means for paws, from the Remote Config thresholds the walk advice uses.
    /// `pavementOK` is pavement that's fine while the air itself is too hot or too cold for paws, so
    /// the tile doesn't call it "Safe for paws" beside a walk card saying the opposite.
    enum PavementBand: Equatable {
        case dangerous, tooHot, warm, safe, pavementOK, freezing, icy

        var line: String {
            switch self {
            case .dangerous: "Dangerously hot"
            case .tooHot: "Too hot for paws"
            case .warm: "Getting hot"
            case .safe: "Safe for paws"
            case .pavementOK: "Fine underfoot"
            case .freezing: "Below freezing"
            case .icy: "Icy, watch for salt"
            }
        }
    }

    /// Below freezing it's only `.icy` after rain or snow (`groundWet`); dry, it's just cold.
    /// `feelsLikeC` is the air's feels-like temperature, compared with the pets' hot and cold limits.
    static func pavementBand(
        pavementC: Double,
        groundWet: Bool,
        feelsLikeC: Double,
        thresholds: PetWeatherThresholds
    ) -> PavementBand {
        if pavementC >= thresholds.dangerousPavementC { return .dangerous }
        if pavementC >= thresholds.hotPavementC { return .tooHot }
        if pavementC >= thresholds.warmPavementC { return .warm }
        if pavementC < thresholds.icyPavementC { return groundWet ? .icy : .freezing }
        if feelsLikeC >= thresholds.petHotC || feelsLikeC <= thresholds.petColdC { return .pavementOK }
        return .safe
    }

    /// Joins each number to its unit with a no-break space, so large text never leaves "°F", "mph" or
    /// "PM" stranded on a line of its own. The time formatter's narrow no-break space before AM/PM is
    /// replaced too, since SwiftUI still wraps at it.
    static func keepUnitsTogether(_ text: String) -> String {
        text.replacing(/(\d)[ \u{202F}](?=°|%|mph\b|m\/s|km\b|mi\b|m\b|AM\b|PM\b)/) { "\($0.1)\u{00A0}" }
    }

    private static let spokenCompassPoints = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]

    /// The compass point a wind comes from, as a word, for VoiceOver: the Wind tile shows it only as an
    /// arrow.
    static func spokenCompassPoint(_ deg: Int) -> String {
        spokenCompassPoints[((deg + 22) / 45) % 8]
    }

    /// Dew point in Celsius (Magnus formula); nil when the humidity is 0, where it's undefined.
    static func dewPointC(temperatureC: Double, humidityPercent: Int) -> Double? {
        guard humidityPercent > 0 else { return nil }
        let a = 17.62
        let b = 243.12
        let gamma = log(Double(min(humidityPercent, 100)) / 100) + a * temperatureC / (b + temperatureC)
        return b * gamma / (a - gamma)
    }

    /// The Beaufort scale's names, which the Wind tile shows under the speed.
    static let windForceNames = [
        "Calm", "Light wind", "Light breeze", "Gentle breeze", "Moderate breeze", "Fresh breeze", "Strong breeze",
        "Near gale", "Gale", "Strong gale", "Storm", "Violent storm", "Hurricane force",
    ]

    /// The WMO upper bounds of each force, in m/s.
    private static let beaufortUpperBounds = [0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7]
    private static let metersPerSecondPerMph = 0.44704

    /// 0 (calm) to 12 (hurricane force).
    static func windForce(speed: Double, units: WeatherUnits) -> Int {
        let metersPerSecond = units == .imperial ? speed * metersPerSecondPerMph : speed
        return beaufortUpperBounds.firstIndex { metersPerSecond < $0 } ?? beaufortUpperBounds.count
    }

    /// Where the day is between sunrise and sunset, for the Daylight tile's arc.
    enum Daylight: Equatable {
        case beforeSunrise(secondsUntil: Int)
        /// `fraction` is 0 at sunrise and 1 at sunset.
        case daytime(secondsLeft: Int, fraction: Double)
        case afterSunset
    }

    static func daylight(now: Int, sunrise: Int, sunset: Int) -> Daylight {
        if now < sunrise { return .beforeSunrise(secondsUntil: sunrise - now) }
        if now >= sunset || sunset <= sunrise { return .afterSunset }
        return .daytime(secondsLeft: sunset - now, fraction: Double(now - sunrise) / Double(sunset - sunrise))
    }

    /// "2 h 15 min", "2 h" or "45 min".
    static func duration(seconds: Int) -> String {
        let totalMinutes = seconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) h" }
        return "\(hours) h \(minutes) min"
    }

    /// Today's high and low for the hero. OpenWeather's current reading has its own min and max,
    /// but they're the spread across nearby stations right now, not the day's, so today's forecast
    /// is used whenever there is one, widened to take in the temperature now.
    static func highLow(current: CurrentWeather, today: DayForecast?) -> (high: Double, low: Double) {
        guard let today else { return (current.tempMax, current.tempMin) }
        return (max(today.tempMax, current.temperature), min(today.tempMin, current.temperature))
    }
}
