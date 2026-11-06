import XCTest
@testable import Cats_Dogs

@MainActor
final class PreferencesStoreTests: XCTestCase {
    private let austin = SavedLocation(label: "Austin", latitude: 30.27, longitude: -97.74)
    private let denver = SavedLocation(label: "Denver", latitude: 39.74, longitude: -104.99)

    private var preferences: IsolatedPreferences!

    override func setUp() async throws {
        preferences = IsolatedPreferences()
    }

    override func tearDown() async throws {
        preferences.destroy()
    }

    func testMyLocationsFallbackNameNeverBecomesTheLastCity() {
        preferences.store.setLastCity("Paris")
        preferences.store.setLastCity("My Location")

        XCTAssertEqual(preferences.reopened().lastCity, "Paris")
    }

    func testCachedWeatherAndForecastRoundTripPerLocation() async {
        let weather = await makeCurrentWeather(cityName: "Austin", temperature: 31)
        let forecast = await makeForecast(temperature: 28)
        preferences.store.setCachedWeather(weather, for: austin.cacheKey)
        preferences.store.setCachedForecast(forecast, for: austin.cacheKey)

        let reopened = preferences.reopened()

        XCTAssertEqual(reopened.cachedWeather(for: austin.cacheKey), weather)
        XCTAssertEqual(reopened.cachedForecast(for: austin.cacheKey), forecast)
        XCTAssertNil(reopened.cachedWeather(for: denver.cacheKey))
    }

    func testTheForecastsFetchTimeIsKeptWithItAndGoesWithIt() async {
        let fetched = Date(timeIntervalSince1970: 1_793_550_600)
        preferences.store.setSavedLocations([austin, denver])
        XCTAssertNil(preferences.store.cachedForecastFetchedAt(for: austin.cacheKey))

        preferences.store.setCachedForecast(await makeForecast(), for: austin.cacheKey, fetchedAt: fetched)
        preferences.store.setCachedForecast(await makeForecast(), for: denver.cacheKey, fetchedAt: fetched)
        XCTAssertEqual(preferences.reopened().cachedForecastFetchedAt(for: austin.cacheKey), fetched)

        // Removing a city drops its time with its forecast; clearing the cache drops them all.
        preferences.store.setSavedLocations([denver])
        XCTAssertNil(preferences.store.cachedForecastFetchedAt(for: austin.cacheKey))
        preferences.store.clearCache()
        XCTAssertNil(preferences.store.cachedForecastFetchedAt(for: denver.cacheKey))
    }

    func testWalkNudgeDatesRoundTrip() {
        let dates = [Date(timeIntervalSince1970: 1_793_550_600), Date(timeIntervalSince1970: 1_793_637_000)]
        XCTAssertEqual(preferences.store.walkNudgeDates, [])

        preferences.store.setWalkNudgeDates(dates)

        XCTAssertEqual(preferences.reopened().walkNudgeDates, dates)
    }

    func testRemovingACityEvictsItsCacheButKeepsTheOthers() async {
        preferences.store.setSavedLocations([austin, denver])
        preferences.store.setCachedWeather(await makeCurrentWeather(cityName: "Austin"), for: austin.cacheKey)
        preferences.store.setCachedWeather(await makeCurrentWeather(cityName: "Denver"), for: denver.cacheKey)
        preferences.store.setCachedForecast(await makeForecast(), for: denver.cacheKey)

        preferences.store.setSavedLocations([austin])

        XCTAssertNotNil(preferences.store.cachedWeather(for: austin.cacheKey))
        XCTAssertNil(preferences.store.cachedWeather(for: denver.cacheKey))
        XCTAssertNil(preferences.store.cachedForecast(for: denver.cacheKey))
    }

    func testReorderingCitiesKeepsEveryCacheEntry() async {
        preferences.store.setSavedLocations([austin, denver])
        preferences.store.setCachedWeather(await makeCurrentWeather(cityName: "Austin"), for: austin.cacheKey)
        preferences.store.setCachedWeather(await makeCurrentWeather(cityName: "Denver"), for: denver.cacheKey)

        preferences.store.setSavedLocations([denver, austin])

        XCTAssertNotNil(preferences.store.cachedWeather(for: austin.cacheKey))
        XCTAssertNotNil(preferences.store.cachedWeather(for: denver.cacheKey))
    }

    /// Builds before the Rain outlook cached hourly slots without the hour's rain amount.
    func testAForecastCachedWithoutRainAmountsStillLoads() throws {
        let day = """
        {"dateLabel":"Mon, Jan 1","conditionMain":"Rain","description":"Light rain","iconCode":"10d",
        "temperature":15,"feelsLike":14,"tempMin":10,"tempMax":16,"units":"metric","precipitationChance":60,
        "hourlySlots":[{"timeLabel":"3 PM","iconCode":"10d","description":"Light rain","temperature":15,
        "feelsLike":14,"windSpeed":3,"windDeg":180,"humidity":80,"pressure":1012,"units":"metric",
        "precipitationChance":60,"localHour":15,"epochSeconds":1704121200,"groundWet":true}]}
        """
        let suite = ThrowawayDefaults()
        defer { suite.destroy() }
        let cache = [austin.cacheKey: [try JSONSerialization.jsonObject(with: Data(day.utf8))]]
        suite.defaults.set(try JSONSerialization.data(withJSONObject: cache), forKey: "forecast_cache")

        let slot = try XCTUnwrap(PreferencesStore(defaults: suite.defaults).cachedForecast(for: austin.cacheKey)?.first?.hourlySlots.first)

        XCTAssertEqual(slot.precipitationChance, 60)
        XCTAssertNil(slot.precipitationMm)
    }

    /// Builds before this change stored each entry as a JSON string inside the map.
    func testCacheWrittenInTheOlderFormatIsIgnoredAndThenReplaced() async throws {
        let suite = ThrowawayDefaults()
        let defaults = suite.defaults
        defer { suite.destroy() }
        defaults.set(try JSONEncoder().encode([austin.cacheKey: "{\"cityName\":\"Austin\"}"]), forKey: "weather_cache")
        let store = PreferencesStore(defaults: defaults)

        XCTAssertNil(store.cachedWeather(for: austin.cacheKey))

        let weather = await makeCurrentWeather(cityName: "Austin")
        store.setCachedWeather(weather, for: austin.cacheKey)

        XCTAssertEqual(store.cachedWeather(for: austin.cacheKey), weather)
    }
}
