import FirebaseCore
import FirebaseRemoteConfig
import Foundation

/// Server-tunable values, with the same keys, defaults and limits as Android's
/// `RemoteConfigRepository`. Falls back to the defaults when Firebase isn't configured.
@MainActor
final class RemoteConfigRepository {
    static let shared = RemoteConfigRepository()

    nonisolated static let keyRefreshInterval = "weather_refresh_interval_minutes"
    nonisolated static let defaultRefreshIntervalMinutes = 60
    /// Matches Android's WorkManager floor. iOS treats the interval as a minimum anyway.
    nonisolated static let minRefreshIntervalMinutes = 15

    nonisolated static let keyRadarFrameInterval = "radar_frame_interval_ms"
    nonisolated static let defaultRadarFrameIntervalMs = 850
    nonisolated static let radarFrameIntervalRangeMs = 100 ... 5000

    /// Kill switch: false drops every analytics event on every install, without an app update.
    nonisolated static let keyAnalyticsEnabled = "analytics_enabled"
    nonisolated static let defaultAnalyticsEnabled = true

    /// Hides the radar card if RainViewer or the OpenStreetMap tiles become unavailable.
    nonisolated static let keyRadarEnabled = "radar_enabled"
    /// Only the daily 9 AM / 1 PM / 7 PM weather summaries. Other notification types get their own.
    nonisolated static let keyDailyWeatherNotificationsEnabled = "daily_weather_notifications_enabled"
    nonisolated static let keyWalkTimeNotificationsEnabled = "walk_time_notifications_enabled"
    nonisolated static let keyRainNotificationsEnabled = "rain_notifications_enabled"
    /// Off for the first release: an alert is only queued if a background refresh happens to run in
    /// the two hours before the rain, which iOS makes hit or miss (NOTES.md).
    nonisolated static let defaultRainNotificationsEnabled = false

    /// Skips the silent refresh on returning to the foreground if the city was fetched this recently.
    nonisolated static let keyForegroundRefreshMinMinutes = "foreground_refresh_min_minutes"
    nonisolated static let defaultForegroundRefreshMinMinutes = 0
    nonisolated static let foregroundRefreshMinMinutesRange = 0 ... 1440

    /// Walk advice and pet moods, all Celsius. See `PetWeatherThresholds` for ranges.
    nonisolated static let keyWalkHotPavementC = "walk_hot_pavement_c"
    nonisolated static let keyWalkWarmPavementC = "walk_warm_pavement_c"
    nonisolated static let keyWalkIcyPavementC = "walk_icy_pavement_c"
    nonisolated static let keyWalkDangerousPavementC = "walk_dangerous_pavement_c"
    nonisolated static let keyWalkMaxRainChance = "walk_max_rain_chance"
    nonisolated static let keyWalkComfortMinC = "walk_comfort_min_c"
    nonisolated static let keyWalkComfortMaxC = "walk_comfort_max_c"
    nonisolated static let keyWalkHoursStart = "walk_hours_start"
    nonisolated static let keyWalkHoursEnd = "walk_hours_end"
    nonisolated static let keyPetHotThresholdC = "pet_hot_threshold_c"
    nonisolated static let keyPetColdThresholdC = "pet_cold_threshold_c"
    nonisolated static let keyWalkBadAirBand = "walk_bad_air_band"

