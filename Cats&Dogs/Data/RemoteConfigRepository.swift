import FirebaseCore
import FirebaseRemoteConfig
import Foundation

/// Server-tunable values, with the same keys, defaults and limits as Android's
/// `RemoteConfigRepository`. Falls back to the defaults when Firebase isn't configured.
@MainActor
final class RemoteConfigRepository {
    static let shared = RemoteConfigRepository()

    nonisolated static let keyRefreshInterval = "weather_refresh_interval_minutes"
    nonisolated static let defaultRefreshIntervalMinutes = 30
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
    /// Stops fetching air quality: no Air quality tile, and the walk planner ignores the air.
    nonisolated static let keyAirQualityEnabled = "air_quality_enabled"
    /// Off sends forecasts for cities with coordinates to OpenWeatherMap instead of Open-Meteo.
    nonisolated static let keyOpenMeteoEnabled = "open_meteo_enabled"
    /// Replacement OpenWeather API key, so a leaked key can be rotated without an app update.
    nonisolated static let keyOpenWeatherApiKey = "openweather_api_key"

    /// Below this version the app is blocked until it's updated; below the recommended one a
    /// banner asks. Separate from Android's keys. Empty never asks.
    nonisolated static let keyIosMinSupportedVersion = "ios_min_supported_version"
    nonisolated static let keyIosMinRecommendedVersion = "ios_min_recommended_version"
    /// Where the Update button goes. Empty hides the button, until the App Store record exists.
    nonisolated static let keyIosAppStoreURL = "ios_app_store_url"

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
            Self.keyDailyWeatherNotificationsEnabled: NSNumber(value: true),
            Self.keyWalkTimeNotificationsEnabled: NSNumber(value: true),
            Self.keyRainNotificationsEnabled: NSNumber(value: true),
            Self.keyForegroundRefreshMinMinutes: NSNumber(value: Self.defaultForegroundRefreshMinMinutes),
            Self.keyOpenMeteoEnabled: NSNumber(value: true),
            Self.keyAirQualityEnabled: NSNumber(value: true),
            Self.keyOpenWeatherApiKey: "" as NSString,
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
        // Activated values apply from the next read; this launch keeps what was last activated.
        remoteConfig.fetchAndActivate()
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

    var petWeatherThresholds: PetWeatherThresholds {
        PetWeatherThresholds.validated(
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
    }

    /// Nil when Firebase is off or the key has no value at all, which would otherwise read as 0.
    private func number(_ key: String) -> NSNumber? {
        guard let value = remoteConfig?[key], value.source != .static else { return nil }
        return value.numberValue
    }

    var dailyWeatherNotificationsEnabled: Bool { Self.flag(Self.keyDailyWeatherNotificationsEnabled) }
    var walkTimeNotificationsEnabled: Bool { Self.flag(Self.keyWalkTimeNotificationsEnabled) }
    var rainNotificationsEnabled: Bool { Self.flag(Self.keyRainNotificationsEnabled) }

    /// Each kind of notification can be switched off for everyone; Settings then hides its switch.
    func notificationsEnabled(_ kind: NotificationKind) -> Bool {
        switch kind {
        case .morningBriefing: dailyWeatherNotificationsEnabled
        case .walkTime: walkTimeNotificationsEnabled
        case .rain: rainNotificationsEnabled
        }
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

    /// Nil when unset or blank, so the key built into the app is used. Not a secret: Remote Config
    /// values reach every device.
    nonisolated static var openWeatherApiKey: String? {
        guard FirebaseApp.app() != nil else { return nil }
        let value = RemoteConfig.remoteConfig()[keyOpenWeatherApiKey]
        guard value.source != .static else { return nil }
        let key: String? = value.stringValue
        return key?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    /// Every flag defaults to on. A key with no value at all reads as false, so that counts as
    /// "not set" rather than "off".
    private nonisolated static func flag(_ key: String) -> Bool {
        guard FirebaseApp.app() != nil else { return true }
        let value = RemoteConfig.remoteConfig()[key]
        return value.source == .static ? true : value.boolValue
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
}

private extension String {
    /// Nonisolated, as the forecast fetch reads the OpenWeather key off the main actor.
    nonisolated var nilIfBlank: String? { isEmpty ? nil : self }
}
