import XCTest
@testable import Cats_Dogs

/// Air quality on the city's scale only, reused for 3 hours: the same rules as on Android.
@MainActor
final class FewerOpenMeteoCallsTests: XCTestCase {
    private let london = SavedLocation(label: "London, GB", latitude: 51.5074, longitude: -0.1278)
    private let start = Date(timeIntervalSince1970: TimeInterval(fixtureDayStart))

    private var suite: ThrowawayDefaults!
    private var preferences: PreferencesStore!

    override func setUp() async throws {
        suite = ThrowawayDefaults()
        preferences = PreferencesStore(defaults: suite.defaults)
    }

    override func tearDown() async throws {
        suite.destroy()
    }

    // MARK: - B. One scale per request

    func testEachScaleAsksForItsOwnIndicesAndTheParticleMassesInTenFieldsOrFewer() {
        let us = AirQualityReadings.fields(for: .us).map(\.rawValue)
        let european = AirQualityReadings.fields(for: .european).map(\.rawValue)

        XCTAssertEqual(us, [
            "us_aqi", "us_aqi_pm2_5", "us_aqi_pm10", "us_aqi_ozone", "us_aqi_nitrogen_dioxide",
            "us_aqi_sulphur_dioxide", "us_aqi_carbon_monoxide", "pm2_5", "pm10",
        ])
        XCTAssertEqual(european, [
            "european_aqi", "european_aqi_pm2_5", "european_aqi_pm10", "european_aqi_ozone",
            "european_aqi_nitrogen_dioxide", "european_aqi_sulphur_dioxide", "pm2_5", "pm10",
        ])
        XCTAssertLessThanOrEqual(us.count, 10)
        XCTAssertLessThanOrEqual(european.count, 10)
        XCTAssertEqual(AirQualityClient.hourlyFields(for: .european), european.joined(separator: ","))
    }

    func testAnUnknownTimeZoneAsksForBothScales() {
        XCTAssertEqual(AirQualityReadings.fields(for: nil).count, 15)
        XCTAssertEqual(Set(AirQualityReadings.fields(for: nil)), Set(AirQualityReadings.Field.allCases))
    }

    func testTheForecastsTimeZonePicksTheScaleToAskFor() async {
        let air = StubAirQualityAPI(hourlyIndices: [fixtureDayStart: 30], timezone: "Europe/London")
        let repository = weatherRepository(air: air, zone: "Europe/London")

        let result = await repository.fetchForecast(for: london, units: .metric, cachedAirQuality: nil)

        XCTAssertEqual(air.requestedScales, [.european])
        XCTAssertEqual(try? result.get().airQuality?.scale, .european)
        XCTAssertEqual(try? result.get().days.first?.hourlySlots.first?.airQuality?.scale, .european)
    }

    func testWithoutTheForecastsTimeZoneBothAreAskedForAndTheResponsePicks() async {
        let air = StubAirQualityAPI(hourlyIndices: [fixtureDayStart: 30], timezone: "Europe/Paris")
        let repository = weatherRepository(air: air, zone: nil)

        let result = await repository.fetchForecast(for: london, units: .metric, cachedAirQuality: nil)

        XCTAssertEqual(air.requestedScales, [nil])
        XCTAssertEqual(try? result.get().airQuality?.scale, .european)
    }

    func testOneScalesFieldsAreEnoughToParse() throws {
        let json = """
        {"timezone":"Europe/Berlin","hourly":{"time":[100],"european_aqi":[45],"european_aqi_pm2_5":[30],
        "european_aqi_ozone":[45],"pm2_5":[12.4],"pm10":[20.1]}}
        """
        let response = try JSONDecoder().decode(AirQualityHourlyResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.byHour(on: .european), [100: AirQuality(index: 45, scale: .european, mainPollutant: .ozone)])
        XCTAssertEqual(response.byHour(on: .us), [:])
    }

    // MARK: - C. Reused for 3 hours

    func testAirQualityIsReusedWithinThreeHoursOnTheSameScaleWhenItCoversTheNextDay() {
        let hours = airHours(fetchedAt: start, scale: .us, hours: 48)

        XCTAssertTrue(hours.canBeReused(on: .us, now: start))
        XCTAssertTrue(hours.canBeReused(on: .us, now: start.addingTimeInterval(AirQualityHours.maxAge - 60)))
        XCTAssertFalse(hours.canBeReused(on: .us, now: start.addingTimeInterval(AirQualityHours.maxAge)), "3 hours old")
        XCTAssertFalse(hours.canBeReused(on: .european, now: start), "another scale")
        XCTAssertFalse(airHours(fetchedAt: start, scale: .us, hours: 23).canBeReused(on: .us, now: start), "under 24 hours")
        XCTAssertFalse(
            airHours(fetchedAt: start, scale: .us, hours: 48, from: fixtureDayStart + 3600).canBeReused(on: .us, now: start),
            "doesn't have the hour in progress"
        )
        XCTAssertFalse(airHours(fetchedAt: start, scale: .us, hours: 0).canBeReused(on: .us, now: start))
    }

