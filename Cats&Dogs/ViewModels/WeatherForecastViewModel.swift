import Foundation
import Observation

/// The weather screen: what it shows for the city on screen, and what it does and in what order.
/// It refreshes that city when it changes, on returning to the app and every half hour; moves My
/// Location to where the phone is (or adds it once location access turns up); refreshes the
/// notification city when that changes; and works out the screen state from the cache and what
/// comes back. The view only tells it what happened. Same as Android's `WeatherForecastViewModel`.
@MainActor
@Observable
final class WeatherForecastViewModel {
    /// What the screen shows for the active city at the screen's clock: the reading (or the
    /// forecast hour standing in for an old one), the hero, the walk verdict, the tiles and the
    /// sections the settings switch on. Worked out again only when something it's made from
    /// changes (each of those properties rebuilds it, as does a Remote Config activation), not on
    /// every redraw. Same as Android's `WeatherForecastViewModel.screen`.
    private(set) var screen: WeatherScreen = .loading

    private(set) var currentWeather: LoadingState<CurrentWeather> = .idle {
        didSet { rebuildScreen() }
    }
    private(set) var forecast: LoadingState<[DayForecast]> = .idle {
        didSet { rebuildScreen() }
    }
    private(set) var isRefreshing = false
    /// Set when a refresh fails while weather is already on screen, so the screen can say the data
    /// is old and why; nil once a refresh succeeds or the user moves to another city.
    private(set) var staleErrorKey: String? {
        didSet { rebuildScreen() }
    }
    /// The screen's clock: what "now" is for everything shown. It moves on with `tick()` (on
    /// refreshes, returning to the app and a regular timer), so past hours drop off together.
    private(set) var now: Date {
        didSet { rebuildScreen() }
    }
    /// The user's settings the screen goes by, passed on by the view with `displaySettingsChanged`:
    /// "I have a dog" (the walk card and Paw Check), and visibility in miles.
    private(set) var hasDog = true {
        didSet { rebuildScreen() }
    }
    private(set) var distanceInMiles = false {
        didSet { rebuildScreen() }
    }

    /// The quiet refresh while the app stays open, so a screen left on overnight keeps up.
    static let autoRefreshInterval: Duration = .seconds(30 * 60)

    private let repository: LocationWeatherRepository
    @ObservationIgnored private let cities: CityRepository
    @ObservationIgnored private let position: any DevicePositioning
    @ObservationIgnored private let follower: MyLocationFollower
    private let refreshNotificationCity: @MainActor () async -> Void
    private let sleep: (Duration) async throws -> Void
    private let replanNotifications: @MainActor () async -> Void
    private let onError: @MainActor (_ errorKey: String) -> Void
    private let onSettingsOpened: @MainActor () -> Void
    private let foregroundRefreshMinInterval: () -> TimeInterval
    private let config: () -> WeatherScreenConfig
    private let clock: () -> Date

    /// When each city's data last arrived, for throttling the silent foreground refresh.
    private var currentFetchedAt: [String: Date] = [:]
    private var forecastFetchedAt: [String: Date] = [:]

    private var currentFetchGeneration = 0
    private var forecastFetchGeneration = 0
    private var currentRefreshing = false
    private var forecastRefreshing = false
    private var currentTargetKey: String?
    private var forecastTargetKey: String?
    private var replanTask: Task<Void, Never>?
    /// Location access at the last check, to spot it being granted later in the Settings app.
    private var locationWasGranted: Bool?
    /// A position is being read, so another check doesn't start one too.
    private var locating = false
    /// Off until the end of init, so the properties set there don't each build the screen.
    @ObservationIgnored private var buildsScreen = false

