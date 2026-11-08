import CoreLocation
import XCTest
@testable import Cats_Dogs

@MainActor
final class LocationPermissionViewModelTests: XCTestCase {
    func testFetchLocationWithoutPermissionDeniesImmediatelyAndDoesNotQueryLocation() async {
        var locationQueries = 0
        let viewModel = LocationPermissionViewModel(
            authorizationStatus: { .denied },
            locationFetcher: {
                locationQueries += 1
                return CLLocation(latitude: 1, longitude: 2)
            }
        )

        viewModel.fetchLocation()
        await settle()

        XCTAssertEqual(viewModel.state, .permissionDenied)
        XCTAssertEqual(locationQueries, 0)
    }

    func testCanAskOnlyWhileIOSWouldStillPrompt() {
        // "Allow Once" and "Ask Next Time" come back as not determined on the next launch.
        XCTAssertTrue(LocationPermissionViewModel(authorizationStatus: { .notDetermined }).canRequestPermission())
        XCTAssertFalse(LocationPermissionViewModel(authorizationStatus: { .denied }).canRequestPermission())
        XCTAssertFalse(LocationPermissionViewModel(authorizationStatus: { .authorizedWhenInUse }).canRequestPermission())
    }

    func testNotDeterminedCountsAsNoPermission() {
        let viewModel = LocationPermissionViewModel(authorizationStatus: { .notDetermined })

        XCTAssertFalse(viewModel.hasLocationPermission())
    }

    func testFetchLocationShowsLocatingThenResolvesCurrentLocation() async {
        let gate = Gate<CLLocation?>()
        let viewModel = LocationPermissionViewModel(
            authorizationStatus: { .authorizedWhenInUse },
            locationFetcher: { try await gate.value() }
        )

        viewModel.fetchLocation()
        XCTAssertEqual(viewModel.state, .locating)

        gate.succeed(CLLocation(latitude: 35.96, longitude: -83.92))
        await waitUntil { viewModel.state != .locating }

        XCTAssertEqual(
            viewModel.state,
            .located(SavedLocation(label: "My Location", latitude: 35.96, longitude: -83.92, isCurrentLocation: true))
        )
    }

    func testCurrentPositionWaitsForAFixAndLeavesTheStateAlone() async {
        let viewModel = LocationPermissionViewModel(
            authorizationStatus: { .authorizedAlways },
            locationFetcher: { CLLocation(latitude: 36.03, longitude: -84.1) }
        )

        let here = await viewModel.currentPosition()

        XCTAssertEqual(here, SavedLocation(label: "My Location", latitude: 36.03, longitude: -84.1, isCurrentLocation: true))
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testCurrentPositionIsNilWithoutPermissionOrAFix() async {
        var asked = false
        let denied = LocationPermissionViewModel(
            authorizationStatus: { .denied },
            locationFetcher: { asked = true; return CLLocation(latitude: 1, longitude: 2) }
        )
        let noFix = LocationPermissionViewModel(authorizationStatus: { .authorizedWhenInUse }, locationFetcher: { nil })

        let deniedPosition = await denied.currentPosition()
        let noFixPosition = await noFix.currentPosition()

        XCTAssertNil(deniedPosition)
        XCTAssertFalse(asked)
        XCTAssertNil(noFixPosition)
    }

    func testFetchLocationFailsWhenNoCoordinatesAreReturned() async {
        let viewModel = LocationPermissionViewModel(
            authorizationStatus: { .authorizedAlways },
            locationFetcher: { nil }
        )

        viewModel.fetchLocation()
        await waitUntil { viewModel.state != .locating }

        XCTAssertEqual(viewModel.state, .failed)
    }

    func testFetchLocationFailsWhenLocationLookupThrows() async {
        let viewModel = LocationPermissionViewModel(
            authorizationStatus: { .authorizedWhenInUse },
            locationFetcher: { throw CLError(.locationUnknown) }
        )

        viewModel.fetchLocation()
        await waitUntil { viewModel.state != .locating }

        XCTAssertEqual(viewModel.state, .failed)
    }

    func testOnPermissionDeniedRecordsDeniedState() {
        let viewModel = LocationPermissionViewModel(authorizationStatus: { .notDetermined })

        viewModel.onPermissionDenied()

        XCTAssertEqual(viewModel.state, .permissionDenied)
    }

    func testUseMyLocationReportsADenialInsteadOfAskingAgain() {
        let denied = LocationPermissionViewModel(authorizationStatus: { .denied })
        XCTAssertFalse(denied.canOfferMyLocation)
        denied.useMyLocation()
        XCTAssertEqual(denied.state, .permissionDenied)

        XCTAssertTrue(LocationPermissionViewModel(authorizationStatus: { .notDetermined }).canOfferMyLocation)
    }

    func testUseMyLocationFetchesWhenAllowed() async {
        let allowed = LocationPermissionViewModel(
            authorizationStatus: { .authorizedWhenInUse },
            locationFetcher: { CLLocation(latitude: 1, longitude: 2) }
        )
        allowed.useMyLocation()
        await waitUntil { if case .located = allowed.state { true } else { false } }
    }
}
