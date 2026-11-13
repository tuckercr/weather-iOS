import XCTest
@testable import Cats_Dogs

/// The weather screen's steps, in `WeatherForecastViewModel`. Same cases as Android's `WeatherScreenStepsTest`.
@MainActor
final class WeatherScreenStepsTests: XCTestCase {
    private let austin = SavedLocation(label: "Austin, TX, US", latitude: 30.27, longitude: -97.74)
    private let myLocation = SavedLocation(label: SavedLocation.myLocationLabel, latitude: 40, longitude: -83, isCurrentLocation: true)
    /// About 110 km north of `myLocation`: far enough to move it.
    private let movedHere = SavedLocation(label: SavedLocation.myLocationLabel, latitude: 41, longitude: -83, isCurrentLocation: true)

    private var preferences: IsolatedPreferences!
    private var api: ScriptedWeatherAPI!
    private var position: FakePosition!
    private var notificationCityRefreshes = 0

    override func setUp() async throws {
        preferences = IsolatedPreferences()
        preferences.store.setUnitOverride(.metric)
        api = ScriptedWeatherAPI()
        position = FakePosition()
        notificationCityRefreshes = 0
    }

    override func tearDown() async throws {
        preferences.destroy()
    }

    // MARK: - Refreshing

    func testAppearingRefreshesTheCityOnScreen() async {
        preferences.store.setSavedLocations([austin])
        let viewModel = makeViewModel()

        viewModel.appeared()

        // A city with coordinates: the reading from the fake, the forecast from Open-Meteo.
        await waitUntil { self.api.currentRequests.count == 1 && viewModel.forecast.successValue != nil }
    }

    func testAnotherCityTheUnitsAndRetryAllRefetch() async {
        preferences.store.setSavedLocations([austin])
        let viewModel = makeViewModel()

        viewModel.activeCityChanged()
        viewModel.unitsChanged()
        viewModel.retry()

        await waitUntil { self.api.currentRequests.count == 3 }
    }

    func testTheHalfHourlyRefreshRunsUntilCancelled() async {
        preferences.store.setSavedLocations([austin])
        var sleeps = 0
        let viewModel = makeViewModel(sleep: { _ in
            sleeps += 1
            if sleeps > 2 { throw CancellationError() }
        })

        await viewModel.refreshWhileActive()

        // Two half hours passed, then it was cancelled.
        await waitUntil { self.api.currentRequests.count == 2 }
        XCTAssertEqual(sleeps, 3)
    }

    func testTheStaleRecheckOnlyRunsWhileThereIsAnError() async {
        preferences.store.setSavedLocations([austin])
        var sleeps = 0
        let viewModel = makeViewModel(sleep: { _ in
            sleeps += 1
            throw CancellationError()
        })

        await viewModel.recheckWhileStale()

        XCTAssertEqual(sleeps, 0)
    }

    func testANewNotificationCityIsRefreshedForTheNotifications() async {
        let viewModel = makeViewModel()

        await viewModel.notificationCityChanged()

        XCTAssertEqual(notificationCityRefreshes, 1)
    }

    // MARK: - My Location

    func testMyLocationFollowsThePhoneAtMostEveryFifteenMinutes() async {
        preferences.store.setSavedLocations([myLocation, austin])
        position.here = movedHere
        let viewModel = makeViewModel()

        viewModel.becameActive()
        await waitUntil { viewModel.locations.first == self.movedHere }
        viewModel.becameActive()
        await settle()

        XCTAssertEqual(position.reads, 1)
    }

    func testMyLocationIsAddedWhenThereAreNoCitiesYet() async {
        position.here = myLocation
        let viewModel = makeViewModel()

        viewModel.appeared()

        await waitUntil { viewModel.locations == [self.myLocation] }
    }

    func testMyLocationRemovedOnPurposeIsNotAddedBack() async {
        preferences.store.setSavedLocations([austin])
        position.here = myLocation
        let viewModel = makeViewModel()

        viewModel.appeared()
        viewModel.becameActive()
        await settle()

        XCTAssertEqual(position.reads, 0)
        XCTAssertEqual(viewModel.locations, [austin])
    }

    func testMyLocationIsAddedWhenAccessIsGrantedLater() async {
        preferences.store.setSavedLocations([austin])
        position.here = myLocation
        position.granted = false
        let viewModel = makeViewModel()

        viewModel.appeared()
        position.granted = true
        viewModel.becameActive()

        await waitUntil { viewModel.locations.contains(self.myLocation) }
    }

    func testPullToRefreshOnMyLocationReadsThePositionWhateverTheInterval() async {
        preferences.store.setSavedLocations([myLocation])
        position.here = myLocation
        let viewModel = makeViewModel()
        viewModel.appeared()
        await waitUntil { self.position.reads == 1 }

        position.here = movedHere
        await viewModel.pulledToRefresh()

        XCTAssertEqual(position.reads, 2)
        XCTAssertEqual(viewModel.locations, [movedHere])
        XCTAssertFalse(viewModel.isRefreshing)
    }

    // MARK: - Helpers

    private func makeViewModel(sleep: ((Duration) async throws -> Void)? = nil) -> WeatherForecastViewModel {
        WeatherForecastViewModel(
            repository: LocationWeatherRepository(weatherRepository: api.repository, preferences: preferences.store),
            cities: CityRepository(preferences: preferences.store, geocodingRepository: ScriptedGeocodingAPI().repository, onCityAdded: { _ in }),
            position: position,
            follower: MyLocationFollower(preferences: preferences.store, authorization: .denied, refresh: {}),
            refreshNotificationCity: { [unowned self] in notificationCityRefreshes += 1 },
            sleep: sleep,
            replanNotifications: {},
            onSettingsOpened: {},
            foregroundRefreshMinInterval: { 0 },
            config: { WeatherScreenConfig() }
        )
    }
}

@MainActor
private final class FakePosition: DevicePositioning {
    var granted = true
    var here: SavedLocation?
    private(set) var reads = 0

    func hasLocationPermission() -> Bool { granted }

    func currentPosition() async -> SavedLocation? {
        reads += 1
        return granted ? here : nil
    }
}
