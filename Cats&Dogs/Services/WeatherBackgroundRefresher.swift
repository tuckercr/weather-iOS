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
    private let repository: LocationWeatherRepository
    private let notificationsAuthorized: () async -> Bool
    private let scheduleNotifications: () async -> Void
    private let submitRefreshRequest: (_ earliestBegin: Date) -> Void
    private let followMyLocation: () -> Void

    init(
        refreshInterval: (() -> TimeInterval)? = nil,
        preferences: PreferencesStore? = nil,
        repository: LocationWeatherRepository? = nil,
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
        },
        followMyLocation: (() -> Void)? = nil
    ) {
        self.refreshInterval = refreshInterval ?? { RemoteConfigRepository.shared.refreshInterval }
        self.preferences = preferences ?? .shared
        self.repository = repository ?? LocationWeatherRepository(preferences: preferences)
        self.notificationsAuthorized = notificationsAuthorized
        self.scheduleNotifications = scheduleNotifications
        self.submitRefreshRequest = submitRefreshRequest
        self.followMyLocation = followMyLocation ?? { MyLocationFollower.shared.followLastKnownPosition() }
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
        // With Follow my location on, My Location first moves to where the phone was last seen.
        followMyLocation()
        let locations = preferences.savedLocations
        let cacheKey = locations.notificationLocation?.cacheKey

        let authorized = await notificationsAuthorized()
        var refreshed = false

        let logic = NotificationWorkerLogic(
            getSavedLocations: { locations },
            refreshWeather: { [repository] in await repository.refreshWeather(for: $0) },
            refreshForecast: { [repository] in await repository.refreshForecast(for: $0) },
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
            _ = await repository.refreshWeather(for: locations[activeIndex])
            _ = await repository.refreshForecast(for: locations[activeIndex])
        }
        return result
    }
}
