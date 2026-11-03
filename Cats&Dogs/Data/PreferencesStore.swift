import Foundation

@MainActor
final class PreferencesStore {
    static let shared = PreferencesStore()

    private let defaults: UserDefaults
    private let region: String?
    private let hasSeenWelcomeKey = "has_seen_welcome"
    private let locationOnboardingDoneKey = "location_onboarding_done"
    private let notificationOnboardingDoneKey = "notification_onboarding_done"
    private let lastCityKey = "last_city"
    private let savedLocationsKey = "saved_locations"
    private let activeLocationIndexKey = "active_location_index"
    private let weatherCacheKey = "weather_cache"
    private let forecastCacheKey = "forecast_cache"
    private let forecastFetchedAtKey = "forecast_fetched_at"
    private let unitOverrideKey = "unit_override"
    private let shareUsageStatisticsKey = "share_usage_statistics"
    private let showWalkCardKey = "show_walk_card"
    private let notifyMorningBriefingKey = "notify_morning_briefing"
    private let notifyWalkTimeKey = "notify_walk_time"
    private let notifyRainKey = "notify_rain"
    private let rainAlertStartKey = "rain_alert_start"
    private let rainAlertFireKey = "rain_alert_fire"
    private let walkNudgeDatesKey = "walk_nudge_dates"
    private let updateBannerDismissedKey = "update_banner_dismissed_at"
    private let followMyLocationKey = "follow_my_location"
    private let alwaysLocationAskedKey = "always_location_asked"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, region: String? = Locale.current.region?.identifier) {
        self.defaults = defaults
        self.region = region
    }

    /// The EU, the rest of the EEA, the UK and Switzerland need opt-in consent for analytics.
    nonisolated static let optInRegions: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV",
        "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO", "GB", "CH",
    ]

    var hasSeenWelcome: Bool {
        defaults.bool(forKey: hasSeenWelcomeKey)
    }

    var locationOnboardingDone: Bool {
        defaults.bool(forKey: locationOnboardingDoneKey)
    }

    var notificationOnboardingDone: Bool {
        if defaults.object(forKey: notificationOnboardingDoneKey) != nil {
            return defaults.bool(forKey: notificationOnboardingDoneKey)
        }
        // Legacy installs that completed location onboarding before this flag existed.
        return locationOnboardingDone
    }

    var lastCity: String? {
        defaults.string(forKey: lastCityKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    var savedLocations: [SavedLocation] {
        guard let data = defaults.data(forKey: savedLocationsKey) else { return [] }
        return (try? decoder.decode([SavedLocation].self, from: data)) ?? []
    }

    var activeLocationIndex: Int {
        defaults.integer(forKey: activeLocationIndexKey)
    }

    var unitOverride: UnitOverride {
        guard let raw = defaults.string(forKey: unitOverrideKey) else { return .system }
        return UnitOverride(rawValue: raw) ?? .system
    }

    /// The user's analytics choice. Until they make one it is on, except where analytics need
    /// opt-in consent, where it stays off until they turn it on in Settings.
    var shareUsageStatistics: Bool {
        defaults.object(forKey: shareUsageStatisticsKey) as? Bool ?? !Self.optInRegions.contains(region ?? "")
    }

    /// Whether the main screen shows the "Best walk time" card. On until the user turns it off
    /// (say, because they don't have a dog).
    var showWalkCard: Bool {
        defaults.object(forKey: showWalkCardKey) as? Bool ?? true
    }

    func setShowWalkCard(_ value: Bool) {
        defaults.set(value, forKey: showWalkCardKey)
    }

    /// The 8:30 AM weather briefing. On unless they turn it off.
    var notifyMorningBriefing: Bool {
        defaults.object(forKey: notifyMorningBriefingKey) as? Bool ?? true
    }

    func setNotifyMorningBriefing(_ value: Bool) {
        defaults.set(value, forKey: notifyMorningBriefingKey)
    }

    /// A nudge at the day's best walk time. Until they choose, it follows the dog question (the walk
    /// card's switch): on with a dog at home, off without.
    var notifyWalkTime: Bool {
        defaults.object(forKey: notifyWalkTimeKey) as? Bool ?? showWalkCard
    }

    func setNotifyWalkTime(_ value: Bool) {
        defaults.set(value, forKey: notifyWalkTimeKey)
    }

    /// An alert when rain or snow is about to start. Off unless they turn it on.
    var notifyRain: Bool {
        defaults.object(forKey: notifyRainKey) as? Bool ?? false
    }

    func setNotifyRain(_ value: Bool) {
        defaults.set(value, forKey: notifyRainKey)
    }

    /// "Follow my location" in Notification settings: My Location moves in the background too. It
    /// also needs "Always" location, which the switch asks for. Off until turned on.
    var followMyLocation: Bool {
        defaults.bool(forKey: followMyLocationKey)
    }

    func setFollowMyLocation(_ value: Bool) {
        defaults.set(value, forKey: followMyLocationKey)
    }

    /// Whether iOS's one "Change to Always Allow" prompt has been asked for. After it, only the
    /// Settings app can grant "Always".
    var alwaysLocationAsked: Bool {
        defaults.bool(forKey: alwaysLocationAskedKey)
    }

    func setAlwaysLocationAsked() {
        defaults.set(true, forKey: alwaysLocationAskedKey)
    }

    /// The last rain alert queued: when that rain starts and when the alert goes off, so the same
    /// shower isn't alerted twice once it has gone off.
    var lastRainAlert: RainAlertRecord? {
        guard let start = defaults.object(forKey: rainAlertStartKey) as? Int,
              let fire = defaults.object(forKey: rainAlertFireKey) as? Double else { return nil }
        return RainAlertRecord(rainStart: start, fireDate: Date(timeIntervalSince1970: fire))
    }

    func setLastRainAlert(_ record: RainAlertRecord) {
        defaults.set(record.rainStart, forKey: rainAlertStartKey)
        defaults.set(record.fireDate.timeIntervalSince1970, forKey: rainAlertFireKey)
    }

    /// When the queued walk nudges go off, plus any that went off earlier today, so a replan after
    /// one has gone off doesn't send a second that day.
    var walkNudgeDates: [Date] {
        (defaults.array(forKey: walkNudgeDatesKey) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }
    }

    func setWalkNudgeDates(_ dates: [Date]) {
        defaults.set(dates.map(\.timeIntervalSince1970), forKey: walkNudgeDatesKey)
    }

    /// When "Not now" was last tapped on the update banner.
    var updateBannerDismissedAt: Date? {
        (defaults.object(forKey: updateBannerDismissedKey) as? Double).map(Date.init(timeIntervalSince1970:))
    }

    func setUpdateBannerDismissedAt(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: updateBannerDismissedKey)
    }

    func setHasSeenWelcome(_ value: Bool) {
        defaults.set(value, forKey: hasSeenWelcomeKey)
    }

    func setLocationOnboardingDone() {
        defaults.set(true, forKey: locationOnboardingDoneKey)
    }

    func setNotificationOnboardingDone() {
        defaults.set(true, forKey: notificationOnboardingDoneKey)
    }

    func setLastCity(_ cityName: String) {
        defaults.set(cityName, forKey: lastCityKey)
    }

    /// Moves My Location to `latitude`, `longitude` after a real move (`withMyLocation`). True when
    /// it moved.
    @discardableResult
    func moveMyLocation(latitude: Double, longitude: Double) -> Bool {
        guard let moved = savedLocations.withMyLocation(atLatitude: latitude, longitude: longitude) else { return false }
        setSavedLocations(moved)
        return true
    }

    func setSavedLocations(_ locations: [SavedLocation]) {
        guard let data = try? encoder.encode(locations) else { return }
        defaults.set(data, forKey: savedLocationsKey)
        pruneCache(keeping: locations)
    }

    func setActiveLocationIndex(_ index: Int) {
        defaults.set(index, forKey: activeLocationIndexKey)
    }

    func setUnitOverride(_ override: UnitOverride) {
        defaults.set(override.rawValue, forKey: unitOverrideKey)
    }

    func setShareUsageStatistics(_ value: Bool) {
        defaults.set(value, forKey: shareUsageStatisticsKey)
    }

    func cachedWeather(for locationKey: String) -> CurrentWeather? {
        loadCache(CurrentWeather.self, forKey: weatherCacheKey)[locationKey]
    }

    func setCachedWeather(_ weather: CurrentWeather, for locationKey: String) {
        var cache = loadCache(CurrentWeather.self, forKey: weatherCacheKey)
        cache[locationKey] = weather
        saveCache(cache, forKey: weatherCacheKey)
    }

    func cachedForecast(for locationKey: String) -> [DayForecast]? {
        loadCache([DayForecast].self, forKey: forecastCacheKey)[locationKey]
    }

    func setCachedForecast(_ forecast: [DayForecast], for locationKey: String, fetchedAt: Date = Date()) {
        var cache = loadCache([DayForecast].self, forKey: forecastCacheKey)
        cache[locationKey] = forecast
        saveCache(cache, forKey: forecastCacheKey)
        var times = loadCache(Double.self, forKey: forecastFetchedAtKey)
        times[locationKey] = fetchedAt.timeIntervalSince1970
        saveCache(times, forKey: forecastFetchedAtKey)
    }

    /// When the cached forecast was fetched; nil for one cached before this was kept.
    func cachedForecastFetchedAt(for locationKey: String) -> Date? {
        loadCache(Double.self, forKey: forecastFetchedAtKey)[locationKey].map { Date(timeIntervalSince1970: $0) }
    }

    func clearCache() {
        defaults.removeObject(forKey: weatherCacheKey)
        defaults.removeObject(forKey: forecastCacheKey)
        defaults.removeObject(forKey: forecastFetchedAtKey)
    }

    /// Drops cache entries for cities that are no longer saved, so removed cities (and every spot
    /// "My Location" has ever resolved to) don't pile up in UserDefaults.
    private func pruneCache(keeping locations: [SavedLocation]) {
        let keys = Set(locations.map(\.cacheKey))
        prune(CurrentWeather.self, forKey: weatherCacheKey, keeping: keys)
        prune([DayForecast].self, forKey: forecastCacheKey, keeping: keys)
        prune(Double.self, forKey: forecastFetchedAtKey, keeping: keys)
    }

    private func prune<Value: Codable>(_ type: Value.Type, forKey key: String, keeping keys: Set<String>) {
        let cache = loadCache(type, forKey: key)
        let pruned = cache.filter { keys.contains($0.key) }
        if pruned.count != cache.count {
            saveCache(pruned, forKey: key)
        }
    }

    /// Unreadable data (including the older string-in-a-map format) is treated as an empty cache.
    private func loadCache<Value: Codable>(_ type: Value.Type, forKey key: String) -> [String: Value] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? decoder.decode([String: Value].self, from: data)) ?? [:]
    }

    private func saveCache<Value: Codable>(_ cache: [String: Value], forKey key: String) {
        guard let data = try? encoder.encode(cache) else { return }
        defaults.set(data, forKey: key)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
