import XCTest
@testable import Cats_Dogs

final class RemoteConfigRepositoryTests: XCTestCase {
    func testRefreshIntervalDefaultsToThirtyMinutes() {
        XCTAssertEqual(RemoteConfigRepository.refreshInterval(minutes: nil), 30 * 60)
    }

    func testRefreshIntervalUsesTheRemoteValue() {
        XCTAssertEqual(RemoteConfigRepository.refreshInterval(minutes: 60), 60 * 60)
    }

    func testRefreshIntervalNeverGoesBelowFifteenMinutes() {
        XCTAssertEqual(RemoteConfigRepository.refreshInterval(minutes: 5), 15 * 60)
        XCTAssertEqual(RemoteConfigRepository.refreshInterval(minutes: 0), 15 * 60)
    }

    func testRadarFrameIntervalDefaultsTo850Milliseconds() {
        XCTAssertEqual(RemoteConfigRepository.radarFrameInterval(milliseconds: nil), .milliseconds(850))
    }

    func testRadarFrameIntervalUsesAnInRangeRemoteValue() {
        XCTAssertEqual(RemoteConfigRepository.radarFrameInterval(milliseconds: 100), .milliseconds(100))
        XCTAssertEqual(RemoteConfigRepository.radarFrameInterval(milliseconds: 5000), .milliseconds(5000))
    }

    func testOutOfRangeRadarFrameIntervalFallsBackToTheDefault() {
        XCTAssertEqual(RemoteConfigRepository.radarFrameInterval(milliseconds: 99), .milliseconds(850))
        XCTAssertEqual(RemoteConfigRepository.radarFrameInterval(milliseconds: 5001), .milliseconds(850))
        XCTAssertEqual(RemoteConfigRepository.radarFrameInterval(milliseconds: 0), .milliseconds(850))
    }

    func testARemoteOpenWeatherKeyReplacesTheBuiltInOne() {
        XCTAssertEqual(AppConfig.resolveOpenWeatherApiKey(remoteKey: " remote ", bundledKey: "bundled"), "remote")
    }

    func testTheBuiltInOpenWeatherKeyIsUsedWhenNoRemoteKeyIsSet() {
        XCTAssertEqual(AppConfig.resolveOpenWeatherApiKey(remoteKey: nil, bundledKey: "bundled"), "bundled")
        XCTAssertEqual(AppConfig.resolveOpenWeatherApiKey(remoteKey: "  ", bundledKey: "bundled"), "bundled")
    }

    func testForegroundRefreshWindowDefaultsToOff() {
        XCTAssertEqual(RemoteConfigRepository.foregroundRefreshMinInterval(minutes: nil), 0)
    }

    func testForegroundRefreshWindowUsesAnInRangeValue() {
        XCTAssertEqual(RemoteConfigRepository.foregroundRefreshMinInterval(minutes: 10), 10 * 60)
        XCTAssertEqual(RemoteConfigRepository.foregroundRefreshMinInterval(minutes: 1440), 1440 * 60)
    }

    func testOutOfRangeForegroundRefreshWindowFallsBackToOff() {
        XCTAssertEqual(RemoteConfigRepository.foregroundRefreshMinInterval(minutes: -5), 0)
        XCTAssertEqual(RemoteConfigRepository.foregroundRefreshMinInterval(minutes: 1441), 0)
    }

    private func citySearchPolicy(
        provider: String? = nil,
        openMeteoEnabled: Bool = true,
        results: Double? = nil,
        sizeRatio: Double? = nil,
        delay: Double? = nil
    ) -> CitySearchPolicy {
        RemoteConfigRepository.citySearchPolicy(
            provider: provider, openMeteoEnabled: openMeteoEnabled, results: results,
            countryFirst: true, nearestFirst: true, sizeRatio: sizeRatio, delayMilliseconds: delay
        )
    }

    func testCitySearchDefaultsAreSearchMdsDefaults() {
        XCTAssertEqual(citySearchPolicy(), CitySearchPolicy(
            provider: .openMeteo, results: 8, countryFirst: true, nearestFirst: true, sizeRatio: 20, delayMilliseconds: 280
        ))
    }

    func testCitySearchProviderIsOpenMeteoOrOpenWeatherAndTheLicenceSwitchWins() {
        XCTAssertEqual(citySearchPolicy(provider: "openweather").provider, .openWeather)
        XCTAssertEqual(citySearchPolicy(provider: "open_meteo").provider, .openMeteo)
        XCTAssertEqual(citySearchPolicy(provider: "google").provider, .openMeteo)
        XCTAssertEqual(citySearchPolicy(provider: "open_meteo", openMeteoEnabled: false).provider, .openWeather)
    }

