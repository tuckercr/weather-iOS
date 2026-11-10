import XCTest
@testable import Cats_Dogs

@MainActor
final class WeatherBackgroundRefresherTests: XCTestCase {
    private let london = SavedLocation(label: "London, GB", latitude: 51.5074, longitude: -0.1278)
    private let nameOnly = SavedLocation(label: "Paris", latitude: nil, longitude: nil)
    private let refreshInterval: TimeInterval = 45 * 60

    private var suite: ThrowawayDefaults!
    private var preferences: PreferencesStore!

    override func setUp() async throws {
        suite = ThrowawayDefaults()
        preferences = PreferencesStore(defaults: suite.defaults)
    }

    override func tearDown() async throws {
        suite.destroy()
    }

    func testFollowMyLocationMovesItBeforeTheRefreshFetches() async {
        let myLocation = SavedLocation(label: "My Location", latitude: 40.0, longitude: -83.0, isCurrentLocation: true)
        preferences.setSavedLocations([myLocation])
        let refresher = makeRefresher(onFollow: { [preferences] in
            preferences?.moveMyLocation(latitude: 51.5074, longitude: -0.1278)
        })

        await refresher.performRefresh()

        XCTAssertEqual(preferences.savedLocations.first?.latitude, 51.5074)
        XCTAssertNotNil(preferences.cachedWeather(for: "51.5074,-0.1278"), "The new place's weather is fetched")
    }

    func testRefreshCachesFreshDataAndReschedulesNotifications() async {
        preferences.setSavedLocations([london])
        let api = FakeOpenWeatherAPI()
        var scheduled = 0
        let refresher = makeRefresher(api: api, onSchedule: { scheduled += 1 })

        let result = await refresher.performRefresh()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(preferences.cachedWeather(for: london.cacheKey)?.temperature, 72.5)
        XCTAssertEqual(preferences.cachedForecast(for: london.cacheKey)?.count, 1)
        XCTAssertEqual(api.lastCurrentLatitude, 51.5074)
        XCTAssertNil(api.lastCurrentCityQuery)
        XCTAssertEqual(scheduled, 1)
    }

    func testCitiesFetchedInTheLastHalfHourAreLeftAsTheyAreButNotificationsAreStillReplanned() async {
        preferences.setSavedLocations([london, nameOnly])
        preferences.setActiveLocationIndex(1)
        for location in [london, nameOnly] {
            preferences.setCachedWeather(sampleWeather(), for: location.cacheKey, fetchedAt: Date(timeIntervalSinceNow: -10 * 60))
            preferences.setCachedForecast([], for: location.cacheKey, fetchedAt: Date(timeIntervalSinceNow: -10 * 60))
        }
        let api = FakeOpenWeatherAPI()
        var scheduled = 0

        let result = await makeRefresher(api: api, onSchedule: { scheduled += 1 }).performRefresh()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(api.currentWeatherCallCount, 0)
        XCTAssertEqual(preferences.cachedWeather(for: london.cacheKey)?.temperature, 15.4, "the cache as it was")
        XCTAssertEqual(scheduled, 1)
    }

    func testACityWhoseForecastIsOlderThanHalfAnHourIsFetched() async {
        preferences.setSavedLocations([london])
        preferences.setCachedWeather(sampleWeather(), for: london.cacheKey, fetchedAt: Date(timeIntervalSinceNow: -10 * 60))
        preferences.setCachedForecast([], for: london.cacheKey, fetchedAt: Date(timeIntervalSinceNow: -40 * 60))
        let api = FakeOpenWeatherAPI()

        await makeRefresher(api: api).performRefresh()

        XCTAssertEqual(api.currentWeatherCallCount, 1)
        XCTAssertEqual(preferences.cachedWeather(for: london.cacheKey)?.temperature, 72.5)
    }

    func testRefreshStillCachesWhenNotificationsAreNotAuthorized() async {
        preferences.setSavedLocations([london])
        var scheduled = 0
        let refresher = makeRefresher(authorized: false, onSchedule: { scheduled += 1 })

        let result = await refresher.performRefresh()

        XCTAssertEqual(result, .success)
        XCTAssertNotNil(preferences.cachedWeather(for: london.cacheKey))
        XCTAssertEqual(scheduled, 0)
    }

    func testRefreshAlsoUpdatesTheTabLastViewedWhenItsAnotherCity() async {
        // London is the tab on screen, but with no My Location saved notifications follow the first city.
        preferences.setSavedLocations([nameOnly, london])
        preferences.setActiveLocationIndex(1)
        let api = FakeOpenWeatherAPI()
        var scheduled = 0
        let refresher = makeRefresher(api: api, onSchedule: { scheduled += 1 })

        await refresher.performRefresh()

        XCTAssertEqual(api.currentWeatherCallCount, 2)
        XCTAssertNotNil(preferences.cachedWeather(for: nameOnly.cacheKey))
        XCTAssertNotNil(preferences.cachedWeather(for: london.cacheKey))
        XCTAssertNotNil(preferences.cachedForecast(for: london.cacheKey))
        XCTAssertEqual(scheduled, 1, "replanned once, for the notification city")
    }

    func testTheNotificationCityIsFetchedOnceWhenItsAlsoTheTabLastViewed() async {
        preferences.setSavedLocations([london, nameOnly])
        preferences.setActiveLocationIndex(0)
        let api = FakeOpenWeatherAPI()

        await makeRefresher(api: api).performRefresh()

        XCTAssertEqual(api.currentWeatherCallCount, 1)
        XCTAssertNil(preferences.cachedWeather(for: nameOnly.cacheKey))
    }

