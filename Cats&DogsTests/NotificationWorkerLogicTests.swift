import XCTest
@testable import Cats_Dogs

@MainActor
final class NotificationWorkerLogicTests: XCTestCase {
    private let london = SavedLocation(label: "London, GB", latitude: 51.5074, longitude: -0.1278)

    func testReturnsSuccessWhenNoLocationsSaved() async {
        var refreshed = 0
        let logic = makeLogic(savedLocations: [], onRefreshed: { refreshed += 1 })

        let result = await logic.doWork()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(refreshed, 0)
    }

    func testTheBellInManageLocationsMarksTheNotificationCity() {
        let here = SavedLocation(label: "My Location", latitude: 40, longitude: -83, isCurrentLocation: true)
        let paris = SavedLocation(label: "Paris, FR", latitude: 48.9, longitude: 2.4)
        XCTAssertEqual([paris, london, here].notificationIndex, 2)
        XCTAssertEqual([london, paris].notificationIndex, 0)
        XCTAssertNil([SavedLocation]().notificationIndex)
    }

    func testRefreshesMyLocationFirstOtherwiseTheFirstCity() async {
        let here = SavedLocation(label: "My Location", latitude: 40, longitude: -83, isCurrentLocation: true)
        let paris = SavedLocation(label: "Paris, FR", latitude: 48.9, longitude: 2.4)
        var latitudes: [Double?] = []
        for locations in [[london, here], [paris, london]] {
            _ = await makeLogic(
                savedLocations: locations,
                refreshWeather: { location in
                    latitudes.append(location.latitude)
                    return .failure(OpenWeatherClientError.network)
                }
            ).doWork()
        }
        XCTAssertEqual(latitudes, [40, 48.9])
    }

    func testReturnsRetryWhenWeatherFetchFails() async {
        var refreshed = 0
        let logic = makeLogic(
            refreshWeather: { _ in .failure(OpenWeatherClientError.network) },
            onRefreshed: { refreshed += 1 }
        )

        let result = await logic.doWork()

        XCTAssertEqual(result, .retry)
        XCTAssertEqual(refreshed, 0)
    }

    func testFetchesTheForecastAndReplansWhenWeatherFetchSucceeds() async {
        var refreshed = 0
        var forecastFetched = false
        let logic = makeLogic(
            refreshForecast: { _ in
                forecastFetched = true
                return .success([])
            },
            onRefreshed: { refreshed += 1 }
        )

        let result = await logic.doWork()

        XCTAssertEqual(result, .success)
        XCTAssertTrue(forecastFetched)
        XCTAssertEqual(refreshed, 1)
    }

    func testFreshDataIsntFetchedAgainButTheNotificationsAreStillPlannedFromIt() async {
        var fetches = 0
        var refreshed = 0
        let logic = makeLogic(
            refreshWeather: { _ in fetches += 1; return .success(sampleWeather()) },
            refreshForecast: { _ in fetches += 1; return .success([]) },
            hasFreshData: true,
            onRefreshed: { refreshed += 1 }
        )

        let result = await logic.doWork()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(fetches, 0)
        XCTAssertEqual(refreshed, 1)
    }

    func testDoesNotReplanWhenPermissionDenied() async {
        var refreshed = 0
        let logic = makeLogic(hasNotificationPermission: { false }, onRefreshed: { refreshed += 1 })

        let result = await logic.doWork()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(refreshed, 0)
    }

    private func makeLogic(
        savedLocations: [SavedLocation]? = nil,
        refreshWeather: ((SavedLocation) async -> Result<CurrentWeather, Error>)? = nil,
        refreshForecast: ((SavedLocation) async -> Result<[DayForecast], Error>)? = nil,
        hasFreshData: Bool = false,
        hasNotificationPermission: @escaping () -> Bool = { true },
        onRefreshed: @escaping () -> Void = {}
    ) -> NotificationWorkerLogic {
        NotificationWorkerLogic(
            getSavedLocations: { savedLocations ?? [self.london] },
            refreshWeather: refreshWeather ?? { _ in .success(sampleWeather()) },
            refreshForecast: refreshForecast ?? { _ in .success([]) },
            hasFreshData: { _ in hasFreshData },
            hasNotificationPermission: hasNotificationPermission,
            onRefreshed: onRefreshed
        )
    }
}

/// A clear 15 °C afternoon in London, for the notification tests.
func sampleWeather(cityName: String = "London", timeZoneOffset: Int = 0) -> CurrentWeather {
    CurrentWeather(
        cityName: cityName,
        conditionMain: "Clear",
        description: "clear sky",
        iconCode: "01d",
        temperature: 15.4,
        feelsLike: 14.0,
        tempMin: 10,
        tempMax: 18,
        humidityPercent: 50,
        pressureHpa: 1013,
        windSpeed: 3.0,
        windDeg: 180,
        visibilityMeters: 10_000,
        cloudPercent: 10,
        units: .metric,
        sunriseEpoch: nil,
        sunsetEpoch: nil,
        timezoneOffsetSeconds: timeZoneOffset
    )
}
