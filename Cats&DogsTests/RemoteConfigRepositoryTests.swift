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
        XCTAssertTrue(RemoteConfigRepository.openMeteoEnabled)
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