    func testAFailedNotificationCityStillRetriesWhenAnotherTabWasViewed() async {
        preferences.setSavedLocations([london, nameOnly])
        preferences.setActiveLocationIndex(1)

        let result = await makeRefresher(api: FakeOpenWeatherAPI(currentError: URLError(.notConnectedToInternet))).performRefresh()

        XCTAssertEqual(result, .retry)
    }

    func testFailedFetchKeepsExistingCacheAndRetriesSooner() async {
        preferences.setSavedLocations([london])
        _ = await makeRefresher().performRefresh()
        // An hour old, so it's fetched again.
        preferences.setCachedWeather(preferences.cachedWeather(for: london.cacheKey)!, for: london.cacheKey, fetchedAt: Date(timeIntervalSinceNow: -3600))
        var scheduled = 0
        var requestedDelays: [TimeInterval] = []
        let refresher = makeRefresher(
            api: FakeOpenWeatherAPI(currentError: URLError(.notConnectedToInternet)),
            onSchedule: { scheduled += 1 },
            onSubmit: { requestedDelays.append($0.timeIntervalSinceNow) }
        )

        await refresher.handleAppRefresh()

        XCTAssertNotNil(preferences.cachedWeather(for: london.cacheKey))
        XCTAssertEqual(scheduled, 0)
        XCTAssertEqual(requestedDelays.count, 2)
        XCTAssertEqual(requestedDelays[0], refreshInterval, accuracy: 5)
        XCTAssertEqual(requestedDelays[1], WeatherBackgroundRefresher.retryInterval, accuracy: 5)
    }

    func testSuccessfulRefreshQueuesExactlyOneFollowUp() async {
        preferences.setSavedLocations([london])
        var requestedDelays: [TimeInterval] = []
        let refresher = makeRefresher(onSubmit: { requestedDelays.append($0.timeIntervalSinceNow) })

        await refresher.handleAppRefresh()

        XCTAssertEqual(requestedDelays.count, 1)
        XCTAssertEqual(requestedDelays[0], refreshInterval, accuracy: 5)
    }

    func testWhenTheNotificationCityChangesItReplansEvenIfTheFetchFailsOrNoCityIsLeft() async {
        preferences.setSavedLocations([london])
        var scheduled = 0
        let offline = makeRefresher(
            api: FakeOpenWeatherAPI(currentError: URLError(.notConnectedToInternet)),
            onSchedule: { scheduled += 1 }
        )
        await offline.performRefresh(replan: true)
        XCTAssertEqual(scheduled, 1)

        preferences.setSavedLocations([])
        await makeRefresher(onSchedule: { scheduled += 1 }).performRefresh(replan: true)
        XCTAssertEqual(scheduled, 2)

        preferences.setSavedLocations([london])
        await makeRefresher(onSchedule: { scheduled += 1 }).performRefresh(replan: true)
        XCTAssertEqual(scheduled, 3, "replanned once, not twice, after a good refresh")
    }

    func testNoSavedLocationsDoesNoNetworkWork() async {
        let api = FakeOpenWeatherAPI()
        let refresher = makeRefresher(api: api)

        let result = await refresher.performRefresh()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(api.currentWeatherCallCount, 0)
    }

    private func makeRefresher(
        api: FakeOpenWeatherAPI? = nil,
        authorized: Bool = true,
        onSchedule: @escaping () -> Void = {},
        onSubmit: @escaping (Date) -> Void = { _ in },
        onFollow: @escaping () -> Void = {}
    ) -> WeatherBackgroundRefresher {
        WeatherBackgroundRefresher(
            refreshInterval: { [refreshInterval] in refreshInterval },
            preferences: preferences,
            repository: LocationWeatherRepository(
                weatherRepository: WeatherRepository(
                    client: api ?? FakeOpenWeatherAPI(),
                    openMeteo: StubOpenMeteoAPI(response: openMeteoResponse(hours: 1)),
                    airQuality: StubAirQualityAPI(),
                    timeZone: TimeZone(identifier: "UTC")!,
                    now: { Date(timeIntervalSince1970: TimeInterval(fixtureDayStart)) }
                ),
                preferences: preferences
            ),
            notificationsAuthorized: { authorized },
            scheduleNotifications: { onSchedule() },
            submitRefreshRequest: onSubmit,
            followMyLocation: onFollow
        )
    }
}

private final class FakeOpenWeatherAPI: OpenWeatherAPI, @unchecked Sendable {
    var currentWeatherCallCount = 0
    var lastCurrentCityQuery: String?
    var lastCurrentLatitude: Double?

    private let currentError: Error?

    init(currentError: Error? = nil) {
        self.currentError = currentError
    }

    func currentWeather(
        cityQuery: String?,
        latitude: Double?,
        longitude: Double?,
        units: WeatherUnits
    ) async throws -> CurrentWeatherResponse {
        currentWeatherCallCount += 1
        lastCurrentCityQuery = cityQuery
        lastCurrentLatitude = latitude
        if let currentError { throw currentError }
        return CurrentWeatherResponse(
            name: "OpenWeather City",
            weather: [WeatherDescDTO(main: "Clear", description: "clear sky", icon: "01d")],
            main: MainDTO(temp: 72.5, feelsLike: 70.0, humidity: 42),
            wind: WindDTO(speed: 5.5),
            visibility: 10_000,
            clouds: CloudsDTO(all: 25),
            sys: nil
        )
    }

    func forecast(
        cityQuery: String?,
        latitude: Double?,
        longitude: Double?,
        units: WeatherUnits
    ) async throws -> ForecastResponse {
        ForecastResponse(list: [
            ForecastListItemDTO(
                dt: 1_700_049_600,
                main: MainDTO(temp: 70.0, feelsLike: 69.0, humidity: 50),
                weather: [WeatherDescDTO(main: "Clear", description: "clear sky", icon: "01d")],
                wind: WindDTO(speed: 1.0)
            ),
        ])
    }
}
