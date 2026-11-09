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
        guard let start = peak.date else { return (String(localized: "Peak \(rounded) today", comment: "UV Index tile line. The number is the UV index."), false) }
        if start > now { return (String(localized: "Peak \(rounded) at \(peak.timeLabel)", comment: "UV Index tile line. The number is the UV index."), false) }
        if hasDog, rounded >= 6 { return (String(localized: "Shade for pale noses", comment: "UV Index tile line. The number is the UV index."), true) }
        return start.addingTimeInterval(60 * 60) > now ? (String(localized: "At today's peak", comment: "UV Index tile line. The number is the UV index."), false) : (String(localized: "Easing off now", comment: "UV Index tile line. The number is the UV index."), false)
    }

    /// How far you can see, in the bands Misty's View names.
    enum VisibilityBand: Equatable {
        case excellent, good, moderate, poor

        var name: String {
            switch self {
            case .excellent: String(localized: "Excellent visibility", comment: "Visibility band on the Misty's View tile")
            case .good: String(localized: "Good visibility", comment: "Visibility band on the Misty's View tile")
            case .moderate: String(localized: "Moderate visibility", comment: "Visibility band on the Misty's View tile")
            case .poor: String(localized: "Poor visibility", comment: "Visibility band on the Misty's View tile")
            }
        }

        /// Misty, watching from the window.
        var mistyLine: String {
            switch self {
            case .excellent: String(localized: "Misty can see the whole street", comment: "Misty's line about how far she can see, on the Misty's View tile")
            case .good: String(localized: "Misty can see down the block", comment: "Misty's line about how far she can see, on the Misty's View tile")
            case .moderate: String(localized: "The end of the street looks fuzzy", comment: "Misty's line about how far she can see, on the Misty's View tile")
            case .poor: String(localized: "Misty can't see past the garden", comment: "Misty's line about how far she can see, on the Misty's View tile")
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
            let tenths = String(format: "%.1f", max(1, (miles * 10).rounded()) / 10)
            return String(localized: "\(tenths) mi", comment: "Visibility distance with its unit")
        }
        if inMiles {
            return String(localized: "\(max(1, Int(miles.rounded()))) mi", comment: "Visibility distance with its unit")
        }
        if meters < 1_000 {
            return String(localized: "\(max(1, Int((Double(meters) / 100).rounded())) * 100) m", comment: "Visibility distance with its unit")
        }
        return String(localized: "\(Int((Double(meters) / 1_000).rounded())) km", comment: "Visibility distance with its unit")
    }

    /// Misty's View's word for the sky.
    enum SkyCondition: Equatable {
        case clear, partlyCloudy, mostlyCloudy, overcast, mist, haze, fog, smoke, dust

        var name: String {
            switch self {
            case .clear: String(localized: "Clear", comment: "The sky on the Misty's View tile")
            case .partlyCloudy: String(localized: "Partly cloudy", comment: "The sky on the Misty's View tile")
            case .mostlyCloudy: String(localized: "Mostly cloudy", comment: "The sky on the Misty's View tile")
            case .overcast: String(localized: "Overcast", comment: "The sky on the Misty's View tile")
            case .mist: String(localized: "Mist", comment: "The sky on the Misty's View tile")
            case .haze: String(localized: "Hazy", comment: "The sky on the Misty's View tile")
            case .fog: String(localized: "Fog", comment: "The sky on the Misty's View tile")
            case .smoke: String(localized: "Smoky", comment: "The sky on the Misty's View tile")
            case .dust: String(localized: "Dusty", comment: "The sky on the Misty's View tile")
            }
        }
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
            case .dangerous: String(localized: "Dangerously hot", comment: "Paw Check tile line: what the pavement means for paws")
            case .tooHot: String(localized: "Too hot for paws", comment: "Paw Check tile line: what the pavement means for paws")
            case .warm: String(localized: "Getting hot", comment: "Paw Check tile line: what the pavement means for paws")
            case .safe: String(localized: "Safe for paws", comment: "Paw Check tile line: what the pavement means for paws")
            case .pavementOK: String(localized: "Fine underfoot", comment: "Paw Check tile line: what the pavement means for paws")
            case .freezing: String(localized: "Below freezing", comment: "Paw Check tile line: what the pavement means for paws")
            case .icy: String(localized: "Icy, watch for salt", comment: "Paw Check tile line: what the pavement means for paws")
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
            case .cold: String(localized: "Cold", comment: "Feels Like band name")
            case .chilly: String(localized: "Chilly", comment: "Feels Like band name")
            case .mild: String(localized: "Mild", comment: "Feels Like band name")
            case .warm: String(localized: "Warm", comment: "Feels Like band name")
            case .hot: String(localized: "Hot", comment: "Feels Like band name")
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
        if abs(gap) <= 1 { return String(localized: "Same as it is", comment: "Feels Like tile: how far it feels from the actual temperature") }
        return gap > 0 ? String(localized: "\(gap)° warmer than it is", comment: "Feels Like tile: how far it feels from the actual temperature") : String(localized: "\(-gap)° cooler than it is", comment: "Feels Like tile: how far it feels from the actual temperature")
    }

    /// Joins each number to its unit with a no-break space, so large text never leaves "°F", "mph" or
    /// "PM" stranded on a line of its own. The time formatter's narrow no-break space before AM/PM is
    /// replaced too, since SwiftUI still wraps at it.
    static func keepUnitsTogether(_ text: String) -> String {
        text.replacing(/(\d)[ \u{202F}](?=°|%|mph\b|m\/s|km\b|mi\b|m\b|AM\b|PM\b)/) { "\($0.1)\u{00A0}" }
    }

    private static let spokenCompassPoints = [String(localized: "north", comment: "Compass point a wind comes from, spoken by VoiceOver"), String(localized: "northeast", comment: "Compass point a wind comes from, spoken by VoiceOver"), String(localized: "east", comment: "Compass point a wind comes from, spoken by VoiceOver"), String(localized: "southeast", comment: "Compass point a wind comes from, spoken by VoiceOver"), String(localized: "south", comment: "Compass point a wind comes from, spoken by VoiceOver"), String(localized: "southwest", comment: "Compass point a wind comes from, spoken by VoiceOver"), String(localized: "west", comment: "Compass point a wind comes from, spoken by VoiceOver"), String(localized: "northwest", comment: "Compass point a wind comes from, spoken by VoiceOver")]

    private static let compassPoints = [String(localized: "N", comment: "Compass point abbreviation a wind comes from, on the Wind tile"), String(localized: "NE", comment: "Compass point abbreviation a wind comes from, on the Wind tile"), String(localized: "E", comment: "Compass point abbreviation a wind comes from, on the Wind tile"), String(localized: "SE", comment: "Compass point abbreviation a wind comes from, on the Wind tile"), String(localized: "S", comment: "Compass point abbreviation a wind comes from, on the Wind tile"), String(localized: "SW", comment: "Compass point abbreviation a wind comes from, on the Wind tile"), String(localized: "W", comment: "Compass point abbreviation a wind comes from, on the Wind tile"), String(localized: "NW", comment: "Compass point abbreviation a wind comes from, on the Wind tile")]

    /// The compass point a wind comes from, as a word, for VoiceOver.
    static func spokenCompassPoint(_ deg: Int) -> String {
        spokenCompassPoints[((deg + 22) / 45) % 8]
    }

    /// The Fluff Factor tile's bands. Misty's fur goes from sleek to full floof, with static sparks
    /// in dry air. Same bands as Android's `FluffLevel`.
    enum FluffLevel: Int, CaseIterable, Equatable {
        case dry, comfy, sticky, muggy, soupy
    }

    /// Mugginess goes by the dew point (humidity alone rises and falls with the temperature): sticky
    /// from 16 °C (61 °F), muggy from 18 °C (64 °F), soupy from 21 °C (70 °F). Below that, the air
    /// is dry under 35% humidity, when fur crackles with static, and comfy otherwise (cool, damp air
    /// included). No dew point means 0% humidity.
    static func fluffLevel(dewPointC: Double?, humidityPercent: Int) -> FluffLevel {
        guard let dewPointC else { return .dry }
        return switch dewPointC {
        case 21...: .soupy
        case 18...: .muggy
        case 16...: .sticky
        default: humidityPercent < dryBelowPercent ? .dry : .comfy
        }
    }

    private static let dryBelowPercent = 35

    /// Misty's line on the Fluff Factor tile. Muggy air matters most to a dog, which cools down by
    /// panting, so with a dog that band says so.
    static func fluffLine(_ level: FluffLevel, hasDog: Bool) -> String {
        switch level {
        case .dry: String(localized: "Dry air, static fur", comment: "Fluff Factor tile line about humidity, in Misty's voice")
        case .comfy: String(localized: "Misty's fur is behaving", comment: "Fluff Factor tile line about humidity, in Misty's voice")
        case .sticky: String(localized: "Misty's fluffing up", comment: "Fluff Factor tile line about humidity, in Misty's voice")
        case .muggy: hasDog ? String(localized: "Puffy fur, panting pup", comment: "Fluff Factor tile line about humidity, in Misty's voice") : String(localized: "Misty's getting puffy", comment: "Fluff Factor tile line about humidity, in Misty's voice")
        case .soupy: String(localized: "Misty has gone full floof", comment: "Fluff Factor tile line about humidity, in Misty's voice")
        }
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
        if force == 0 || WeatherFormatting.isCalm(speed, units: units) { return (String(localized: "Calm", comment: "Beaufort wind force name on the Wind tile, also its note when there is no wind"), String(localized: "Calm", comment: "Beaufort wind force name on the Wind tile, also its note when there is no wind")) }
        let toMetersPerSecond = units == .imperial ? metersPerSecondPerMph : 1
        let point = compassPoint(deg)
        let spokenPoint = spokenCompassPoint(deg)
        let forceName = windForceNames[force].lowercased()
        if let gust, (gust - speed) * toMetersPerSecond >= gustGapMetersPerSecond {
            let formatted = WeatherFormatting.wind(gust, units: units)
            let gustNumber = formatted.split(separator: " ").first.map(String.init) ?? formatted
            return (
                String(localized: "From the \(point), gusts \(gustNumber)", comment: "Wind tile note: where the wind comes from (a compass point) and the gust speed, without its unit"),
                String(localized: "From the \(spokenPoint), \(forceName), gusts \(formatted)", comment: "Spoken by VoiceOver: where the wind comes from, the wind force name (lower case) and the gust speed")
            )
        }
        return (
            String(localized: "From the \(point)", comment: "Wind tile note: where the wind comes from, a compass point"),
            String(localized: "From the \(spokenPoint), \(forceName)", comment: "Spoken by VoiceOver: where the wind comes from and the wind force name (lower case)")
        )
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
        String(localized: "Calm", comment: "Beaufort wind force name on the Wind tile, also its note when there is no wind"), String(localized: "Light wind", comment: "Beaufort wind force name on the Wind tile"), String(localized: "Light breeze", comment: "Beaufort wind force name on the Wind tile"), String(localized: "Gentle breeze", comment: "Beaufort wind force name on the Wind tile"), String(localized: "Moderate breeze", comment: "Beaufort wind force name on the Wind tile"), String(localized: "Fresh breeze", comment: "Beaufort wind force name on the Wind tile"), String(localized: "Strong breeze", comment: "Beaufort wind force name on the Wind tile"),
        String(localized: "Near gale", comment: "Beaufort wind force name on the Wind tile"), String(localized: "Gale", comment: "Beaufort wind force name on the Wind tile"), String(localized: "Strong gale", comment: "Beaufort wind force name on the Wind tile"), String(localized: "Storm", comment: "Beaufort wind force name on the Wind tile"), String(localized: "Violent storm", comment: "Beaufort wind force name on the Wind tile"), String(localized: "Hurricane force", comment: "Beaufort wind force name on the Wind tile"),
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
        if hours == 0 { return String(localized: "\(minutes) min", comment: "Duration in hours and minutes, abbreviated") }
        if minutes == 0 { return String(localized: "\(hours) h", comment: "Duration in hours and minutes, abbreviated") }
        return String(localized: "\(hours) h \(minutes) min", comment: "Duration in hours and minutes, abbreviated")
    }

    /// Today's high and low for the hero. OpenWeather's current reading has its own min and max,
    /// but they're the spread across nearby stations right now, not the day's, so today's forecast
    /// is used whenever there is one, widened to take in the temperature now.
    static func highLow(current: CurrentWeather, today: DayForecast?) -> (high: Double, low: Double) {
        guard let today else { return (current.tempMax, current.tempMin) }
        return highLow(temperature: current.temperature, today: today)
    }

    /// `today`'s forecast high and low, widened to take in `temperature` (the temperature now, or
    /// at the hour a briefing is for). The hero and the morning briefing both give these.
    static func highLow(temperature: Double, today: DayForecast) -> (high: Double, low: Double) {
        (max(today.tempMax, temperature), min(today.tempMin, temperature))
    }
}
