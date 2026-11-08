import Foundation
import Observation

@MainActor
@Observable
final class WeatherForecastViewModel {
    private(set) var currentWeather: LoadingState<CurrentWeather> = .idle
    private(set) var forecast: LoadingState<[DayForecast]> = .idle
    private(set) var isRefreshing = false
    /// Set when a refresh fails while weather is already on screen, so the screen can say the data
    /// is old and why; nil once a refresh succeeds or the user moves to another city.
    private(set) var staleErrorKey: String?

    private let preferences: PreferencesStore
    private let weatherRepository: WeatherRepository
    private let onError: @MainActor (_ errorKey: String) -> Void
    private let onSettingsOpened: @MainActor () -> Void
    private let foregroundRefreshMinInterval: () -> TimeInterval
    private let petWeatherThresholds: () -> PetWeatherThresholds
    private let now: () -> Date

    /// When each city's data last arrived, for throttling the silent foreground refresh.
    private var currentFetchedAt: [String: Date] = [:]
    private var forecastFetchedAt: [String: Date] = [:]

    private var currentFetchGeneration = 0
    private var forecastFetchGeneration = 0
    private var currentRefreshing = false
    private var forecastRefreshing = false
    private var currentTargetKey: String?
    private var forecastTargetKey: String?

    init(
        preferences: PreferencesStore? = nil,
        weatherRepository: WeatherRepository? = nil,
        onError: (@MainActor (_ errorKey: String) -> Void)? = nil,
        onSettingsOpened: (@MainActor () -> Void)? = nil,
        foregroundRefreshMinInterval: (() -> TimeInterval)? = nil,
        petWeatherThresholds: (() -> PetWeatherThresholds)? = nil,
        now: (() -> Date)? = nil
    ) {
        // Optional closures filled in here rather than closure default values: Swift 6.1 (CI's
        // Xcode 16.4) crashes emitting the module for isolated closure defaults.
        self.preferences = preferences ?? .shared
        self.weatherRepository = weatherRepository ?? WeatherRepository()
        self.onError = onError ?? { AnalyticsRepository.shared.logWeatherError($0) }
        self.onSettingsOpened = onSettingsOpened ?? { AnalyticsRepository.shared.logSettingsOpened() }
        self.foregroundRefreshMinInterval = foregroundRefreshMinInterval ?? {
            RemoteConfigRepository.shared.foregroundRefreshMinInterval
        }
        self.petWeatherThresholds = petWeatherThresholds ?? { RemoteConfigRepository.shared.petWeatherThresholds }
        self.now = now ?? { Date() }
    }

    /// The walk verdict for `weather` (the reading on screen, or the forecast hour standing in for an
    /// old one) at the screen's `now`, from the forecast's hours. Nil while the forecast is loading
    /// or failed, which hides the walk card rather than advising on nothing. The hero's caption and
    /// the walk card both read it.
    func walkAdvice(for weather: CurrentWeather, at now: Date, hasDog: Bool) -> WalkAdvice? {
        guard let days = forecast.successValue else { return nil }
        return WalkAdvisor.advice(for: weather, forecast: days, at: now, thresholds: petWeatherThresholds(), hasDog: hasDog)
    }

    /// The silent refresh on returning to the foreground. Remote Config can make it skip a city that
    /// was fetched recently; explicit refreshes are never skipped.
    func backgroundRefreshCurrent(location: SavedLocation) {
        guard !wasFetchedRecently(currentFetchedAt[location.cacheKey]) else { return }
        Task {
            let units = resolvedUnits()
            let result = await weatherRepository.fetchCurrentWeather(for: location, units: units)
            if let target = currentTargetKey, target != location.cacheKey { return }
            switch result {
            case .success(let weather):
                currentFetchedAt[location.cacheKey] = now()
                currentWeather = .success(weather)
                staleErrorKey = nil
                preferences.setLastCity(weather.cityName)
                preferences.setCachedWeather(weather, for: location.cacheKey)
            case .failure(let error):
                if case .success = currentWeather {
                    staleErrorKey = WeatherErrorMessages.errorKey(for: error)
                }
            }
        }
    }