    func testAForecastRefreshReusesRecentAirQualityAndFetchesItAgainOnceItsThreeHoursOld() async {
        let clock = TestClock(start)
        let air = StubAirQualityAPI(hourlyIndices: indices(hours: 48))
        let repository = LocationWeatherRepository(
            weatherRepository: weatherRepository(air: air, zone: "America/New_York", now: { clock.now }),
            preferences: preferences,
            now: { clock.now }
        )

        _ = await repository.refreshForecast(for: london)
        XCTAssertEqual(air.requestedScales, [.us])
        XCTAssertEqual(preferences.cachedAirQuality(for: london.cacheKey)?.fetchedAt, start)

        clock.now = start.addingTimeInterval(2 * 3600)
        let reused = await repository.refreshForecast(for: london)
        XCTAssertEqual(air.requestedScales.count, 1, "reused")
        XCTAssertNotNil(try? reused.get().first?.hourlySlots.first?.airQuality, "the reused hours are on the slots")

        clock.now = start.addingTimeInterval(3 * 3600)
        _ = await repository.refreshForecast(for: london)
        XCTAssertEqual(air.requestedScales.count, 2, "fetched again")
        XCTAssertEqual(preferences.cachedAirQuality(for: london.cacheKey)?.fetchedAt, clock.now)
    }

    func testAirQualityThatNoLongerCoversTheNextDayIsFetchedAgain() async {
        let air = StubAirQualityAPI(hourlyIndices: indices(hours: 20))
        let repository = LocationWeatherRepository(
            weatherRepository: weatherRepository(air: air, zone: "America/New_York"),
            preferences: preferences,
            now: { [start] in start }
        )

        _ = await repository.refreshForecast(for: london)
        _ = await repository.refreshForecast(for: london)

        XCTAssertEqual(air.requestedScales.count, 2)
    }

    func testAirQualityIsKeptWhenAFetchFails() async {
        let cached = airHours(fetchedAt: start.addingTimeInterval(-4 * 3600), scale: .us, hours: 48)
        preferences.setCachedAirQuality(cached, for: london.cacheKey)
        let repository = LocationWeatherRepository(
            weatherRepository: weatherRepository(air: StubAirQualityAPI(error: URLError(.timedOut)), zone: "America/New_York"),
            preferences: preferences,
            now: { [start] in start }
        )

        let result = await repository.refreshForecast(for: london)

        XCTAssertNotNil(try? result.get(), "the forecast still stands")
        XCTAssertEqual(preferences.cachedAirQuality(for: london.cacheKey), cached)
    }

    func testCachedAirQualitySurvivesAFreshStoreAndGoesWithTheCity() {
        let hours = airHours(fetchedAt: start, scale: .european, hours: 2)
        preferences.setSavedLocations([london])
        preferences.setCachedAirQuality(hours, for: london.cacheKey)

        XCTAssertEqual(PreferencesStore(defaults: suite.defaults).cachedAirQuality(for: london.cacheKey), hours)

        preferences.setSavedLocations([])
        XCTAssertNil(preferences.cachedAirQuality(for: london.cacheKey))
    }

    // MARK: - Helpers

    private func weatherRepository(
        air: StubAirQualityAPI,
        zone: String?,
        now: (@Sendable () -> Date)? = nil
    ) -> WeatherRepository {
        let start = start
        return WeatherRepository(
            client: NoOpenWeather(),
            openMeteo: StubOpenMeteoAPI(response: openMeteoResponse(hours: 6, zone: zone)),
            airQuality: air,
            timeZone: TimeZone(identifier: "UTC")!,
            now: now ?? { start }
        )
    }

    private func indices(hours: Int, from first: Int = fixtureDayStart) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: (0 ..< hours).map { (first + $0 * 3600, 40) })
    }

    private func airHours(fetchedAt: Date, scale: AirQuality.Scale, hours: Int, from first: Int = fixtureDayStart) -> AirQualityHours {
        AirQualityHours(
            fetchedAt: fetchedAt,
            scale: scale,
            byHour: indices(hours: hours, from: first).mapValues { AirQuality(index: $0, scale: scale, mainPollutant: nil) }
        )
    }
}

private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private struct NoOpenWeather: OpenWeatherAPI {
    func currentWeather(cityQuery: String?, latitude: Double?, longitude: Double?, units: WeatherUnits) async throws -> CurrentWeatherResponse {
        throw OpenWeatherClientError.network
    }

    func forecast(cityQuery: String?, latitude: Double?, longitude: Double?, units: WeatherUnits) async throws -> ForecastResponse {
        throw OpenWeatherClientError.network
    }
}
