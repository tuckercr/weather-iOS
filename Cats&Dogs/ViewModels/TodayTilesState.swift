import Foundation

/// The Today tiles with everything they show worked out: which tiles there are and in what order,
/// and each one's value, band and line. `TodayTiles` only lays them out and colours them. Built
/// with the screen state. Same as Android's `TodayTilesState`.
@MainActor
struct TodayTilesState {
    /// The small tiles, in order: feels like, wind, Fluff Factor, Paw Check, UV and air quality, as
    /// shown. They go in pairs, an odd one out across the full width.
    let small: [TodayTile]
    let daylight: DaylightTile?
    let sky: SkyTile?

    init(
        weather: CurrentWeather,
        showingForecast: Bool,
        pavementNow: Double?,
        groundWet: Bool,
        uvIndex: Double?,
        uvPeak: HourlySlot?,
        airQuality: AirQuality?,
        hasDog: Bool,
        now: Date,
        thresholds: PetWeatherThresholds,
        distanceInMiles: Bool,
        switches: TodayTileSwitches
    ) {
        let daylight: DaylightTile? = if switches.daylight, let sunrise = weather.sunriseEpoch, let sunset = weather.sunsetEpoch {
            DaylightTile(sunrise: sunrise, sunset: sunset, timeZone: weather.timeZone, now: now)
        } else {
            nil
        }
        // UV gets its own tile when switched on, or when there's no Daylight tile to carry it.
        let uvTile = uvIndex != nil && (switches.uv || daylight == nil)

        var small: [TodayTile] = []
        if switches.feelsLike { small.append(.feelsLike(FeelsLikeTile(weather: weather, thresholds: thresholds))) }
        if switches.wind { small.append(.wind(WindTile(weather: weather))) }
        if switches.humidity { small.append(.fluff(FluffTile(weather: weather, hasDog: hasDog))) }
        if switches.pawCheck, let pavementNow {
            small.append(.pawCheck(PawCheckTile(pavement: pavementNow, weather: weather, groundWet: groundWet, thresholds: thresholds)))
        }
        if uvTile, let uvIndex { small.append(.uv(UVTile(uv: uvIndex, peak: uvPeak, now: now, hasDog: hasDog))) }
        if let airQuality { small.append(.air(AirTile(air: airQuality, hasDog: hasDog, thresholds: thresholds))) }
        self.small = small
        self.daylight = daylight.map { tile in
            var tile = tile
            // Without a UV tile, Daylight carries the UV index.
            if !uvTile, let uvIndex { tile.uvNote = String(localized: "UV \(Int(uvIndex.rounded())) · \(WeatherFormatting.uvLevel(uvIndex))", comment: "Daylight tile: the UV index and its category") }
            return tile
        }
        sky = switches.sky ? SkyTile(weather: weather, showingForecast: showingForecast, distanceInMiles: distanceInMiles, now: now) : nil
    }
}

enum TodayTile {
    case feelsLike(FeelsLikeTile)
    case wind(WindTile)
    case fluff(FluffTile)
    case pawCheck(PawCheckTile)
    case uv(UVTile)
    case air(AirTile)
}

/// The feels-like temperature with its band ("Hot"), where it sits on the band bar, and how far it
/// is from the actual temperature.
struct FeelsLikeTile {
    let value: String
    let band: TodayDetails.FeelsLikeBand
    let barPosition: Double
    let note: String

    init(weather: CurrentWeather, thresholds: PetWeatherThresholds) {
        let feelsLikeC = weather.units.toCelsius(weather.feelsLike)
        value = WeatherFormatting.temperature(weather.feelsLike, units: weather.units)
        band = TodayDetails.feelsLikeBand(feelsLikeC: feelsLikeC, thresholds: thresholds)
        barPosition = TodayDetails.feelsLikeBarPosition(feelsLikeC: feelsLikeC, thresholds: thresholds)
        note = TodayDetails.feelsLikeGap(feelsLike: weather.feelsLike, temperature: weather.temperature)
    }
}

/// The speed, the windsock's droop for its strength, and where it comes from with any gusts.
struct WindTile {
    let value: String
    let droopDegrees: Double
    let note: String
    let spokenNote: String

    init(weather: CurrentWeather) {
        value = WeatherFormatting.wind(weather.windSpeed, units: weather.units)
        droopDegrees = TodayDetails.windsockDroopDegrees(speed: weather.windSpeed, units: weather.units)
        let note = TodayDetails.windNote(speed: weather.windSpeed, deg: weather.windDeg, gust: weather.windGust, units: weather.units)
        self.note = note.text
        spokenNote = note.spoken
    }
}

/// Fluff Factor: the humidity, the dew point, how fluffed up Misty is, and her line about it.
struct FluffTile {
    let humidityPercent: Int
    /// "Dew point 54°"; nil when it can't be worked out.
    let dewPoint: String?
    let level: TodayDetails.FluffLevel
    let line: String

    init(weather: CurrentWeather, hasDog: Bool) {
        let dewC = TodayDetails.dewPointC(
            temperatureC: weather.units.toCelsius(weather.temperature),
            humidityPercent: weather.humidityPercent
        )
        humidityPercent = weather.humidityPercent
        dewPoint = dewC.map {
            String(localized: "Dew point \(WeatherFormatting.temperature(weather.units.fromCelsius($0), units: weather.units, showsUnit: false))", comment: "Fluff Factor tile: the dew point temperature")
        }
        level = TodayDetails.fluffLevel(dewPointC: dewC, humidityPercent: weather.humidityPercent)
        line = TodayDetails.fluffLine(level, hasDog: hasDog)
    }
}

