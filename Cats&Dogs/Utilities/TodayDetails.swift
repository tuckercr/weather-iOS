import Foundation

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

/// The rules behind the Today tiles, kept out of the views so they can be tested. Same rules as
/// Android's `util/TodayDetails.kt`.
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

        /// Which of the Paw Check tile's five paws this is, 0 (icy) to 4 (dangerous). Icy and below
        /// freezing share the first, safe and fine underfoot the second.
        var pawScaleStep: Int {
            switch self {
            case .freezing, .icy: 0
            case .safe, .pavementOK: 1
            case .warm: 2
            case .tooHot: 3
            case .dangerous: 4
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

    /// The Feels Like tile's band, from the Remote Config limits behind the pets' moods and the walk
    /// advice: Hot and Cold where the pets are hot and cold, Mild across the walk comfort range, and
    /// Chilly and Warm between.
    enum FeelsLikeBand: Int, CaseIterable, Equatable {
        case cold, chilly, mild, warm, hot

        var name: String {
            switch self {
            case .cold: "Cold"
            case .chilly: "Chilly"
            case .mild: "Mild"
            case .warm: "Warm"
            case .hot: "Hot"
            }
        }
    }

    static func feelsLikeBand(feelsLikeC: Double, thresholds: PetWeatherThresholds) -> FeelsLikeBand {
        if feelsLikeC >= thresholds.petHotC { return .hot }
        if feelsLikeC <= thresholds.petColdC { return .cold }
        if feelsLikeC < thresholds.comfortC.lowerBound { return .chilly }
        if feelsLikeC <= thresholds.comfortC.upperBound { return .mild }
        return .warm
    }

    /// How far the Cold and Hot bands reach past the pets' limits on the Feels Like bar.
    static let feelsLikeEndBandC = 10.0

    /// Where the Feels Like bar's mark sits, 0 to 1: five bands of equal width, with the reading
    /// placed within its own. The end bands reach `feelsLikeEndBandC` past the pets' limits (-10 and
    /// 40 C with the standard thresholds), and the mark stays at the end beyond them.
    static func feelsLikeBarPosition(feelsLikeC: Double, thresholds: PetWeatherThresholds) -> Double {
        let band = feelsLikeBand(feelsLikeC: feelsLikeC, thresholds: thresholds)
        // Remote Config validates each limit, but the comfort range may still reach past the pets'
        // limits, so its edges are kept between them.
        let cold = thresholds.petColdC
        let hot = max(thresholds.petHotC, cold)
        let comfortLow = min(max(thresholds.comfortC.lowerBound, cold), hot)
        let comfortHigh = min(max(thresholds.comfortC.upperBound, comfortLow), hot)
        let (low, high): (Double, Double) = switch band {
        case .cold: (cold - feelsLikeEndBandC, cold)
        case .chilly: (cold, comfortLow)
        case .mild: (comfortLow, comfortHigh)
        case .warm: (comfortHigh, hot)
        case .hot: (hot, hot + feelsLikeEndBandC)
        }
        let within = high > low ? min(max((feelsLikeC - low) / (high - low), 0), 1) : 0.5
        return (Double(band.rawValue) + within) / Double(FeelsLikeBand.allCases.count)
    }

    /// The Feels Like tile's last line: how far it feels from the actual temperature, from the two
    /// as shown (whole degrees), so it agrees with the hero. A degree or less either way is the same.
    /// No unit: the number above carries it, and the line has to fit beside a half-width tile's edge.
    static func feelsLikeGap(feelsLike: Double, temperature: Double) -> String {
        let gap = Int(feelsLike.rounded()) - Int(temperature.rounded())
        if abs(gap) <= 1 { return "Same as it is" }
        return gap > 0 ? "\(gap)° warmer than it is" : "\(-gap)° cooler than it is"
    }

    /// Joins each number to its unit with a no-break space, so large text never leaves "°F", "mph" or
    /// "PM" stranded on a line of its own. The time formatter's narrow no-break space before AM/PM is
    /// replaced too, since SwiftUI still wraps at it.
    static func keepUnitsTogether(_ text: String) -> String {
        text.replacing(/(\d)[ \u{202F}](?=°|%|mph\b|m\/s|km\b|mi\b|m\b|AM\b|PM\b)/) { "\($0.1)\u{00A0}" }
    }

    private static let spokenCompassPoints = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]

    private static let compassPoints = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// The compass point a wind comes from, as a word, for VoiceOver.
    static func spokenCompassPoint(_ deg: Int) -> String {
        spokenCompassPoints[((deg + 22) / 45) % 8]
    }

    /// The compass point a wind comes from, for the Wind tile: "SW".
    static func compassPoint(_ deg: Int) -> String {
        compassPoints[((deg + 22) / 45) % 8]
    }

    /// The windsock's droop below the horizontal: limp (75°) when calm, lifting steadily until it
    /// flies straight out from a strong breeze (Beaufort 6, 10.8 m/s or 24 mph).
    static func windsockDroopDegrees(speed: Double, units: WeatherUnits) -> Double {
        let metersPerSecond = units == .imperial ? speed * metersPerSecondPerMph : speed
        return windsockLimpDegrees * (1 - min(max(metersPerSecond / windsockStraightMetersPerSecond, 0), 1))
    }

    static let windsockLimpDegrees = 75.0
    private static let windsockStraightMetersPerSecond = 10.8

    /// Gusts are mentioned when they're at least this much stronger than the wind (5 mph).
    private static let gustGapMetersPerSecond = 2.2

    /// The Wind tile's note, with what VoiceOver says. The windsock shows how strong the wind is, so
    /// the note gives where it comes from, and gusts that stand out: "From the SW, gusts 24".
    static func windNote(speed: Double, deg: Int, gust: Double?, units: WeatherUnits) -> (text: String, spoken: String) {
        let force = windForce(speed: speed, units: units)
        if force == 0 || WeatherFormatting.isCalm(speed, units: units) { return ("Calm", "Calm") }
        let toMetersPerSecond = units == .imperial ? metersPerSecondPerMph : 1
        var text = "From the \(compassPoint(deg))"
        var spoken = "From the \(spokenCompassPoint(deg)), \(windForceNames[force].lowercased())"
        if let gust, (gust - speed) * toMetersPerSecond >= gustGapMetersPerSecond {
            let formatted = WeatherFormatting.wind(gust, units: units)
            text += ", gusts \(formatted.split(separator: " ").first.map(String.init) ?? formatted)"
            spoken += ", gusts \(formatted)"
        }
        return (text, spoken)
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