    func backgroundRefreshForecast(location: SavedLocation) {
        guard !wasFetchedRecently(forecastFetchedAt[location.cacheKey]) else { return }
        Task {
            let units = resolvedUnits()
            let result = await weatherRepository.fetchForecast(for: location, units: units)
            if let target = forecastTargetKey, target != location.cacheKey { return }
            if case .success(let days) = result {
                forecastFetchedAt[location.cacheKey] = now()
                forecast = .success(days)
                preferences.setCachedForecast(days, for: location.cacheKey)
            }
        }
    }

    func refreshCurrent(location: SavedLocation) {
        if currentTargetKey != location.cacheKey { staleErrorKey = nil }
        currentTargetKey = location.cacheKey
        currentFetchGeneration += 1
        let fetchId = currentFetchGeneration
        currentRefreshing = true
        updateRefreshingState()

        Task {
            let cached = preferences.cachedWeather(for: location.cacheKey)
            currentWeather = cached.map { .success($0) } ?? .loading

            let units = resolvedUnits()
            let result = await weatherRepository.fetchCurrentWeather(for: location, units: units)

            guard fetchId == currentFetchGeneration else { return }
            switch result {
            case .success(let weather):
                preferences.setLastCity(weather.cityName)
                preferences.setCachedWeather(weather, for: location.cacheKey)
                currentWeather = .success(weather)
                staleErrorKey = nil
                currentFetchedAt[location.cacheKey] = now()
            case .failure(let error):
                let errorKey = WeatherErrorMessages.errorKey(for: error)
                onError(errorKey)
                // Keep cached data visible if there is any, flagged as old; only show the error on
                // its own when there's nothing.
                if cached == nil {
                    currentWeather = .error(
                        errorKey: errorKey,
                        canRetry: WeatherErrorMessages.canRetry(for: error)
                    )
                } else {
                    staleErrorKey = errorKey
                }
            }

            if fetchId == currentFetchGeneration {
                currentRefreshing = false
                updateRefreshingState()
            }
        }
    }

    func refreshForecast(location: SavedLocation) {
        forecastTargetKey = location.cacheKey
        forecastFetchGeneration += 1
        let fetchId = forecastFetchGeneration
        forecastRefreshing = true
        updateRefreshingState()

        Task {
            let cached = preferences.cachedForecast(for: location.cacheKey)
            forecast = cached.map { .success($0) } ?? .loading

            let units = resolvedUnits()
            let result = await weatherRepository.fetchForecast(for: location, units: units)

            guard fetchId == forecastFetchGeneration else { return }
            switch result {
            case .success(let days):
                preferences.setCachedForecast(days, for: location.cacheKey)
                forecast = .success(days)
                forecastFetchedAt[location.cacheKey] = now()
            case .failure(let error):
                let errorKey = WeatherErrorMessages.errorKey(for: error)
                onError(errorKey)
                // Keep cached data visible if there is any; only show the error when there's nothing.
                if cached == nil {
                    forecast = .error(
                        errorKey: errorKey,
                        canRetry: WeatherErrorMessages.canRetry(for: error)
                    )
                }
            }

            if fetchId == forecastFetchGeneration {
                forecastRefreshing = false
                updateRefreshingState()
            }
        }
    }

    func logSettingsOpened() {
        onSettingsOpened()
    }

    func clearCurrentError() {
        if case .error = currentWeather {
            currentWeather = .idle
        }
    }

    func clearForecastError() {
        if case .error = forecast {
            forecast = .idle
        }
    }

    private func wasFetchedRecently(_ fetchedAt: Date?) -> Bool {
        guard let fetchedAt else { return false }
        let window = foregroundRefreshMinInterval()
        return window > 0 && now().timeIntervalSince(fetchedAt) < window
    }

    private func resolvedUnits() -> WeatherUnits {
        WeatherUnitsResolver.resolve(override: preferences.unitOverride)
    }

    private func updateRefreshingState() {
        isRefreshing = currentRefreshing || forecastRefreshing
    }
}
