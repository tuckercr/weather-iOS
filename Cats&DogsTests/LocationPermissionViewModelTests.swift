import CoreLocation
import XCTest
@testable import Cats_Dogs

@MainActor
final class LocationPermissionViewModelTests: XCTestCase {
    func testFetchLocationWithoutPermissionDeniesImmediatelyAndDoesNotQueryLocation() async {
        var locationQueries = 0
        let viewModel = makeViewModel(
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
        XCTAssertTrue(makeViewModel(authorizationStatus: { .notDetermined }).canRequestPermission())
        XCTAssertFalse(makeViewModel(authorizationStatus: { .denied }).canRequestPermission())
        XCTAssertFalse(makeViewModel(authorizationStatus: { .authorizedWhenInUse }).canRequestPermission())
    }

    func testNotDeterminedCountsAsNoPermission() {
        let viewModel = makeViewModel(authorizationStatus: { .notDetermined })

        XCTAssertFalse(viewModel.hasLocationPermission())
    }

    func testFetchLocationShowsLocatingThenResolvesCurrentLocation() async {
        let gate = Gate<CLLocation?>()
        let viewModel = makeViewModel(
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

    func testCurrentPositionWaitsForAFix() async {
        let repository = LocationRepository(
            authorizationStatus: { .authorizedAlways },
            locationFetcher: { CLLocation(latitude: 36.03, longitude: -84.1) }
        )

        let here = await repository.currentPosition()

        XCTAssertEqual(here, SavedLocation(label: "My Location", latitude: 36.03, longitude: -84.1, isCurrentLocation: true))
    }

    func testCurrentPositionIsNilWithoutPermissionOrAFix() async {
        var asked = false
        let denied = LocationRepository(
            authorizationStatus: { .denied },
            locationFetcher: { asked = true; return CLLocation(latitude: 1, longitude: 2) }
        )
        let noFix = LocationRepository(authorizationStatus: { .authorizedWhenInUse }, locationFetcher: { nil })

        let deniedPosition = await denied.currentPosition()
        let noFixPosition = await noFix.currentPosition()

        XCTAssertNil(deniedPosition)
        XCTAssertFalse(asked)
        XCTAssertNil(noFixPosition)
    }

    func testFetchLocationFailsWhenNoCoordinatesAreReturned() async {
        let viewModel = makeViewModel(
            authorizationStatus: { .authorizedAlways },
            locationFetcher: { nil }
        )

        viewModel.fetchLocation()
        await waitUntil { viewModel.state != .locating }

        XCTAssertEqual(viewModel.state, .failed)
    }

    func testFetchLocationFailsWhenLocationLookupThrows() async {
        let viewModel = makeViewModel(
            authorizationStatus: { .authorizedWhenInUse },
            locationFetcher: { throw CLError(.locationUnknown) }
        )

        viewModel.fetchLocation()
        await waitUntil { viewModel.state != .locating }

        XCTAssertEqual(viewModel.state, .failed)
    }

    func testOnPermissionDeniedRecordsDeniedState() {
        let viewModel = makeViewModel(authorizationStatus: { .notDetermined })

        viewModel.onPermissionDenied()

        XCTAssertEqual(viewModel.state, .permissionDenied)
    }

    func testUseMyLocationReportsADenialInsteadOfAskingAgain() {
        let denied = makeViewModel(authorizationStatus: { .denied })
        XCTAssertFalse(denied.canOfferMyLocation)
        denied.useMyLocation()
        XCTAssertEqual(denied.state, .permissionDenied)

        XCTAssertTrue(makeViewModel(authorizationStatus: { .notDetermined }).canOfferMyLocation)
    }

    func testUseMyLocationFetchesWhenAllowed() async {
        let allowed = makeViewModel(
            authorizationStatus: { .authorizedWhenInUse },
            locationFetcher: { CLLocation(latitude: 1, longitude: 2) }
        )
        allowed.useMyLocation()
        await waitUntil { if case .located = allowed.state { true } else { false } }
    }

    func testAskingWithoutAPromptToShowSaysWhetherAccessIsOn() async {
        let allowed = await LocationRepository(authorizationStatus: { .authorizedWhenInUse }).requestPermission()
        let denied = await LocationRepository(authorizationStatus: { .denied }).requestPermission()

        XCTAssertTrue(allowed)
        XCTAssertFalse(denied)
    }

    private func makeViewModel(
        authorizationStatus: @escaping () -> CLAuthorizationStatus,
        locationFetcher: (() async throws -> CLLocation?)? = nil
    ) -> LocationPermissionViewModel {
        LocationPermissionViewModel(
            location: LocationRepository(authorizationStatus: authorizationStatus, locationFetcher: locationFetcher)
        )
    }
}