/// Paw Check: the pavement estimate ("About 128°") and its band, which picks the paw and the line.
struct PawCheckTile {
    let value: String
    let band: TodayDetails.PavementBand

    init(pavement: Double, weather: CurrentWeather, groundWet: Bool, thresholds: PetWeatherThresholds) {
        // An estimate for dark asphalt in direct sun, so a whole number, and said to be one.
        value = String(localized: "About \(WeatherFormatting.temperature(pavement, units: weather.units))", comment: "Paw Check tile: estimated pavement temperature")
        band = TodayDetails.pavementBand(
            pavementC: weather.units.toCelsius(pavement),
            groundWet: groundWet,
            feelsLikeC: weather.units.toCelsius(weather.feelsLike),
            thresholds: thresholds
        )
    }
}

/// The UV index, its WHO level, and the peak or a line for pale-nosed dogs.
struct UVTile {
    let value: Int
    let level: String
    /// Empty when there's nothing to say.
    let line: String
    /// The dog's line, which takes the pets' colour.
    let isPetLine: Bool

    init(uv: Double, peak: HourlySlot?, now: Date, hasDog: Bool) {
        value = Int(uv.rounded())
        level = WeatherFormatting.uvLevel(uv)
        let line = TodayDetails.uvLine(peak: peak, now: now, hasDog: hasDog)
        self.line = line.text
        isPetLine = line.isPetLine
    }
}

/// The air quality index, its band, the line for walks (or people without a dog), and how it reads.
struct AirTile {
    enum Tone { case good, soSo, bad }

    let index: Int
    let bandName: String
    let barPosition: Double
    let line: String
    /// The pollutant behind it and the line, for VoiceOver.
    let spokenLine: String
    /// Bad where the walk rules say potty breaks only, or without a dog (whose line goes by band)
    /// from Unhealthy up; good in the first band.
    let tone: Tone

    init(air: AirQuality, hasDog: Bool, thresholds: PetWeatherThresholds) {
        index = air.index
        bandName = air.bandName
        barPosition = air.barPosition
        line = air.line(hasDog: hasDog, thresholds: thresholds)
        spokenLine = [air.pollutantLine, line].compactMap(\.self).joined(separator: ". ")
        let bad = hasDog ? WalkConditions.airLevel(band: air.band, thresholds) >= .pottyOnly : air.band >= 3
        tone = bad ? .bad : air.band == 0 ? .good : .soSo
    }
}

/// Daylight: where the day is between sunrise and sunset, and what's left of it.
struct DaylightTile {
    /// 0 at sunrise, 1 at sunset.
    let fraction: Double
    let isUp: Bool
    let summary: String
    let sunrise: String
    let sunset: String
    /// "UV 6 · High" when UV has no tile of its own.
    var uvNote: String?

    init(sunrise: Int, sunset: Int, timeZone: TimeZone, now: Date) {
        switch TodayDetails.daylight(now: Int(now.timeIntervalSince1970), sunrise: sunrise, sunset: sunset) {
        case .beforeSunrise(let secondsUntil):
            fraction = 0
            isUp = false
            summary = String(localized: "Sunrise in \(TodayDetails.duration(seconds: secondsUntil))", comment: "Daylight tile summary. The argument is a duration.")
        case .daytime(let secondsLeft, let dayFraction):
            fraction = dayFraction
            isUp = true
            summary = String(localized: "\(TodayDetails.duration(seconds: secondsLeft)) left", comment: "Daylight tile summary. The argument is a duration.")
        case .afterSunset:
            fraction = 1
            isUp = false
            summary = String(localized: "The sun has set", comment: "Daylight tile summary")
        }
        self.sunrise = WeatherFormatting.epochTime(sunrise, timeZone: timeZone)
        self.sunset = WeatherFormatting.epochTime(sunset, timeZone: timeZone)
    }
}

/// Misty's View: the sky and how far she can see, and her line about it. After dark the line is
/// about the streetlights and the stars instead (`TodayDetails.mistyNightLine`).
struct SkyTile {
    let headline: String
    let mistyLine: String?

    init(weather: CurrentWeather, showingForecast: Bool, distanceInMiles: Bool, now: Date) {
        // A forecast hour standing in for the reading has no cloud cover or visibility.
        let sky = TodayDetails.skyCondition(
            conditionMain: weather.conditionMain,
            cloudPercent: showingForecast ? nil : weather.cloudPercent,
            iconCode: weather.iconCode
        )
        let visibility = showingForecast ? nil : weather.visibilityMeters
        let band = visibility.map { TodayDetails.visibilityBand(meters: $0) }
        let headline: String = if let visibility, let band {
            if let distance = TodayDetails.visibilityDistance(meters: visibility, inMiles: distanceInMiles) {
                String(localized: "\(sky.name) · \(band.name), \(distance)", comment: "Misty's View tile headline: the sky, how far you can see and the distance")
            } else {
                String(localized: "\(sky.name) · \(band.name)", comment: "Misty's View tile headline: the sky and how far you can see")
            }
        } else {
            sky.name
        }
        self.headline = TodayDetails.keepUnitsTogether(headline)
        // Dark by today's sun times in the city, as the rest of the screen goes by.
        let dark = StaleWeather.isDark(StaleWeather.withSunTimesToday(weather, at: now), at: now)
        mistyLine = band.map { dark ? TodayDetails.mistyNightLine(band: $0, sky: sky) : $0.mistyLine }
    }
}
