import Foundation

/// The Remote Config switches and settings the weather screen goes by, read once per update.
@MainActor
struct WeatherScreenConfig {
    var thresholds = PetWeatherThresholds.standard
    var seasonalThemes: [SeasonalTheme] = []
    var nextRainEnabled = true
    var rainOutlookEnabled = true
    var rainOutlookHours = RemoteConfigRepository.defaultRainOutlookHours
    var rainOutlookMinChance = RemoteConfigRepository.defaultRainOutlookMinChance
    var airQualityEnabled = true
    var hourlyForecastEnabled = true
    var radarEnabled = true
    var weekForecastEnabled = true
    var walkCardEnabled = true
    var todayTiles = TodayTileSwitches()
    /// Visibility in miles rather than kilometres: the user's units, not Remote Config's.
    var distanceInMiles = false

    static var live: WeatherScreenConfig {
        let config = RemoteConfigRepository.shared
        return WeatherScreenConfig(
            thresholds: config.petWeatherThresholds,
            seasonalThemes: config.seasonalThemes,
            nextRainEnabled: config.nextRainEnabled,
            rainOutlookEnabled: config.rainOutlookEnabled,
            rainOutlookHours: config.rainOutlookHours,
            rainOutlookMinChance: config.rainOutlookMinChance,
            airQualityEnabled: RemoteConfigRepository.airQualityEnabled,
            hourlyForecastEnabled: config.hourlyForecastEnabled,
            radarEnabled: config.radarEnabled,
            weekForecastEnabled: config.weekForecastEnabled,
            walkCardEnabled: config.walkCardEnabled,
            todayTiles: config.todayTiles
        )
    }
}

/// What the weather screen shows for the active city, worked out by `WeatherForecastViewModel`
/// from the reading, the forecast, its clock and the settings. The view only draws it.
@MainActor
enum WeatherScreen {
    case loading
    /// Nothing to show as now: no reading at all, or the cached one too old to show with no
    /// forecast hour to stand in for it. `lastUpdated` says when that old reading was taken.
    case error(errorKey: String, canRetry: Bool, lastUpdated: String? = nil)
    case weather(WeatherScreenState)

    /// Past the cutoff, an old reading isn't shown as now: the cached forecast's current hour stands
    /// in for it, or the error if the forecast doesn't cover now.
    static func make(
        current: LoadingState<CurrentWeather>,
        forecast: LoadingState<[DayForecast]>,
        staleErrorKey: String?,
        now: Date,
        hasDog: Bool,
        config: WeatherScreenConfig
    ) -> WeatherScreen {
        switch current {
        case .idle, .loading:
            return .loading
        case let .error(errorKey, canRetry):
            return .error(errorKey: errorKey, canRetry: canRetry)
        case let .success(reading):
            let tooOld = staleErrorKey != nil && StaleWeather.isTooOldToShowAsNow(reading, now: now)
            let forecastNow = tooOld
                ? forecast.successValue.flatMap { StaleWeather.forecastAsCurrent(reading, forecast: $0, now: now) }
                : nil
            if tooOld, forecastNow == nil {
                return .error(
                    errorKey: staleErrorKey ?? "generic",
                    canRetry: true,
                    lastUpdated: StaleWeather.readingTime(reading, now: now)
                )
            }
            return .weather(WeatherScreenState(
                weather: forecastNow ?? reading,
                showingForecast: forecastNow != nil,
                stale: staleErrorKey.map { WeatherScreenState.Stale(reading: reading, errorKey: $0) },
                forecast: forecast,
                now: now,
                hasDog: hasDog,
                config: config
            ))
        }
    }
}

/// Everything the weather screen shows for a reading, worked out in one place.
@MainActor
struct WeatherScreenState {
    /// The old reading behind the "showing weather from..." banner, and why the refresh failed.
    struct Stale {
        let reading: CurrentWeather
        let errorKey: String
    }

    /// What the Today tiles are given beside the reading.
    struct Tiles {
        /// The hour in progress's pavement estimate, in the reading's units; nil without a dog.
        let pavementNow: Double?
        /// Rain or snow lately, or now: below freezing the pavement may be icy.
        let groundWet: Bool
        /// The hour's UV index, only in the daytime (it's always 0 after dark).
        let uvIndex: Double?
        /// Today's hour with the highest UV, for the UV tile's peak.
        let uvPeak: HourlySlot?
        /// The hour's air quality; nil while air quality is switched off.
        let airQuality: AirQuality?
    }

    /// The rest of the week below the radar: its days, or the forecast loading or failed.
    enum Week {
        case days([DayForecast])
        case loading
        case error(errorKey: String, canRetry: Bool)
    }

    /// The screen's clock when this was worked out.
    let now: Date
    /// The reading shown as now: the latest, or the cached forecast's hour standing in for one
    /// too old to show.
    let weather: CurrentWeather
    /// True when `weather` is that forecast hour: there's no cloud cover or visibility to show.
    let showingForecast: Bool
    /// Set while refreshes are failing and the cached reading is on screen.
    let stale: Stale?
    let hasDog: Bool
    /// `weather` with today's sunrise and sunset, for a reading cached on an earlier day, so the
    /// Daylight tile and the walk card follow the clock as the hero does.
    let weatherToday: CurrentWeather
    /// Day or night by the clock, so a reading cached before sunset doesn't show the daytime hero.
    let iconCodeNow: String
    let mood: PetMood
    /// Today's seasonal theme by the city's own date, so it ends by itself when its day does.
    let seasonalTheme: SeasonalTheme?
    /// Today's forecast, by the city's own date; nil before the forecast has today.
    let today: DayForecast?
    /// Today's high and low in whole degrees, taking in the temperature now.
    let high: Int
    let low: Int
    let heroCaption: String
    /// The hourly strip's hours and sunrise and sunset; empty when it's switched off or there are
    /// no hours left.
    let hourlyStrip: [HourlyStripItem]
    /// "Rain starting around 3:15 PM", only when rain or snow is due in the next 2 hours.
    let nextRain: NextRain?
    /// The chance of rain over the next few hours; it takes over the next-rain line.
    let rainOutlook: RainOutlook?
    /// Nil while the forecast is loading or failed, which hides the card rather than advising on
    /// nothing.
    let walkAdvice: WalkAdvice?
    let showsWalkCard: Bool
    /// What the walk card says; nil when it doesn't show.
    let walkCard: WalkCardContent?
    let tiles: Tiles
    /// The Today tiles, worked out from `tiles` and the reading.
    let todayTiles: TodayTilesState
    let showsRadar: Bool
    /// Nil when the rest of the week is switched off, or there's nothing to show for it.
    let week: Week?