    /// Hides the "time to walk the dog" card.
    nonisolated static let keyWalkCardEnabled = "walk_card_enabled"
    /// Hide the hourly strip, the "Rain starting around 3:15 PM" line and the rest of the week.
    nonisolated static let keyHourlyForecastEnabled = "hourly_forecast_enabled"
    nonisolated static let keyNextRainEnabled = "next_rain_enabled"
    nonisolated static let keyWeekForecastEnabled = "week_forecast_enabled"
    /// The Rain outlook card: a switch, how many hours it charts from the one in progress, and the
    /// chance an hour must reach for the card to show (also where "Drying out after" draws the line).
    nonisolated static let keyRainOutlookEnabled = "rain_outlook_enabled"
    nonisolated static let keyRainOutlookHours = "rain_outlook_hours"
    nonisolated static let defaultRainOutlookHours = 10
    nonisolated static let rainOutlookHoursRange = 6 ... 12
    nonisolated static let keyRainOutlookMinChance = "rain_outlook_min_chance"
    nonisolated static let defaultRainOutlookMinChance = 20
    nonisolated static let rainOutlookMinChanceRange = 1 ... 100
    /// Stops fetching air quality: no Air quality tile, and the walk planner ignores the air.
    nonisolated static let keyAirQualityEnabled = "air_quality_enabled"
    /// One switch per Today tile, so any can be hidden for everyone. UV is new and starts off.
    nonisolated static let keyTileFeelsLikeEnabled = "tile_feels_like_enabled"
    nonisolated static let keyTileWindEnabled = "tile_wind_enabled"
    nonisolated static let keyTileHumidityEnabled = "tile_humidity_enabled"
    nonisolated static let keyTilePawCheckEnabled = "tile_paw_check_enabled"
    nonisolated static let keyTileUvEnabled = "tile_uv_enabled"
    nonisolated static let keyTileDaylightEnabled = "tile_daylight_enabled"
    nonisolated static let keyTileSkyEnabled = "tile_sky_enabled"
    /// Seasonal themes (`SeasonalTheme`): a master switch, and the themes themselves as JSON, which
    /// replaces the list shipped in the app when it's valid. Empty uses the shipped list.
    nonisolated static let keySeasonalThemesEnabled = "seasonal_themes_enabled"
    nonisolated static let keySeasonalThemes = "seasonal_themes"
    /// Off shows temperatures as "89°" rather than "89 °F". Units and conversion are unchanged.
    nonisolated static let keyTemperatureUnitsShown = "temperature_units_shown"
    nonisolated static let defaultTemperatureUnitsShown = false
    /// Off sends forecasts for cities with coordinates to OpenWeatherMap instead of Open-Meteo.
    nonisolated static let keyOpenMeteoEnabled = "open_meteo_enabled"
    /// Replacement OpenWeather API key, so a leaked key can be rotated without an app update.
    nonisolated static let keyOpenWeatherApiKey = "openweather_api_key"
    /// Town and city search (SEARCH.md, "Remote Config design"): where suggestions come from, how
    /// many show, the two sorting rules and their size guard, and the wait after typing.
    nonisolated static let keyCitySearchProvider = "city_search_provider"
    nonisolated static let keyCitySearchResults = "city_search_results"
    nonisolated static let citySearchResultsRange = 3 ... 10
    nonisolated static let keyCitySearchCountryFirst = "city_search_country_first"
    nonisolated static let keyCitySearchNearestFirst = "city_search_nearest_first"
    nonisolated static let keyCitySearchSizeRatio = "city_search_size_ratio"
    nonisolated static let citySearchSizeRatioRange = 2 ... 1000
    nonisolated static let keyCitySearchDelayMs = "city_search_delay_ms"
    nonisolated static let citySearchDelayRangeMs = 100 ... 1000

    /// Below this version the app is blocked until it's updated; below the recommended one a
    /// banner asks. Separate from Android's keys. Empty never asks.
    nonisolated static let keyIosMinSupportedVersion = "ios_min_supported_version"
    nonisolated static let keyIosMinRecommendedVersion = "ios_min_recommended_version"
    /// Where the Update button goes. Empty hides the button, until the App Store record exists.
    nonisolated static let keyIosAppStoreURL = "ios_app_store_url"

    /// Posted on the main queue when newly fetched values have been activated.
    nonisolated static let didActivate = Notification.Name("RemoteConfigRepository.didActivate")

    private let remoteConfig: RemoteConfig?