    init(
        repository: LocationWeatherRepository? = nil,
        cities: CityRepository? = nil,
        position: (any DevicePositioning)? = nil,
        follower: MyLocationFollower? = nil,
        refreshNotificationCity: (@MainActor () async -> Void)? = nil,
        sleep: ((Duration) async throws -> Void)? = nil,
        replanNotifications: (@MainActor () async -> Void)? = nil,
        onError: (@MainActor (_ errorKey: String) -> Void)? = nil,
        onSettingsOpened: (@MainActor () -> Void)? = nil,
        foregroundRefreshMinInterval: (() -> TimeInterval)? = nil,
        config: (() -> WeatherScreenConfig)? = nil,
        now: (() -> Date)? = nil,
        notificationCenter: NotificationCenter? = nil
    ) {
        // Optional closures filled in here rather than closure default values: Swift 6.1 (CI's
        // Xcode 16.4) crashes emitting the module for isolated closure defaults.
        self.repository = repository ?? LocationWeatherRepository()
        self.cities = cities ?? CityRepository()
        self.position = position ?? LocationRepository.shared
        self.follower = follower ?? .shared
        self.refreshNotificationCity = refreshNotificationCity ?? {
            await WeatherBackgroundRefresher.shared.performRefresh(replan: true)
        }
        self.sleep = sleep ?? { try await Task.sleep(for: $0) }
        self.replanNotifications = replanNotifications ?? { await WeatherNotificationScheduler.shared.scheduleNotifications() }
        self.onError = onError ?? { AnalyticsRepository.shared.logWeatherError($0) }
        self.onSettingsOpened = onSettingsOpened ?? { AnalyticsRepository.shared.logSettingsOpened() }
        self.foregroundRefreshMinInterval = foregroundRefreshMinInterval ?? {
            RemoteConfigRepository.shared.foregroundRefreshMinInterval
        }
        self.config = config ?? { .live }
        let clock = now ?? { Date() }
        self.clock = clock
        self.now = clock()
        buildsScreen = true
        rebuildScreen()
        // Values fetched while the app is open apply at once, not from the next restart. The
        // observer holds the view model weakly, and the app's one lives as long as the app.
        (notificationCenter ?? .default).addObserver(
            forName: RemoteConfigRepository.didActivate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.remoteConfigActivated() }
        }
    }

    /// Moves the screen's clock on to the time now.
    func tick() {
        now = clock()
    }

    // MARK: - The cities

    var locations: [SavedLocation] { cities.locations }
    var activeIndex: Int { cities.activeIndex }
    var activeLocation: SavedLocation? { cities.activeLocation }

    /// Follow my location's moves of My Location in storage, for the view to pass on with
    /// `myLocationMoved()`.
    var myLocationMoves: Int { follower.moves }

    // MARK: - What happened on screen

    /// The screen first shows.
    func appeared() {
        refreshActiveCity()
        updateMyLocation()
    }

    /// The app comes back to the foreground: the clock moves on, the city on screen is quietly
    /// refreshed, My Location follows the phone, and cities added by name get their coordinates.
    func becameActive() {
        tick()
        quietlyRefreshActiveCity()
        updateMyLocation()
        cities.fillInMissingCoordinates()
    }

    /// A city tab was picked.
    func selectCity(_ index: Int) {
        cities.setActiveIndex(index)
    }

    /// A city added from the empty screen's Add location.
    func addCity(_ location: SavedLocation, added: CityAdded?) {
        cities.addLocation(location, added: added)
    }

    /// Another city is on screen: a real refetch.
    func activeCityChanged() {
        refreshActiveCity()
    }

    /// The units changed (the cache is in the old ones): a real refetch.
    func unitsChanged() {
        refreshActiveCity()
    }

    /// The settings the screen goes by, from the view: on first showing and whenever they change.
    func displaySettingsChanged(hasDog: Bool, distanceInMiles: Bool) {
        if self.hasDog != hasDog { self.hasDog = hasDog }
        if self.distanceInMiles != distanceInMiles { self.distanceInMiles = distanceInMiles }
    }

    /// New Remote Config values are active: switches, thresholds and themes apply straight away.
    func remoteConfigActivated() {
        rebuildScreen()
    }

    /// The retry buttons.
    func retry() {
        refreshActiveCity()
    }

    /// Notifications are for My Location, otherwise the first city, whichever tab is showing. When
    /// that changes (reordered, added, removed, or My Location moved), its weather may not be cached
    /// yet: it's fetched, then the notifications are replanned.
    func notificationCityChanged() async {
        await refreshNotificationCity()
    }

    /// Follow my location moved My Location in storage while the app is open: the screen takes the
    /// move up, and the new place's weather comes with the active city changing.
    func myLocationMoved() {
        cities.followStoredMyLocation()
    }

    /// Pull to refresh. On My Location the phone's position is read first, whatever the 15-minute
    /// limit, so My Location moves (by the usual 1 km rule) before its weather is fetched: a drive
    /// with the screen on never returns to the app, so this is how to catch up by hand. Returns once
    /// the fetch is done, so the spinner stays up until then.
    func pulledToRefresh() async {
        if cities.activeLocation?.isCurrentLocation == true, let here = await position.currentPosition() {
            cities.noteMyLocationChecked()
            cities.updateCurrentLocation(here)
        }
        // At once, after a move too, so the spinner waits on a fetch already under way.
        refreshActiveCity()
        await waitForRefresh()
    }

    // MARK: - While the screen is up

    /// The quiet refresh every half hour, run by the view while the app is active, until cancelled.
    func refreshWhileActive() async {
        while (try? await sleep(Self.autoRefreshInterval)) != nil, !Task.isCancelled {
            tick()
            quietlyRefreshActiveCity()
        }
    }

    /// While refreshes keep failing, the clock is re-read every few minutes so old weather gives way
    /// to the forecast once it passes the cutoff. Run by the view while there's an error, until
    /// cancelled.
    func recheckWhileStale() async {
        guard staleErrorKey != nil else { return }
        while (try? await sleep(StaleWeather.recheckInterval)) != nil, !Task.isCancelled {
            tick()
        }
    }

    // MARK: - Steps

    private func refreshActiveCity() {
        // A refresh also moves "now" on, so the hourly strip and captions update even when the
        // weather itself hasn't changed.
        tick()
        guard let location = cities.activeLocation else { return }
        refreshCurrent(location: location)
        refreshForecast(location: location)
    }

    private func quietlyRefreshActiveCity() {
        guard let location = cities.activeLocation else { return }
        backgroundRefreshCurrent(location: location)
        backgroundRefreshForecast(location: location)
    }

    /// On first showing and each return to the app, with location access on:
    /// - re-reads the position while My Location is saved (at most every 15 minutes), so it follows
    ///   the device rather than staying where it was added;
    /// - otherwise adds it once access turns up after onboarding went without it (granted later in
    ///   the Settings app, say). Only when there are no cities yet, or access has just changed to
    ///   granted, so someone who removed My Location on purpose doesn't get it back every launch.
    private func updateMyLocation() {
        // While a read is under way this check is skipped whole, so a grant made meanwhile is still
        // "newly granted" next time.
        guard !locating else { return }
        let granted = position.hasLocationPermission()
        let newlyGranted = granted && locationWasGranted == false
        locationWasGranted = granted
        guard granted else { return }
        let adding: Bool
        if cities.locations.contains(where: \.isCurrentLocation) {
            guard cities.claimMyLocationCheck() else { return }
            adding = false
        } else if newlyGranted || cities.locations.isEmpty {
            adding = true
        } else {
            return
        }
        locating = true
        Task {
            defer { locating = false }
            guard let here = await position.currentPosition() else { return }
            if cities.locations.contains(where: \.isCurrentLocation) {
                cities.updateCurrentLocation(here)
            } else if adding {
                // A position read only to move My Location, arriving after it was removed, adds nothing.
                cities.addLocation(here)
            }
        }
    }

    private func waitForRefresh() async {
        while isRefreshing, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Fetching

    /// Works `screen` out again from its inputs, reading Remote Config afresh.
    private func rebuildScreen() {
        guard buildsScreen else { return }
        var config = config()
        config.distanceInMiles = distanceInMiles
        screen = WeatherScreen.make(
            current: currentWeather,
            forecast: forecast,
            staleErrorKey: staleErrorKey,
            now: now,
            hasDog: hasDog,
            config: config
        )
    }

    /// The silent refresh on returning to the foreground. Remote Config can make it skip a city that
    /// was fetched recently; explicit refreshes are never skipped.
    func backgroundRefreshCurrent(location: SavedLocation) {
        guard !wasFetchedRecently(currentFetchedAt[location.cacheKey]) else { return }
        Task {
            let result = await repository.refreshWeather(for: location)
            if let target = currentTargetKey, target != location.cacheKey { return }
            switch result {
            case .success(let weather):
                currentFetchedAt[location.cacheKey] = clock()
                currentWeather = .success(weather)
                staleErrorKey = nil
                repository.rememberShownCity(weather.cityName)
                notificationsNeedReplanning()
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
            let result = await repository.refreshForecast(for: location)
            if let target = forecastTargetKey, target != location.cacheKey { return }
            if case .success(let days) = result {
                forecastFetchedAt[location.cacheKey] = clock()
                forecast = .success(days)
                notificationsNeedReplanning()
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
            let cached = repository.cachedWeather(for: location)
            currentWeather = cached.map { .success($0) } ?? .loading
            // The plan is renewed from the cache too, so a week of briefings keeps going offline.
            if cached != nil { notificationsNeedReplanning() }

            let result = await repository.refreshWeather(for: location)

            guard fetchId == currentFetchGeneration else { return }
            switch result {
            case .success(let weather):
                repository.rememberShownCity(weather.cityName)
                notificationsNeedReplanning()
                currentWeather = .success(weather)
                staleErrorKey = nil
                currentFetchedAt[location.cacheKey] = clock()
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
            let cached = repository.cachedForecast(for: location)
            forecast = cached.map { .success($0) } ?? .loading
            if cached != nil { notificationsNeedReplanning() }

            let result = await repository.refreshForecast(for: location)

            guard fetchId == forecastFetchGeneration else { return }
            switch result {
            case .success(let days):
                notificationsNeedReplanning()
                forecast = .success(days)
                forecastFetchedAt[location.cacheKey] = clock()
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
        return window > 0 && clock().timeIntervalSince(fetchedAt) < window
    }

    /// The notifications are planned from the cache, so they're replanned once new weather is in.
    /// A refresh brings a reading and a forecast, so the calls are coalesced into one replan.
    private func notificationsNeedReplanning() {
        replanTask?.cancel()
        replanTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await replanNotifications()
        }
    }

    private func updateRefreshingState() {
        isRefreshing = currentRefreshing || forecastRefreshing
    }
}