    /// The hourly strip covers the next 24 hours.
    static let hourlyStripCount = 24

    init(
        weather: CurrentWeather,
        showingForecast: Bool,
        stale: Stale?,
        forecast: LoadingState<[DayForecast]>,
        now: Date,
        hasDog: Bool,
        config: WeatherScreenConfig
    ) {
        let days = forecast.successValue ?? []
        let timeZone = weather.timeZone
        self.now = now
        self.weather = weather
        self.showingForecast = showingForecast
        self.stale = stale
        self.hasDog = hasDog
        weatherToday = StaleWeather.withSunTimesToday(weather, at: now)
        iconCodeNow = StaleWeather.iconCode(weather, at: now)
        mood = PetMood.forReading(weather, at: now, thresholds: config.thresholds)
        seasonalTheme = SeasonalThemes.theme(on: now, timeZone: timeZone, in: config.seasonalThemes)
        let today = days.first.flatMap { $0.isDay(of: now, in: timeZone) ? $0 : nil }
        self.today = today
        let highLow = TodayDetails.highLow(current: weather, today: today)
        high = Int(highLow.high.rounded())
        low = Int(highLow.low.rounded())

        // From the hour in progress on, however old the forecast on screen is.
        let upcomingSlots = days.flatMap(\.hourlySlots).upcoming(from: now)
        let stripSlots = Array(upcomingSlots.prefix(Self.hourlyStripCount))
        hourlyStrip = config.hourlyForecastEnabled && !stripSlots.isEmpty
            ? HourlyStripItem.strip(stripSlots, events: SunEvent.all(forecast: days, weather: weatherToday), now: now)
            : []
        let nextRain = config.nextRainEnabled ? NextRain.from(days.first?.quarterHours ?? [], now: now) : nil
        self.nextRain = nextRain
        rainOutlook = RainOutlook.from(
            upcomingSlots,
            enabled: config.rainOutlookEnabled,
            hours: config.rainOutlookHours,
            minChance: config.rainOutlookMinChance,
            units: weather.units,
            nextRainLine: nextRain?.line(timeZone: timeZone)
        )

        let walkAdvice = forecast.successValue == nil
            ? nil
            : WalkAdvisor.advice(for: weather, forecast: days, at: now, thresholds: config.thresholds, hasDog: hasDog)
        self.walkAdvice = walkAdvice
        showsWalkCard = walkAdvice?.showsCard(hasDog: hasDog, cardEnabled: config.walkCardEnabled) ?? false
        walkCard = showsWalkCard ? walkAdvice.map(WalkCardContent.init) : nil
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        heroCaption = PetMood.heroCaption(
            walk: walkAdvice?.now,
            hasDog: hasDog,
            themeCaption: seasonalTheme?.caption(night: mood == .night, on: now, calendar: calendar),
            mood: mood,
            partlyCloudy: PetMood.isPartlyCloudy(weather, showingForecast: showingForecast),
            on: now,
            timeZone: timeZone
        )

        let hourNow = upcomingSlots.first
        tiles = Tiles(
            // Paw Check goes with the walk card: Settings' I have a dog switch hides both.
            pavementNow: hasDog ? hourNow?.pavementTemperature : nil,
            groundWet: hourNow?.groundWet == true || WalkAdvisor.isPrecipitating(conditionMain: weather.conditionMain),
            uvIndex: iconCodeNow.hasSuffix("n") ? nil : hourNow?.uvIndex,
            uvPeak: today?.hourlySlots.filter { $0.uvIndex != nil }.max { ($0.uvIndex ?? 0) < ($1.uvIndex ?? 0) },
            // The forecast's hour in progress, so it shows offline too. A forecast cached before the
            // switch went off can still have it, hence the check here as well.
            airQuality: config.airQualityEnabled ? hourNow?.airQuality : nil
        )
        todayTiles = TodayTilesState(
            weather: weatherToday,
            showingForecast: showingForecast,
            pavementNow: tiles.pavementNow,
            groundWet: tiles.groundWet,
            uvIndex: tiles.uvIndex,
            uvPeak: tiles.uvPeak,
            airQuality: tiles.airQuality,
            hasDog: hasDog,
            now: now,
            thresholds: config.thresholds,
            distanceInMiles: config.distanceInMiles,
            switches: config.todayTiles
        )
        showsRadar = config.radarEnabled

        let upcomingDays = today != nil ? Array(days.dropFirst()) : days
        week = if !config.weekForecastEnabled {
            nil
        } else if !upcomingDays.isEmpty {
            .days(upcomingDays)
        } else {
            switch forecast {
            case .loading: .loading
            case let .error(errorKey, canRetry): .error(errorKey: errorKey, canRetry: canRetry)
            case .idle, .success: nil
            }
        }
    }
}