    private init() {
        guard FirebaseSetup.isConfigured else {
            remoteConfig = nil
            return
        }
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        // Fetch new values at most every hour, as on Android.
        settings.minimumFetchInterval = 3600
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults([
            Self.keyRefreshInterval: NSNumber(value: Self.defaultRefreshIntervalMinutes),
            Self.keyRadarFrameInterval: NSNumber(value: Self.defaultRadarFrameIntervalMs),
            Self.keyAnalyticsEnabled: NSNumber(value: Self.defaultAnalyticsEnabled),
            Self.keyRadarEnabled: NSNumber(value: true),
            Self.keyWalkCardEnabled: NSNumber(value: true),
            Self.keyHourlyForecastEnabled: NSNumber(value: true),
            Self.keyNextRainEnabled: NSNumber(value: true),
            Self.keyWeekForecastEnabled: NSNumber(value: true),
            Self.keyRainOutlookEnabled: NSNumber(value: true),
            Self.keyRainOutlookHours: NSNumber(value: Self.defaultRainOutlookHours),
            Self.keyRainOutlookMinChance: NSNumber(value: Self.defaultRainOutlookMinChance),
            Self.keyDailyWeatherNotificationsEnabled: NSNumber(value: true),
            Self.keyWalkTimeNotificationsEnabled: NSNumber(value: true),
            Self.keyRainNotificationsEnabled: NSNumber(value: Self.defaultRainNotificationsEnabled),
            Self.keyForegroundRefreshMinMinutes: NSNumber(value: Self.defaultForegroundRefreshMinMinutes),
            Self.keyOpenMeteoEnabled: NSNumber(value: true),
            Self.keyAirQualityEnabled: NSNumber(value: true),
            Self.keyTileFeelsLikeEnabled: NSNumber(value: Self.defaultTiles.feelsLike),
            Self.keyTileWindEnabled: NSNumber(value: Self.defaultTiles.wind),
            Self.keyTileHumidityEnabled: NSNumber(value: Self.defaultTiles.humidity),
            Self.keyTilePawCheckEnabled: NSNumber(value: Self.defaultTiles.pawCheck),
            Self.keyTileUvEnabled: NSNumber(value: Self.defaultTiles.uv),
            Self.keyTileDaylightEnabled: NSNumber(value: Self.defaultTiles.daylight),
            Self.keyTileSkyEnabled: NSNumber(value: Self.defaultTiles.sky),
            Self.keySeasonalThemesEnabled: NSNumber(value: true),
            Self.keySeasonalThemes: "" as NSString,
            Self.keyTemperatureUnitsShown: NSNumber(value: Self.defaultTemperatureUnitsShown),
            Self.keyOpenWeatherApiKey: "" as NSString,
            Self.keyCitySearchProvider: CitySearchPolicy.standard.provider.rawValue as NSString,
            Self.keyCitySearchResults: NSNumber(value: CitySearchPolicy.standard.results),
            Self.keyCitySearchCountryFirst: NSNumber(value: CitySearchPolicy.standard.countryFirst),
            Self.keyCitySearchNearestFirst: NSNumber(value: CitySearchPolicy.standard.nearestFirst),
            Self.keyCitySearchSizeRatio: NSNumber(value: CitySearchPolicy.standard.sizeRatio),
            Self.keyCitySearchDelayMs: NSNumber(value: CitySearchPolicy.standard.delayMilliseconds),
            Self.keyIosMinSupportedVersion: "" as NSString,
            Self.keyIosMinRecommendedVersion: "" as NSString,
            Self.keyIosAppStoreURL: "" as NSString,
            Self.keyWalkHotPavementC: NSNumber(value: PetWeatherThresholds.standard.hotPavementC),
            Self.keyWalkWarmPavementC: NSNumber(value: PetWeatherThresholds.standard.warmPavementC),
            Self.keyWalkIcyPavementC: NSNumber(value: PetWeatherThresholds.standard.icyPavementC),
            Self.keyWalkDangerousPavementC: NSNumber(value: PetWeatherThresholds.standard.dangerousPavementC),
            Self.keyWalkMaxRainChance: NSNumber(value: PetWeatherThresholds.standard.maxRainChance),
            Self.keyWalkComfortMinC: NSNumber(value: PetWeatherThresholds.standard.comfortC.lowerBound),
            Self.keyWalkComfortMaxC: NSNumber(value: PetWeatherThresholds.standard.comfortC.upperBound),
            Self.keyWalkHoursStart: NSNumber(value: PetWeatherThresholds.standard.walkHours.lowerBound),
            Self.keyWalkHoursEnd: NSNumber(value: PetWeatherThresholds.standard.walkHours.upperBound),
            Self.keyPetHotThresholdC: NSNumber(value: PetWeatherThresholds.standard.petHotC),
            Self.keyPetColdThresholdC: NSNumber(value: PetWeatherThresholds.standard.petColdC),
            Self.keyWalkBadAirBand: NSNumber(value: PetWeatherThresholds.standard.badAirBand),
        ])
        // Activated values apply from the next read. Screens that keep what they worked out (the
        // weather screen) listen for `didActivate` to work it out again.
        remoteConfig.fetchAndActivate { status, _ in
            guard status != .error else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: RemoteConfigRepository.didActivate, object: nil)
            }
        }
        self.remoteConfig = remoteConfig
    }

    var refreshInterval: TimeInterval {
        let minutes = remoteConfig?[Self.keyRefreshInterval].numberValue.intValue
        return Self.refreshInterval(minutes: minutes)
    }

    var radarFrameInterval: Duration {
        let milliseconds = remoteConfig?[Self.keyRadarFrameInterval].numberValue.intValue
        return Self.radarFrameInterval(milliseconds: milliseconds)
    }

    var analyticsEnabled: Bool { Self.flag(Self.keyAnalyticsEnabled) }

    var radarEnabled: Bool { Self.flag(Self.keyRadarEnabled) }

    var walkCardEnabled: Bool { Self.flag(Self.keyWalkCardEnabled) }

    var hourlyForecastEnabled: Bool { Self.flag(Self.keyHourlyForecastEnabled) }

    var nextRainEnabled: Bool { Self.flag(Self.keyNextRainEnabled) }

    var weekForecastEnabled: Bool { Self.flag(Self.keyWeekForecastEnabled) }

    var rainOutlookEnabled: Bool { Self.flag(Self.keyRainOutlookEnabled) }

    var rainOutlookHours: Int {
        Self.rainOutlookHours(number(Self.keyRainOutlookHours)?.doubleValue)
    }

    var rainOutlookMinChance: Int {
        Self.rainOutlookMinChance(number(Self.keyRainOutlookMinChance)?.doubleValue)
    }

    var petWeatherThresholds: PetWeatherThresholds {
        var thresholds = PetWeatherThresholds.validated(
            hotPavementC: number(Self.keyWalkHotPavementC)?.doubleValue,
            warmPavementC: number(Self.keyWalkWarmPavementC)?.doubleValue,
            icyPavementC: number(Self.keyWalkIcyPavementC)?.doubleValue,
            dangerousPavementC: number(Self.keyWalkDangerousPavementC)?.doubleValue,
            maxRainChance: number(Self.keyWalkMaxRainChance)?.intValue,
            comfortMinC: number(Self.keyWalkComfortMinC)?.doubleValue,
            comfortMaxC: number(Self.keyWalkComfortMaxC)?.doubleValue,
            walkHoursStart: number(Self.keyWalkHoursStart)?.intValue,
            walkHoursEnd: number(Self.keyWalkHoursEnd)?.intValue,
            petHotC: number(Self.keyPetHotThresholdC)?.doubleValue,
            petColdC: number(Self.keyPetColdThresholdC)?.doubleValue,
            badAirBand: number(Self.keyWalkBadAirBand)?.intValue
        )
        thresholds.airQualityEnabled = Self.airQualityEnabled
        return thresholds
    }

    /// Nil when Firebase is off or the key has no value at all, which would otherwise read as 0.
    private func number(_ key: String) -> NSNumber? {
        guard let value = remoteConfig?[key], value.source != .static else { return nil }
        return value.numberValue
    }

    var dailyWeatherNotificationsEnabled: Bool { Self.flag(Self.keyDailyWeatherNotificationsEnabled) }
    var walkTimeNotificationsEnabled: Bool { Self.flag(Self.keyWalkTimeNotificationsEnabled) }
    var rainNotificationsEnabled: Bool {
        Self.flag(Self.keyRainNotificationsEnabled, fallback: Self.defaultRainNotificationsEnabled)
    }

    /// Each kind of notification can be switched off for everyone; Settings then hides its switch.
    func notificationsEnabled(_ kind: NotificationKind) -> Bool {
        switch kind {
        case .morningBriefing: dailyWeatherNotificationsEnabled
        case .walkTime: walkTimeNotificationsEnabled
        case .rain: rainNotificationsEnabled
        }
    }

    /// Read on every search, so a change applies from the next one. Each value is validated, so a bad
    /// console value falls back to its default instead of breaking search.
    var citySearchPolicy: CitySearchPolicy {
        Self.citySearchPolicy(
            provider: string(Self.keyCitySearchProvider),
            openMeteoEnabled: Self.openMeteoEnabled,
            results: number(Self.keyCitySearchResults)?.doubleValue,
            countryFirst: Self.flag(Self.keyCitySearchCountryFirst, fallback: CitySearchPolicy.standard.countryFirst),
            nearestFirst: Self.flag(Self.keyCitySearchNearestFirst, fallback: CitySearchPolicy.standard.nearestFirst),
            sizeRatio: number(Self.keyCitySearchSizeRatio)?.doubleValue,
            delayMilliseconds: number(Self.keyCitySearchDelayMs)?.doubleValue
        )
    }

    var iosMinSupportedVersion: String? { string(Self.keyIosMinSupportedVersion) }
    var iosMinRecommendedVersion: String? { string(Self.keyIosMinRecommendedVersion) }
    var iosAppStoreURL: URL? { string(Self.keyIosAppStoreURL).flatMap(URL.init(string:)) }

    /// Nil when Firebase is off or the value is blank.
    private func string(_ key: String) -> String? {
        let value: String? = remoteConfig?[key].stringValue
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    var foregroundRefreshMinInterval: TimeInterval {
        let minutes = remoteConfig?[Self.keyForegroundRefreshMinMinutes].numberValue.intValue
        return Self.foregroundRefreshMinInterval(minutes: minutes)
    }

    /// Read from the forecast fetch, which isn't on the main actor. Remote Config is thread-safe.
    nonisolated static var openMeteoEnabled: Bool { flag(keyOpenMeteoEnabled) }

    /// Read from the forecast fetch too. Air quality comes from Open-Meteo, so it also needs that on.
    nonisolated static var airQualityEnabled: Bool { flag(keyAirQualityEnabled) }

    /// The default for `WeatherFormatting.temperature`'s `showsUnit`. Nonisolated, so it's a safe
    /// default argument whatever the formatter's isolation (Xcode 16.4 builds it nonisolated).
    /// Tests pass `showsUnit` instead.
    nonisolated static var temperatureUnitsShown: Bool {
        flag(keyTemperatureUnitsShown, fallback: defaultTemperatureUnitsShown)
    }

    /// Which Today tiles show. Air quality has its own switch above, as it also stops the fetch.
    var todayTiles: TodayTileSwitches {
        let defaults = Self.defaultTiles
        return TodayTileSwitches(
            feelsLike: Self.flag(Self.keyTileFeelsLikeEnabled, fallback: defaults.feelsLike),
            wind: Self.flag(Self.keyTileWindEnabled, fallback: defaults.wind),
            humidity: Self.flag(Self.keyTileHumidityEnabled, fallback: defaults.humidity),
            pawCheck: Self.flag(Self.keyTilePawCheckEnabled, fallback: defaults.pawCheck),
            uv: Self.flag(Self.keyTileUvEnabled, fallback: defaults.uv),
            daylight: Self.flag(Self.keyTileDaylightEnabled, fallback: defaults.daylight),
            sky: Self.flag(Self.keyTileSkyEnabled, fallback: defaults.sky)
        )
    }

    /// Each tile's switch with no Remote Config value: `TodayTileSwitches`' own defaults, so they're
    /// written in one place.
    private static let defaultTiles = TodayTileSwitches()

    /// Nil when unset or blank, so the key built into the app is used. Not a secret: Remote Config
    /// values reach every device.
    nonisolated static var openWeatherApiKey: String? {
        guard FirebaseApp.app() != nil else { return nil }
        let value = RemoteConfig.remoteConfig()[keyOpenWeatherApiKey]
        guard value.source != .static else { return nil }
        let key: String? = value.stringValue
        return key?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    /// The seasonal themes to choose from: Remote Config's list when it's valid, else the one shipped
    /// in the app; none when they're switched off. Debug builds can force one with
    /// `-seasonalTheme halloween`, whatever the date.
    var seasonalThemes: [SeasonalTheme] {
        #if DEBUG
        if let forced = UserDefaults.standard.string(forKey: "seasonalTheme") {
            return SeasonalThemes.builtIn.filter { $0.id == forced }.map(\.everyDay)
        }
        #endif
        guard Self.flag(Self.keySeasonalThemesEnabled) else { return [] }
        return string(Self.keySeasonalThemes).flatMap(themes(fromJSON:)) ?? SeasonalThemes.builtIn
    }

    /// The last theme list parsed, so a screen update doesn't decode the JSON again each time.
    private var lastThemes: (json: String, themes: [SeasonalTheme]?)?

    private func themes(fromJSON json: String) -> [SeasonalTheme]? {
        if let lastThemes, lastThemes.json == json { return lastThemes.themes }
        let themes = SeasonalThemes.parse(Data(json.utf8))
        lastThemes = (json, themes)
        return themes
    }

    /// A key with no value at all reads as false, so that counts as "not set" rather than "off":
    /// `fallback` is used then, and without Firebase, so a switch that starts off stays off.
    private nonisolated static func flag(_ key: String, fallback: Bool = true) -> Bool {
        guard FirebaseApp.app() != nil else { return fallback }
        let value = RemoteConfig.remoteConfig()[key]
        return value.source == .static ? fallback : value.boolValue
    }

    nonisolated static func refreshInterval(minutes: Int?) -> TimeInterval {
        TimeInterval(max(minutes ?? defaultRefreshIntervalMinutes, minRefreshIntervalMinutes) * 60)
    }

    nonisolated static func foregroundRefreshMinInterval(minutes: Int?) -> TimeInterval {
        guard let minutes, foregroundRefreshMinMinutesRange.contains(minutes) else {
            return TimeInterval(defaultForegroundRefreshMinMinutes * 60)
        }
        return TimeInterval(minutes * 60)
    }

    /// Out-of-range values fall back to the default rather than the nearest limit, as on Android.
    nonisolated static func radarFrameInterval(milliseconds: Int?) -> Duration {
        guard let milliseconds, radarFrameIntervalRangeMs.contains(milliseconds) else {
            return .milliseconds(defaultRadarFrameIntervalMs)
        }
        return .milliseconds(milliseconds)
    }

    /// Read as a double so that 7.5 falls back to the default too, rather than being cut to 7.
    nonisolated static func rainOutlookHours(_ value: Double?) -> Int {
        wholeNumber(value, in: rainOutlookHoursRange) ?? defaultRainOutlookHours
    }

    nonisolated static func rainOutlookMinChance(_ value: Double?) -> Int {
        wholeNumber(value, in: rainOutlookMinChanceRange) ?? defaultRainOutlookMinChance
    }

    /// `open_meteo_enabled` off forces OpenWeather, so the one licence switch turns off every
    /// Open-Meteo call. The size ratio is a whole number from 2 to 1000, or 0 for no guard.
    static func citySearchPolicy(
        provider: String?,
        openMeteoEnabled: Bool,
        results: Double?,
        countryFirst: Bool,
        nearestFirst: Bool,
        sizeRatio: Double?,
        delayMilliseconds: Double?
    ) -> CitySearchPolicy {
        let standard = CitySearchPolicy.standard
        let chosen = provider.flatMap(CitySearchProvider.init(rawValue:)) ?? standard.provider
        let ratio = sizeRatio == 0 ? 0 : wholeNumber(sizeRatio, in: citySearchSizeRatioRange)
        return CitySearchPolicy(
            provider: openMeteoEnabled ? chosen : .openWeather,
            results: wholeNumber(results, in: citySearchResultsRange) ?? standard.results,
            countryFirst: countryFirst,
            nearestFirst: nearestFirst,
            sizeRatio: ratio ?? standard.sizeRatio,
            delayMilliseconds: wholeNumber(delayMilliseconds, in: citySearchDelayRangeMs) ?? standard.delayMilliseconds
        )
    }

    /// Nil unless `value` is a whole number in `range`.
    private nonisolated static func wholeNumber(_ value: Double?, in range: ClosedRange<Int>) -> Int? {
        guard let value, value.rounded() == value,
              value >= Double(range.lowerBound), value <= Double(range.upperBound) else { return nil }
        return Int(value)
    }
}

private extension String {
    /// Nonisolated, as the forecast fetch reads the OpenWeather key off the main actor.
    nonisolated var nilIfBlank: String? { isEmpty ? nil : self }
}
