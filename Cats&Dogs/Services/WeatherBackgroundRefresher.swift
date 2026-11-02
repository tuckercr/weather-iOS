import BackgroundTasks
import Foundation

/// iOS counterpart of Android's `WeatherUpdateWorker` and `WeatherNotificationWorker`.
///
/// iOS cannot run code at a fixed time of day, so one `BGAppRefreshTask` does both jobs whenever
/// the system grants background time: it refreshes the active city's cache, then replans the queued
/// notifications (briefings, walk nudges, rain alert) from it.
@MainActor
final class WeatherBackgroundRefresher {
    static let shared = WeatherBackgroundRefresher()

    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    nonisolated static let taskIdentifier = "com.fangjet.weather.refresh"
    nonisolated static let retryInterval: TimeInterval = 15 * 60

    /// Remote Config's `weather_refresh_interval_minutes`, as on Android. iOS treats it as a minimum.
    private let refreshInterval: () -> TimeInterval
    private let preferences: PreferencesStore
    private let weatherRepository: WeatherRepository
    private let notificationsAuthorized: () async -> Bool
    private let scheduleNotifications: () async -> Void
    private let submitRefreshRequest: (_ earliestBegin: Date) -> Void

    init(
        refreshInterval: (() -> TimeInterval)? = nil,
        preferences: PreferencesStore? = nil,
        weatherRepository: WeatherRepository? = nil,
        notificationsAuthorized: @escaping () async -> Bool = {
            await WeatherNotificationScheduler.shared.isAuthorized()
        },
        scheduleNotifications: @escaping () async -> Void = {
            await WeatherNotificationScheduler.shared.scheduleNotifications()
        },
        submitRefreshRequest: @escaping (_ earliestBegin: Date) -> Void = { earliestBegin in
            let request = BGAppRefreshTaskRequest(identifier: WeatherBackgroundRefresher.taskIdentifier)
            request.earliestBeginDate = earliestBegin
            // Fails on the simulator and when Background App Refresh is off; nothing to recover.
            try? BGTaskScheduler.shared.submit(request)
        }
    ) {
        self.refreshInterval = refreshInterval ?? { RemoteConfigRepository.shared.refreshInterval }
        self.preferences = preferences ?? .shared
        self.weatherRepository = weatherRepository ?? WeatherRepository()
        self.notificationsAuthorized = notificationsAuthorized
        self.scheduleNotifications = scheduleNotifications
        self.submitRefreshRequest = submitRefreshRequest
    }

    /// Asks iOS for the next refresh. A new request replaces any pending one.
    func scheduleNextRefresh(after interval: TimeInterval? = nil) {
        submitRefreshRequest(Date(timeIntervalSinceNow: interval ?? refreshInterval()))
    }

    /// Entry point for the `BGAppRefreshTask`.
    func handleAppRefresh() async {
        // Queue the next run first so the chain survives this one being cut short.
        scheduleNextRefresh()
        if await performRefresh() == .retry {
            scheduleNextRefresh(after: Self.retryInterval)
        }
    }

    /// `replan` replans the notifications even when the refresh fails or there's no city left, for
    /// when the notification city itself has changed and the old plan is wrong either way.
    @discardableResult
    func performRefresh(replan: Bool = false) async -> NotificationWorkerResult {
        let locations = preferences.savedLocations
        let notificationLocation = locations.notificationLocation
        let cacheKey = notificationLocation?.cacheKey
        // Same display-name rule as the foreground refresh in WeatherForecastViewModel.
        let usesApiCityName = notificationLocation?.isCurrentLocation == true

        let authorized = await notificationsAuthorized()
        var refreshed = false

        let logic = NotificationWorkerLogic(
            getSavedLocations: { locations },
            getUnits: { [preferences] in
                WeatherUnitsResolver.resolve(override: preferences.unitOverride)
            },
            fetchCurrentWeather: { [preferences, weatherRepository] units, label, latitude, longitude in
                let result = await weatherRepository.fetchCurrentWeather(
                    units: units,
                    locationLabel: usesApiCityName ? "" : label,
                    cityQuery: latitude == nil || longitude == nil ? label : nil,
                    latitude: latitude,
                    longitude: longitude
                )
                if case .success(let weather) = result, let cacheKey {
                    preferences.setCachedWeather(weather, for: cacheKey)
                }
                return result
            },
            fetchForecast: { [preferences, weatherRepository] units, label, latitude, longitude in
                let result = await weatherRepository.fetchForecast(
                    units: units,
                    cityQuery: latitude == nil || longitude == nil ? label : nil,
                    latitude: latitude,
                    longitude: longitude
                )
                if case .success(let days) = result, let cacheKey {
                    preferences.setCachedForecast(days, for: cacheKey)
                }
                return result
            },
            hasNotificationPermission: { authorized },
            onRefreshed: { refreshed = true }
        )

        let result = await logic.doWork()
        if refreshed || replan {
            await scheduleNotifications()
        }
        // The city tab last viewed, which the app opens to, when it's another one: so that doesn't
        // open on an old cache either. After the notifications, which matter more if time runs out,
        // and not part of the result. Same as Android's background refresh.
        let activeIndex = preferences.activeLocationIndex
        if locations.indices.contains(activeIndex), locations[activeIndex].cacheKey != cacheKey {
            await refreshCache(for: locations[activeIndex])
        }
        return result
    }

    /// Fetches `location`'s weather and forecast and caches whatever comes back, as the foreground
    /// refresh does.
    private func refreshCache(for location: SavedLocation) async {
        let units = WeatherUnitsResolver.resolve(override: preferences.unitOverride)
        let cityQuery = location.latitude == nil || location.longitude == nil ? location.label : nil
        let weather = await weatherRepository.fetchCurrentWeather(
            units: units,
            locationLabel: location.isCurrentLocation ? "" : location.label,
            cityQuery: cityQuery,
            latitude: location.latitude,
            longitude: location.longitude
        )
        if case .success(let weather) = weather {
            preferences.setCachedWeather(weather, for: location.cacheKey)
        }
        let forecast = await weatherRepository.fetchForecast(
            units: units,
            cityQuery: cityQuery,
            latitude: location.latitude,
            longitude: location.longitude
        )
        if case .success(let days) = forecast {
            preferences.setCachedForecast(days, for: location.cacheKey)
        }
    }
}
