import XCTest
@testable import Cats_Dogs

@MainActor
final class WeatherForecastViewModelTests: XCTestCase {
    private let austin = SavedLocation(label: "Austin", latitude: nil, longitude: nil)
    private let denver = SavedLocation(label: "Denver", latitude: nil, longitude: nil)
    private let pinned = SavedLocation(label: "Austin, Texas, US", latitude: 30.27, longitude: -97.74)
    private let offline = OpenWeatherClientError.network

    private var preferences: IsolatedPreferences!
    private var api: ScriptedWeatherAPI!
    private var viewModel: WeatherForecastViewModel!
    private var loggedErrors: [String] = []
    private var settingsOpenedCount = 0
    private var replans = 0
    private var foregroundRefreshWindow: TimeInterval = 0
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        preferences = IsolatedPreferences()
        preferences.store.setUnitOverride(.metric)
        api = ScriptedWeatherAPI()
        loggedErrors = []
        settingsOpenedCount = 0
        replans = 0
        foregroundRefreshWindow = 0
        clock = Date(timeIntervalSince1970: 1_700_000_000)
        viewModel = WeatherForecastViewModel(
            repository: LocationWeatherRepository(weatherRepository: api.repository, preferences: preferences.store),
            replanNotifications: { [unowned self] in replans += 1 },
            onError: { [unowned self] in loggedErrors.append($0) },
            onSettingsOpened: { [unowned self] in settingsOpenedCount += 1 },
            foregroundRefreshMinInterval: { [unowned self] in foregroundRefreshWindow },
            config: { WeatherScreenConfig() },
            now: { [unowned self] in clock }
        )
    }

    override func tearDown() async throws {
        preferences.destroy()
    }

    // MARK: - Clock and screen

    func testTheClockOnlyMovesOnWithTick() {
        let start = viewModel.now
        clock = clock.addingTimeInterval(3_600)
        XCTAssertEqual(viewModel.now, start)
        viewModel.tick()
        XCTAssertEqual(viewModel.now, clock)
    }

    func testTheScreenLoadsThenShowsTheReadingAtTheClock() async {
        guard case .loading = viewModel.screen(hasDog: true) else { return XCTFail("expected loading") }

        viewModel.refreshCurrent(location: pinned)
        await waitUntil { self.viewModel.currentWeather.successValue != nil }
        guard case let .weather(state) = viewModel.screen(hasDog: true) else { return XCTFail("expected weather") }
        XCTAssertEqual(state.now, viewModel.now)
        XCTAssertEqual(state.weather.cityName, "Austin, Texas, US")
        XCTAssertNil(state.stale)
    }

    func testWalkAdviceComesFromTheLoadedForecastAndIsNilUntilThen() async {
        viewModel.refreshCurrent(location: pinned)
        await waitUntil { self.viewModel.currentWeather.successValue != nil }
        guard case let .weather(before) = viewModel.screen(hasDog: true) else { return XCTFail("expected weather") }
        XCTAssertNil(before.walkAdvice)
        XCTAssertFalse(before.showsWalkCard)

        viewModel.refreshForecast(location: pinned)
        await waitUntil { self.viewModel.forecast.successValue != nil }
        clock = viewModel.forecast.successValue?.first?.hourlySlots.first?.date ?? clock
        viewModel.tick()
        guard case let .weather(after) = viewModel.screen(hasDog: true) else { return XCTFail("expected weather") }
        XCTAssertNotNil(after.walkAdvice)
    }

    // MARK: - Notifications

    func testNewWeatherReplansTheNotificationsOnce() async {
        viewModel.refreshCurrent(location: pinned)
        viewModel.refreshForecast(location: pinned)
        await waitUntil(timeout: 4) { self.replans > 0 }
        try? await Task.sleep(for: .milliseconds(1_500))
        XCTAssertEqual(replans, 1)
    }

    func testAFailedRefreshDoesNotReplan() async {
        api.onCurrent = { _ in throw self.offline }
        viewModel.refreshCurrent(location: austin)
        await waitUntil { self.loggedErrors.count == 1 }
        try? await Task.sleep(for: .milliseconds(1_500))
        XCTAssertEqual(replans, 0)
    }

    // MARK: - Request routing

    func testCurrentWeatherWithCoordinatesPassesLatLonAndNilCityQuery() async {
        viewModel.refreshCurrent(location: pinned)
        await waitUntil { self.viewModel.currentWeather.successValue != nil }

        XCTAssertEqual(
            api.currentRequests,
            [WeatherRequest(cityQuery: nil, latitude: 30.27, longitude: -97.74, units: .metric)]
        )
        XCTAssertEqual(viewModel.currentWeather.successValue?.cityName, "Austin, Texas, US")
    }

    func testCurrentWeatherWithoutCoordinatesUsesLabelAsCityQuery() async {
        viewModel.refreshCurrent(location: austin)
        await waitUntil { self.viewModel.currentWeather.successValue != nil }

        XCTAssertEqual(
            api.currentRequests,
            [WeatherRequest(cityQuery: "Austin", latitude: nil, longitude: nil, units: .metric)]
        )
    }

    func testForecastWithCoordinatesComesFromOpenMeteo() async {
        viewModel.refreshForecast(location: pinned)
        await waitUntil { self.viewModel.forecast.successValue != nil }

        // Cities with coordinates get their forecast from Open-Meteo, not OpenWeatherMap.
        XCTAssertTrue(api.forecastRequests.isEmpty)
        XCTAssertEqual(api.openMeteo.requests.map(\.latitude), [30.27])
        XCTAssertEqual(api.openMeteo.requests.map(\.longitude), [-97.74])
    }

    func testRequestsUseTheUnitOverrideFromSettings() async {
        preferences.store.setUnitOverride(.imperial)

        viewModel.refreshCurrent(location: austin)
        await waitUntil { self.viewModel.currentWeather.successValue != nil }

        XCTAssertEqual(api.currentRequests.first?.units, .imperial)
        XCTAssertEqual(viewModel.currentWeather.successValue?.units, .imperial)
    }

    func testRefreshAfterAUnitChangeReplacesDataCachedInTheOldUnits() async {
        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }
        XCTAssertEqual(viewModel.currentWeather.successValue?.units, .metric)

        preferences.store.setUnitOverride(.imperial)
        viewModel.refreshCurrent(location: austin)
        await waitUntil { self.viewModel.currentWeather.successValue?.units == .imperial }

        XCTAssertEqual(api.currentRequests.map(\.units), [.metric, .imperial])
        XCTAssertEqual(preferences.store.cachedWeather(for: austin.cacheKey)?.units, .imperial)
    }

    func testCurrentLocationShowsTheCityNameDetectedByTheApi() async {
        api.onCurrent = { _ in weatherResponse(name: "Detected City") }
        let myLocation = SavedLocation(label: "My Location", latitude: 37.77, longitude: -122.42, isCurrentLocation: true)

        viewModel.refreshCurrent(location: myLocation)
        await waitUntil { self.viewModel.currentWeather.successValue != nil }

        XCTAssertEqual(viewModel.currentWeather.successValue?.cityName, "Detected City")
    }

    // MARK: - Foreground refresh

    func testSuccessfulRefreshCachesResultAndRemembersLastCity() async {
        viewModel.refreshCurrent(location: austin)
        viewModel.refreshForecast(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(preferences.store.cachedWeather(for: austin.cacheKey)?.cityName, "Austin")
        XCTAssertEqual(preferences.store.cachedForecast(for: austin.cacheKey)?.count, 1)
        XCTAssertEqual(preferences.store.lastCity, "Austin")
    }

    func testIsRefreshingStaysTrueUntilBothCurrentAndForecastFinish() async {
        let forecastGate = Gate<ForecastResponse>()
        api.onForecast = { _ in try await forecastGate.value() }

        viewModel.refreshCurrent(location: austin)
        viewModel.refreshForecast(location: austin)
        XCTAssertTrue(viewModel.isRefreshing)
        await waitUntil { self.viewModel.currentWeather.successValue != nil }
        await settle()
        XCTAssertTrue(viewModel.isRefreshing, "Forecast is still in flight")

        forecastGate.succeed(forecastResponse())
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertNotNil(viewModel.forecast.successValue)
    }

    func testLatestCurrentWeatherRequestWinsWhenAnEarlierRequestFinishesLast() async {
        let firstRequest = Gate<CurrentWeatherResponse>()
        let secondRequest = Gate<CurrentWeatherResponse>()
        api.onCurrent = { request in
            try await (request.cityQuery == "Austin" ? firstRequest : secondRequest).value()
        }

        viewModel.refreshCurrent(location: austin)
        await waitUntil { self.api.currentRequests.count == 1 }
        viewModel.refreshCurrent(location: denver)
        await waitUntil { self.api.currentRequests.count == 2 }

        secondRequest.succeed(weatherResponse(name: "Denver"))
        await waitUntil { self.viewModel.currentWeather.successValue != nil }
        firstRequest.succeed(weatherResponse(name: "Austin"))
        await waitUntil { self.api.completedCurrentRequests == 2 }
        await settle()

        XCTAssertEqual(api.currentRequests.map(\.cityQuery), ["Austin", "Denver"])
        XCTAssertEqual(viewModel.currentWeather.successValue?.cityName, "Denver")
        XCTAssertEqual(preferences.store.lastCity, "Denver")
        // Still cached under its own city: it's Austin's weather, just not what's on screen.
        XCTAssertEqual(preferences.store.cachedWeather(for: austin.cacheKey)?.cityName, "Austin")
        XCTAssertEqual(preferences.store.cachedWeather(for: denver.cacheKey)?.cityName, "Denver")
        XCTAssertFalse(viewModel.isRefreshing)
    }

    // MARK: - Errors

    func testCurrentWeatherNetworkFailureMapsToRetryableErrorAndCanBeCleared() async {
        api.onCurrent = { _ in throw self.offline }

        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(viewModel.currentWeather, .error(errorKey: "offline", canRetry: true))

        viewModel.clearCurrentError()
        XCTAssertEqual(viewModel.currentWeather, .idle)
    }

    func testForecastNetworkFailureMapsToRetryableErrorAndCanBeCleared() async {
        api.onForecast = { _ in throw self.offline }

        viewModel.refreshForecast(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(viewModel.forecast, .error(errorKey: "offline", canRetry: true))

        viewModel.clearForecastError()
        XCTAssertEqual(viewModel.forecast, .idle)
    }

    func testCityNotFoundIsNotRetryable() async {
        api.onCurrent = { _ in throw OpenWeatherClientError.http(statusCode: 404, message: "city not found") }

        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(viewModel.currentWeather, .error(errorKey: "city_not_found", canRetry: false))
    }

    func testClearErrorLeavesSuccessfulStateAlone() async {
        viewModel.refreshCurrent(location: austin)
        await waitUntil { self.viewModel.currentWeather.successValue != nil }

        viewModel.clearCurrentError()

        XCTAssertNotNil(viewModel.currentWeather.successValue)
    }

    // MARK: - Cache

    func testCachedCurrentWeatherIsShownImmediatelyWhileFetchIsInFlight() async {
        preferences.store.setCachedWeather(await makeCurrentWeather(temperature: 5), for: austin.cacheKey)
        let gate = Gate<CurrentWeatherResponse>()
        api.onCurrent = { _ in try await gate.value() }

        viewModel.refreshCurrent(location: austin)
        await waitUntil { self.api.currentRequests.count == 1 }

        XCTAssertEqual(viewModel.currentWeather.successValue?.temperature, 5)
        XCTAssertTrue(viewModel.isRefreshing)

        gate.succeed(weatherResponse(name: "Austin", temperature: 25))
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(viewModel.currentWeather.successValue?.temperature, 25)
    }

    func testNetworkErrorIsSuppressedWhenCachedCurrentWeatherIsAvailable() async {
        preferences.store.setCachedWeather(await makeCurrentWeather(temperature: 5), for: austin.cacheKey)
        api.onCurrent = { _ in throw self.offline }

        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(viewModel.currentWeather.successValue?.temperature, 5)
    }

    func testFailedRefreshOverCachedWeatherFlagsItAsStaleUntilARefreshSucceeds() async {
        preferences.store.setCachedWeather(await makeCurrentWeather(temperature: 5), for: austin.cacheKey)
        api.onCurrent = { _ in throw self.offline }

        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }
        XCTAssertEqual(viewModel.staleErrorKey, "offline")

        api.onCurrent = { request in weatherResponse(name: request.cityQuery ?? "Somewhere") }
        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }
        XCTAssertNil(viewModel.staleErrorKey)
    }

    func testFailedRefreshWithNothingCachedShowsTheErrorNotTheStaleBanner() async {
        api.onCurrent = { _ in throw self.offline }

        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(viewModel.currentWeather, .error(errorKey: "offline", canRetry: true))
        XCTAssertNil(viewModel.staleErrorKey)
    }

    func testFailedBackgroundRefreshFlagsShownWeatherAsStaleAndSwitchingCityClearsIt() async {
        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }
        api.onCurrent = { _ in throw self.offline }

        viewModel.backgroundRefreshCurrent(location: austin)
        await waitUntil { self.api.completedCurrentRequests == 2 }
        await settle()
        XCTAssertEqual(viewModel.staleErrorKey, "offline")

        viewModel.refreshCurrent(location: denver)
        XCTAssertNil(viewModel.staleErrorKey)
    }

    // MARK: - Foreground refresh throttle

    func testForegroundRefreshSkipsACityFetchedWithinTheWindow() async {
        foregroundRefreshWindow = 10 * 60
        viewModel.refreshCurrent(location: austin)
        viewModel.refreshForecast(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }
        clock += 9 * 60

        viewModel.backgroundRefreshCurrent(location: austin)
        viewModel.backgroundRefreshForecast(location: austin)
        await settle()

        XCTAssertEqual(api.currentRequests.count, 1)
        XCTAssertEqual(api.forecastRequests.count, 1)
    }

    func testForegroundRefreshRunsOnceTheWindowHasPassed() async {
        foregroundRefreshWindow = 10 * 60
        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }
        clock += 11 * 60

        viewModel.backgroundRefreshCurrent(location: austin)
        await waitUntil { self.api.completedCurrentRequests == 2 }

        XCTAssertEqual(api.currentRequests.count, 2)
    }

    func testForegroundRefreshIsNeverSkippedWithAZeroWindow() async {
        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        viewModel.backgroundRefreshCurrent(location: austin)
        await waitUntil { self.api.completedCurrentRequests == 2 }

        XCTAssertEqual(api.currentRequests.count, 2)
    }

    func testExplicitRefreshIsNeverSkipped() async {
        foregroundRefreshWindow = 10 * 60
        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        viewModel.refreshCurrent(location: austin)
        await waitUntil { self.api.completedCurrentRequests == 2 }

        XCTAssertEqual(api.currentRequests.count, 2)
    }

    func testAFailedFetchDoesNotStartTheWindow() async {
        foregroundRefreshWindow = 10 * 60
        api.onCurrent = { _ in throw self.offline }
        viewModel.refreshCurrent(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        viewModel.backgroundRefreshCurrent(location: austin)
        await waitUntil { self.api.completedCurrentRequests == 2 }

        XCTAssertEqual(api.currentRequests.count, 2)
    }

    // MARK: - Analytics

    func testFailuresAreReportedEvenWhenCachedDataHidesThem() async {
        preferences.store.setCachedWeather(await makeCurrentWeather(temperature: 5), for: austin.cacheKey)
        api.onCurrent = { _ in throw self.offline }
        api.onForecast = { _ in throw self.offline }

        viewModel.refreshCurrent(location: austin)
        viewModel.refreshForecast(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(loggedErrors, ["offline", "offline"])
    }

    func testSuccessfulRefreshReportsNoError() async {
        viewModel.refreshCurrent(location: austin)
        viewModel.refreshForecast(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(loggedErrors, [])
    }

    func testLogSettingsOpenedReportsTheEvent() {
        viewModel.logSettingsOpened()

        XCTAssertEqual(settingsOpenedCount, 1)
    }

    func testNetworkErrorIsSuppressedWhenCachedForecastIsAvailable() async {
        let cached = await makeForecast(temperature: 7)
        preferences.store.setCachedForecast(cached, for: austin.cacheKey)
        api.onForecast = { _ in throw self.offline }

        viewModel.refreshForecast(location: austin)
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(viewModel.forecast, .success(cached))
    }

    func testCacheIsKeptPerLocation() async {
        preferences.store.setCachedWeather(await makeCurrentWeather(temperature: 5), for: austin.cacheKey)
        api.onCurrent = { _ in throw self.offline }

        viewModel.refreshCurrent(location: denver)
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(viewModel.currentWeather, .error(errorKey: "offline", canRetry: true))
    }

    // MARK: - Silent background refresh

    func testBackgroundRefreshCurrentUpdatesStateOnSuccessWithoutShowingLoading() async {
        viewModel.backgroundRefreshCurrent(location: austin)
        XCTAssertEqual(viewModel.currentWeather, .idle)
        await waitUntil { self.viewModel.currentWeather.successValue != nil }

        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertNotNil(preferences.store.cachedWeather(for: austin.cacheKey))
    }

    func testBackgroundRefreshCurrentSilentlyIgnoresNetworkFailures() async {
        api.onCurrent = { _ in throw self.offline }

        viewModel.backgroundRefreshCurrent(location: austin)
        await waitUntil { self.api.completedCurrentRequests == 1 }
        await settle()

        XCTAssertEqual(viewModel.currentWeather, .idle)
    }

    func testBackgroundRefreshForecastUpdatesStateOnSuccessWithoutShowingLoading() async {
        viewModel.backgroundRefreshForecast(location: austin)
        XCTAssertEqual(viewModel.forecast, .idle)
        await waitUntil { self.viewModel.forecast.successValue != nil }

        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertNotNil(preferences.store.cachedForecast(for: austin.cacheKey))
    }

    func testBackgroundRefreshForecastSilentlyIgnoresNetworkFailures() async {
        api.onForecast = { _ in throw self.offline }

        viewModel.backgroundRefreshForecast(location: austin)
        await waitUntil { self.api.completedForecastRequests == 1 }
        await settle()

        XCTAssertEqual(viewModel.forecast, .idle)
    }

    /// Reproduces Android's indefinite-spinner bug: a foreground refresh and a silent background
    /// refresh fire for the same location, and the background one fails.
    func testConcurrentSameLocationBackgroundRefreshDoesNotBlockForegroundResult() async {
        let foreground = Gate<CurrentWeatherResponse>()
        let background = Gate<CurrentWeatherResponse>()
        var call = 0
        api.onCurrent = { _ in
            call += 1
            return try await (call == 1 ? foreground : background).value()
        }

        viewModel.refreshCurrent(location: austin)
        await waitUntil { self.api.currentRequests.count == 1 }
        viewModel.backgroundRefreshCurrent(location: austin)
        await waitUntil { self.api.currentRequests.count == 2 }

        background.fail(offline)
        await waitUntil { self.api.completedCurrentRequests == 1 }
        await settle()
        foreground.succeed(weatherResponse(name: "Austin"))
        await waitUntil { !self.viewModel.isRefreshing }

        XCTAssertEqual(viewModel.currentWeather.successValue?.cityName, "Austin")
    }

    func testStaleBackgroundCurrentRefreshDoesNotOverwriteNewerForegroundResult() async {
        let austinGate = Gate<CurrentWeatherResponse>()
        api.onCurrent = { request in
            request.cityQuery == "Austin" ? try await austinGate.value() : weatherResponse(name: "Denver")
        }

        viewModel.refreshCurrent(location: austin)
        await waitUntil { self.api.currentRequests.count == 1 }
        viewModel.backgroundRefreshCurrent(location: austin)
        await waitUntil { self.api.currentRequests.count == 2 }
        viewModel.refreshCurrent(location: denver)
        await waitUntil { self.viewModel.currentWeather.successValue?.cityName == "Denver" }

        austinGate.succeed(weatherResponse(name: "Austin"))
        await waitUntil { self.api.completedCurrentRequests == 3 }
        await settle()

        XCTAssertEqual(viewModel.currentWeather.successValue?.cityName, "Denver")
    }

    func testStaleBackgroundForecastRefreshDoesNotOverwriteNewerForegroundResult() async {
        let austinGate = Gate<ForecastResponse>()
        api.onForecast = { request in
            request.cityQuery == "Austin" ? try await austinGate.value() : forecastResponse(temperature: 30)
        }
        let denverForecast = await makeForecast(temperature: 30)

        viewModel.refreshForecast(location: austin)
        await waitUntil { self.api.forecastRequests.count == 1 }
        viewModel.backgroundRefreshForecast(location: austin)
        await waitUntil { self.api.forecastRequests.count == 2 }
        viewModel.refreshForecast(location: denver)
        await waitUntil { self.viewModel.forecast == .success(denverForecast) }

        austinGate.succeed(forecastResponse(temperature: -5))
        await waitUntil { self.api.completedForecastRequests == 3 }
        await settle()

        XCTAssertEqual(viewModel.forecast, .success(denverForecast))
    }
}
