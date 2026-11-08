import Foundation

/// The weather for the saved locations, cache first: what's cached for a location, and refreshes
/// that fetch it in the user's units and cache what comes back. The one way the screen, the
/// background refresh and the notifications get weather, so they always agree on the units and the
/// cache. Same as Android's `LocationWeatherRepository`.
@MainActor
final class LocationWeatherRepository {
    private let weatherRepository: WeatherRepository
    private let preferences: PreferencesStore

    init(weatherRepository: WeatherRepository? = nil, preferences: PreferencesStore? = nil) {
        self.weatherRepository = weatherRepository ?? WeatherRepository()
        self.preferences = preferences ?? .shared
    }

    /// The user's units: Settings' choice, or the device's.
    var units: WeatherUnits {
        WeatherUnitsResolver.resolve(override: preferences.unitOverride)
    }

    func cachedWeather(for location: SavedLocation) -> CurrentWeather? {
        preferences.cachedWeather(for: location.cacheKey)
    }

    func cachedForecast(for location: SavedLocation) -> [DayForecast]? {
        preferences.cachedForecast(for: location.cacheKey)
    }

    /// When `location`'s cached forecast was fetched; nil for one cached before that was kept.
    func forecastFetchedAt(for location: SavedLocation) -> Date? {
        preferences.cachedForecastFetchedAt(for: location.cacheKey)
    }

    /// Fetches `location`'s current reading and caches it. A fetch the screen has since moved on
    /// from is still cached: it's that location's weather.
    func refreshWeather(for location: SavedLocation) async -> Result<CurrentWeather, Error> {
        let result = await weatherRepository.fetchCurrentWeather(for: location, units: units)
        if case .success(let weather) = result {
            preferences.setCachedWeather(weather, for: location.cacheKey)
        }
        return result
    }

    /// Keeps the city last shown, which the city list falls back to when it has none.
    func rememberShownCity(_ cityName: String) {
        preferences.setLastCity(cityName)
    }

    /// Fetches `location`'s forecast and caches it, with when it was fetched.
    func refreshForecast(for location: SavedLocation) async -> Result<[DayForecast], Error> {
        let result = await weatherRepository.fetchForecast(for: location, units: units)
        if case .success(let days) = result {
            preferences.setCachedForecast(days, for: location.cacheKey)
        }
        return result
    }
}