    func testCitySearchNumbersAreWholeAndInRangeOrTheirDefault() {
        XCTAssertEqual([3.0, 10, 2, 11, 7.5].map { citySearchPolicy(results: $0).results }, [3, 10, 8, 8, 8])
        XCTAssertEqual([2.0, 1000, 0, 1, 1001, 20.5].map { citySearchPolicy(sizeRatio: $0).sizeRatio }, [2, 1000, 0, 20, 20, 20])
        XCTAssertEqual([100.0, 1000, 99, 1001].map { citySearchPolicy(delay: $0).delayMilliseconds }, [100, 1000, 280, 280])
    }

    func testRainOutlookHoursDefaultsToTen() {
        XCTAssertEqual(RemoteConfigRepository.rainOutlookHours(nil), 10)
    }

    func testRainOutlookHoursUsesAWholeNumberFromSixToTwelve() {
        XCTAssertEqual(RemoteConfigRepository.rainOutlookHours(6), 6)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookHours(8), 8)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookHours(12), 12)
    }

    func testOutOfRangeOrFractionalRainOutlookHoursFallBackToTen() {
        XCTAssertEqual(RemoteConfigRepository.rainOutlookHours(5), 10)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookHours(13), 10)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookHours(0), 10)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookHours(-8), 10)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookHours(7.5), 10)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookHours(.nan), 10)
    }

    func testRainOutlookMinChanceDefaultsToTwenty() {
        XCTAssertEqual(RemoteConfigRepository.rainOutlookMinChance(nil), 20)
    }

    func testRainOutlookMinChanceUsesAWholeNumberFromOneToAHundred() {
        XCTAssertEqual(RemoteConfigRepository.rainOutlookMinChance(1), 1)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookMinChance(35), 35)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookMinChance(100), 100)
    }

    func testOutOfRangeOrFractionalRainOutlookMinChanceFallsBackToTwenty() {
        XCTAssertEqual(RemoteConfigRepository.rainOutlookMinChance(0), 20)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookMinChance(101), 20)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookMinChance(-5), 20)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookMinChance(30.5), 20)
        XCTAssertEqual(RemoteConfigRepository.rainOutlookMinChance(.infinity), 20)
    }

    func testTemperaturesLeaveOutTheUnitByDefault() {
        XCTAssertEqual(RemoteConfigRepository.keyTemperatureUnitsShown, "temperature_units_shown")
        XCTAssertFalse(RemoteConfigRepository.defaultTemperatureUnitsShown)
    }

    @MainActor
    func testWithoutFirebaseTheDefaultsApply() {
        XCTAssertFalse(FirebaseSetup.isConfigured)
        XCTAssertEqual(RemoteConfigRepository.shared.refreshInterval, 30 * 60)
        XCTAssertEqual(RemoteConfigRepository.shared.radarFrameInterval, .milliseconds(850))
        XCTAssertTrue(RemoteConfigRepository.shared.analyticsEnabled)
        XCTAssertTrue(RemoteConfigRepository.shared.radarEnabled)
        XCTAssertTrue(RemoteConfigRepository.shared.walkCardEnabled)
        XCTAssertTrue(RemoteConfigRepository.shared.hourlyForecastEnabled)
        XCTAssertTrue(RemoteConfigRepository.shared.nextRainEnabled)
        XCTAssertTrue(RemoteConfigRepository.shared.weekForecastEnabled)
        XCTAssertTrue(RemoteConfigRepository.shared.rainOutlookEnabled)
        XCTAssertEqual(RemoteConfigRepository.shared.rainOutlookHours, 10)
        XCTAssertEqual(RemoteConfigRepository.shared.rainOutlookMinChance, 20)
        XCTAssertTrue(RemoteConfigRepository.openMeteoEnabled)
        XCTAssertFalse(RemoteConfigRepository.temperatureUnitsShown)
        XCTAssertNil(RemoteConfigRepository.openWeatherApiKey)
        XCTAssertTrue(RemoteConfigRepository.shared.dailyWeatherNotificationsEnabled)
        XCTAssertTrue(RemoteConfigRepository.shared.walkTimeNotificationsEnabled)
        // Off for the first release.
        XCTAssertFalse(RemoteConfigRepository.shared.rainNotificationsEnabled)
        XCTAssertEqual(RemoteConfigRepository.shared.todayTiles, TodayTileSwitches())
        XCTAssertEqual(RemoteConfigRepository.shared.foregroundRefreshMinInterval, 0)
        XCTAssertEqual(RemoteConfigRepository.shared.petWeatherThresholds, .standard)
    }
}
