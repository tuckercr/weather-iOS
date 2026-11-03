import CoreLocation
import XCTest
@testable import Cats_Dogs

@MainActor
final class MyLocationFollowerTests: XCTestCase {
    private let london = SavedLocation(label: "London", latitude: 51.5072, longitude: -0.1276)
    private let myLocation = SavedLocation(label: "My Location", latitude: 40.0, longitude: -83.0, isCurrentLocation: true)

    private var preferences: IsolatedPreferences!

    override func setUp() async throws {
        preferences = IsolatedPreferences()
    }

    override func tearDown() async throws {
        preferences.destroy()
    }

    // MARK: - The move rule

    func testARealMoveMovesMyLocationAndLeavesTheOtherCitiesAlone() {
        let moved = [london, myLocation].withMyLocation(atLatitude: 40.1, longitude: -83.0)

        XCTAssertEqual(moved?.map(\.label), ["London", "My Location"])
        XCTAssertEqual(moved?.last?.latitude, 40.1)
        XCTAssertEqual(moved?.first, london)
    }

    func testGPSWobbleUnderAKilometreChangesNothing() {
        XCTAssertNil([myLocation].withMyLocation(atLatitude: 40.001, longitude: -83.0))
    }

    func testWithoutAMyLocationThereIsNothingToMove() {
        XCTAssertNil([london].withMyLocation(atLatitude: 40.1, longitude: -83.0))
    }

    // MARK: - Following

    func testAMoveWhileFollowingMovesMyLocationAndRefreshes() async {
        var refreshes = 0
        let follower = makeFollower(switchedOn: true, authorization: .authorizedAlways) { refreshes += 1 }

        await follower.handle(CLLocation(latitude: 40.1, longitude: -83.0))

        XCTAssertEqual(preferences.store.savedLocations.last?.latitude, 40.1)
        XCTAssertEqual(refreshes, 1)
    }

    func testWobbleWhileFollowingNeitherMovesNorRefreshes() async {
        var refreshes = 0
        let follower = makeFollower(switchedOn: true, authorization: .authorizedAlways) { refreshes += 1 }

        await follower.handle(CLLocation(latitude: 40.001, longitude: -83.0))

        XCTAssertEqual(preferences.store.savedLocations.last?.latitude, 40.0)
        XCTAssertEqual(refreshes, 0)
    }

    func testWithoutAlwaysTheSwitchShowsOffAndMovesAreIgnored() async {
        var refreshes = 0
        let follower = makeFollower(switchedOn: true, authorization: .authorizedWhenInUse) { refreshes += 1 }

        await follower.handle(CLLocation(latitude: 40.1, longitude: -83.0))

        XCTAssertFalse(follower.isFollowing)
        XCTAssertEqual(preferences.store.savedLocations.last?.latitude, 40.0)
        XCTAssertEqual(refreshes, 0)
    }

    func testSwitchedOffMovesAreIgnoredEvenWithAlways() async {
        var refreshes = 0
        let follower = makeFollower(switchedOn: false, authorization: .authorizedAlways) { refreshes += 1 }

        await follower.handle(CLLocation(latitude: 40.1, longitude: -83.0))

        XCTAssertFalse(follower.isFollowing)
        XCTAssertEqual(refreshes, 0)
    }

    func testOnceIOSHasAskedForAlwaysTurningOnOpensTheSettingsApp() {
        preferences.store.setAlwaysLocationAsked()
        let follower = makeFollower(switchedOn: false, authorization: .authorizedWhenInUse) {}
        var openedSettings = 0

        follower.turnOn { openedSettings += 1 }

        XCTAssertEqual(openedSettings, 1)
        XCTAssertTrue(preferences.store.followMyLocation, "Kept, so granting Always in Settings turns it on")
    }

    func testWithAlwaysAlreadyGrantedTurningOnNeedsNoSettings() {
        let follower = makeFollower(switchedOn: false, authorization: .authorizedAlways) {}
        var openedSettings = 0

        follower.turnOn { openedSettings += 1 }

        XCTAssertEqual(openedSettings, 0)
        XCTAssertTrue(follower.isFollowing)

        follower.turnOff()
        XCTAssertFalse(follower.isFollowing)
        XCTAssertFalse(preferences.store.followMyLocation)
    }

    private func makeFollower(
        switchedOn: Bool,
        authorization: CLAuthorizationStatus,
        refresh: @escaping () -> Void
    ) -> MyLocationFollower {
        preferences.store.setSavedLocations([london, myLocation])
        preferences.store.setFollowMyLocation(switchedOn)
        return MyLocationFollower(preferences: preferences.store, authorization: authorization, refresh: { refresh() })
    }
}
