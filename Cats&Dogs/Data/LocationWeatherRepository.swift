import Foundation

/// The weather for the saved locations, cache first: what's cached for a location, and refreshes
/// that fetch it in the user's units and cache what comes back. The one way the screen, the
/// background refresh and the notifications get weather, so they always agree on the units and the
/// cache. Same as Android's `LocationWeatherRepository`.
@MainActor
final class LocationWeatherRepository {
    private let weatherRepository: WeatherRepository
    private let preferences: PreferencesStore
    private let now: () -> Date

    init(weatherRepository: WeatherRepository? = nil, preferences: PreferencesStore? = nil, now: (() -> Date)? = nil) {
        self.weatherRepository = weatherRepository ?? WeatherRepository()
        self.preferences = preferences ?? .shared
        self.now = now ?? { Date() }
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
    /// from is still cached (it's that location's weather), unless the units changed meanwhile.
    func refreshWeather(for location: SavedLocation) async -> Result<CurrentWeather, Error> {
        let units = units
        let result = await weatherRepository.fetchCurrentWeather(for: location, units: units)
        // Not cached if the units changed while it was fetched: the cache stays in the new ones.
        if case .success(let weather) = result, self.units == units {
            preferences.setCachedWeather(weather, for: location.cacheKey)
        }
        return result
    }

    /// Keeps the city last shown, which the city list falls back to when it has none.
    func rememberShownCity(_ cityName: String) {
        preferences.setLastCity(cityName)
    }

    /// Fetches `location`'s forecast and caches it, with when it was fetched. Air quality fetched
    /// in the last 3 hours is reused (`AirQualityHours`), whatever the reason for the refresh; new
    /// air quality is cached whatever the units, which it doesn't depend on.
    func refreshForecast(for location: SavedLocation) async -> Result<[DayForecast], Error> {
        let units = units
        let cachedAir = preferences.cachedAirQuality(for: location.cacheKey)
        let result = await weatherRepository.fetchForecast(for: location, units: units, cachedAirQuality: cachedAir)
        if case .success(let fetch) = result {
            if let air = fetch.airQuality, air != cachedAir {
                preferences.setCachedAirQuality(air, for: location.cacheKey)
            }
            if self.units == units {
                preferences.setCachedForecast(fetch.days, for: location.cacheKey, fetchedAt: now())
            }
        }
        return result.map(\.days)
    }
}
