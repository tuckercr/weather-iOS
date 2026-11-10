import Foundation

enum NotificationWorkerResult: Equatable {
    case success
    case retry
}

struct NotificationWorkerLogic {
    let getSavedLocations: () async -> [SavedLocation]
    /// Fetches and caches `location`'s current reading: `LocationWeatherRepository.refreshWeather(for:)`.
    let refreshWeather: (_ location: SavedLocation) async -> Result<CurrentWeather, Error>
    /// Fetches and caches `location`'s forecast: `LocationWeatherRepository.refreshForecast(for:)`.
    let refreshForecast: (_ location: SavedLocation) async -> Result<[DayForecast], Error>
    /// The location's reading and forecast are both recent enough to use as they are:
    /// `LocationWeatherRepository.hasFreshData(for:)`.
    let hasFreshData: (_ location: SavedLocation) async -> Bool
    let hasNotificationPermission: () -> Bool
    /// The caches are fresh and notifications are allowed: time to replan them.
    let onRefreshed: () -> Void

    /// Refreshes the notification city's weather and forecast in the cache, unless both were
    /// fetched in the last 30 minutes, then calls `onRefreshed`. Retries when the current weather
    /// can't be fetched. Same as Android's `WeatherUpdateWorker`.
    func doWork() async -> NotificationWorkerResult {
        guard let location = await getSavedLocations().notificationLocation else { return .success }

        if await !hasFreshData(location) {
            guard case .success = await refreshWeather(location) else { return .retry }
            _ = await refreshForecast(location)
        }

        guard hasNotificationPermission() else { return .success }
        onRefreshed()
        return .success
    }
}
