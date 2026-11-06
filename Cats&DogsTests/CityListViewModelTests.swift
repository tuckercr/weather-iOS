import XCTest
@testable import Cats_Dogs

@MainActor
final class CityListViewModelTests: XCTestCase {
    private let austin = SavedLocation(label: "Austin", latitude: 30.27, longitude: -97.74)
    private let denver = SavedLocation(label: "Denver", latitude: 39.74, longitude: -104.99)
    private let seattle = SavedLocation(label: "Seattle", latitude: 47.61, longitude: -122.33)

    private var preferences: IsolatedPreferences!
    private var geocoding: ScriptedGeocodingAPI!

    override func setUp() async throws {
        preferences = IsolatedPreferences()
        geocoding = ScriptedGeocodingAPI()
    }

    override func tearDown() async throws {
        preferences.destroy()
    }

    // MARK: - updateCurrentLocation

    private let myLocation = SavedLocation(label: "My Location", latitude: 40, longitude: -83, isCurrentLocation: true)

    func testUpdateCurrentLocationMovesMyLocationAfterARealMove() {
        preferences.store.setSavedLocations([austin, myLocation])
        let viewModel = makeViewModel()

        // About 11 km north.
        viewModel.updateCurrentLocation(SavedLocation(label: "My Location", latitude: 40.1, longitude: -83, isCurrentLocation: true))

        let moved = SavedLocation(label: "My Location", latitude: 40.1, longitude: -83, isCurrentLocation: true)
        XCTAssertEqual(viewModel.locations, [austin, moved])
        XCTAssertEqual(preferences.reopened().savedLocations, [austin, moved])
    }

    func testUpdateCurrentLocationIgnoresGPSWobbleUnderAKilometre() {
        preferences.store.setSavedLocations([myLocation])
        let viewModel = makeViewModel()

        // About 110 m.
        viewModel.updateCurrentLocation(SavedLocation(label: "My Location", latitude: 40.001, longitude: -83, isCurrentLocation: true))

        XCTAssertEqual(viewModel.locations, [myLocation])
        XCTAssertEqual(preferences.reopened().savedLocations, [myLocation])
    }

    func testUpdateCurrentLocationDoesNothingWithoutMyLocation() {
        preferences.store.setSavedLocations([austin])
        let viewModel = makeViewModel()

        viewModel.updateCurrentLocation(myLocation)

        XCTAssertEqual(viewModel.locations, [austin])
    }

    func testUpdateCurrentLocationSaysWhetherMyLocationMoved() {
        preferences.store.setSavedLocations([myLocation])
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.updateCurrentLocation(SavedLocation(label: "My Location", latitude: 40.001, longitude: -83, isCurrentLocation: true)))
        XCTAssertTrue(viewModel.updateCurrentLocation(SavedLocation(label: "My Location", latitude: 40.1, longitude: -83, isCurrentLocation: true)))
    }

    // MARK: - Following a move made in storage

    func testAMoveMadeInStorageWhileOpenIsTakenUp() {
        preferences.store.setSavedLocations([austin, myLocation])
        let viewModel = makeViewModel()

        // Follow my location, while the screen is open.
        XCTAssertTrue(preferences.store.moveMyLocation(latitude: 40.1, longitude: -83))
        viewModel.followStoredMyLocation()

        let moved = SavedLocation(label: "My Location", latitude: 40.1, longitude: -83, isCurrentLocation: true)
        XCTAssertEqual(viewModel.locations, [austin, moved])
    }

    func testFollowingTheStoredListChangesNothingWhenMyLocationHasntMoved() {
        preferences.store.setSavedLocations([austin, myLocation])
        let viewModel = makeViewModel()
        viewModel.addLocation(denver)

        viewModel.followStoredMyLocation()

        XCTAssertEqual(viewModel.locations.map(\.label), ["Austin", "My Location", "Denver"])
    }

    func testACheckMadeByPullToRefreshHoldsOffTheNextOnReturn() {
        let viewModel = makeViewModel()
        let pulled = Date(timeIntervalSince1970: 1_793_990_000)

        viewModel.noteMyLocationChecked(now: pulled)

        XCTAssertFalse(viewModel.claimMyLocationCheck(now: pulled.addingTimeInterval(60)))
        XCTAssertTrue(viewModel.claimMyLocationCheck(now: pulled.addingTimeInterval(CityListViewModel.myLocationCheckInterval)))
    }

    // MARK: - init

    func testInitLoadsSavedLocationsAndActiveIndex() {
        preferences.store.setSavedLocations([austin, denver])
        preferences.store.setActiveLocationIndex(1)

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.locations, [austin, denver])
        XCTAssertEqual(viewModel.activeIndex, 1)
        XCTAssertEqual(viewModel.activeLocation, denver)
    }

    func testInitWithNoSavedLocationsMigratesFromLegacyLastCity() {
        preferences.store.setLastCity("Portland")

        let viewModel = makeViewModel()

        let migrated = SavedLocation(label: "Portland", latitude: nil, longitude: nil)
        XCTAssertEqual(viewModel.locations, [migrated])
        XCTAssertEqual(viewModel.activeLocation, migrated)
        XCTAssertEqual(preferences.reopened().savedLocations, [migrated])
    }

    func testInitWithNoSavedLocationsAndNoLastCityLeavesLocationsEmpty() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.locations.isEmpty)
        XCTAssertNil(viewModel.activeLocation)
    }

    func testInitClampsOutOfRangeActiveIndex() {
        preferences.store.setSavedLocations([austin, denver])
        preferences.store.setActiveLocationIndex(9)

        XCTAssertEqual(makeViewModel().activeIndex, 1)
    }

    // MARK: - addLocation

    func testAddLocationAppendsNewEntryMakesItActiveAndPersists() async {
        preferences.store.setSavedLocations([austin])
        let viewModel = makeViewModel()

        viewModel.addLocation(denver)

        XCTAssertEqual(viewModel.locations, [austin, denver])
        XCTAssertEqual(viewModel.activeLocation, denver)
        XCTAssertEqual(preferences.reopened().savedLocations, [austin, denver])
        XCTAssertEqual(preferences.reopened().activeLocationIndex, 1)
        XCTAssertTrue(geocoding.queries.isEmpty, "Locations that already have coordinates must not be geocoded")
    }

    func testAddLocationWithoutCoordinatesGeocodesThemAndKeepsTheEnteredLabel() async {
        geocoding.onSearch = { _ in [geocodingResult(name: "Paris", country: "FR", lat: 48.85, lon: 2.35)] }
        let viewModel = makeViewModel()

        viewModel.addLocation(SavedLocation(label: "paris", latitude: nil, longitude: nil))
        await waitUntil { viewModel.locations.first?.latitude != nil }

        let geocoded = SavedLocation(label: "paris", latitude: 48.85, longitude: 2.35)
        XCTAssertEqual(geocoding.queries, ["paris"])
        XCTAssertEqual(viewModel.locations, [geocoded])
        XCTAssertEqual(preferences.reopened().savedLocations, [geocoded])
    }

    /// Offline, geocoding can take up to the request timeout; the city must not wait for it.
    func testNameOnlyCityAppearsImmediatelyWhileGeocodingIsStillInFlight() async {
        let search = Gate<[GeocodingDirectDTO]>()
        geocoding.onSearch = { _ in try await search.value() }
        let viewModel = makeViewModel()

        viewModel.addLocation(SavedLocation(label: "Paris", latitude: nil, longitude: nil))

        XCTAssertEqual(viewModel.locations, [SavedLocation(label: "Paris", latitude: nil, longitude: nil)])
        XCTAssertEqual(viewModel.activeLocation?.label, "Paris")

        search.succeed([geocodingResult(name: "Paris", country: "FR", lat: 48.85, lon: 2.35)])
        await waitUntil { viewModel.locations.first?.latitude != nil }
    }

    func testAddingTheSameCityTwiceBeforeGeocodingReturnsDoesNotDuplicateIt() async {
        let search = Gate<[GeocodingDirectDTO]>()
        geocoding.onSearch = { _ in try await search.value() }
        let viewModel = makeViewModel()

        viewModel.addLocation(SavedLocation(label: "Paris", latitude: nil, longitude: nil))
        viewModel.addLocation(SavedLocation(label: "Paris", latitude: nil, longitude: nil))
        search.succeed([geocodingResult(name: "Paris", country: "FR", lat: 48.85, lon: 2.35)])
        await waitUntil { viewModel.locations.first?.latitude != nil }

        XCTAssertEqual(viewModel.locations.count, 1)
        XCTAssertEqual(geocoding.queries.count, 1)
    }

    func testRemovingACityWhileItIsBeingGeocodedDoesNotBringItBack() async {
        let search = Gate<[GeocodingDirectDTO]>()
        geocoding.onSearch = { _ in try await search.value() }
        preferences.store.setSavedLocations([austin])
        let viewModel = makeViewModel()
        viewModel.addLocation(SavedLocation(label: "Paris", latitude: nil, longitude: nil))
        await waitUntil { self.geocoding.queries.count == 1 }

        viewModel.removeLocation(at: 1)
        search.succeed([geocodingResult(name: "Paris", country: "FR", lat: 48.85, lon: 2.35)])
        await waitUntil { self.geocoding.completedSearches == 1 }
        await settle()

        XCTAssertEqual(viewModel.locations, [austin])
        XCTAssertEqual(preferences.reopened().savedLocations, [austin])
    }

    func testAddLocationWithoutCoordinatesIsStillSavedWhenGeocodingFails() async {
        geocoding.onSearch = { _ in throw URLError(.notConnectedToInternet) }
        let viewModel = makeViewModel()

        viewModel.addLocation(SavedLocation(label: "Nowhere", latitude: nil, longitude: nil))
        await waitUntil { self.geocoding.completedSearches == 1 }
        await settle()

        XCTAssertEqual(viewModel.locations, [SavedLocation(label: "Nowhere", latitude: nil, longitude: nil)])
    }

    /// A city whose first lookup failed gets its coordinates the next time the app opens.
    func testNameOnlyCitySavedEarlierIsGeocodedOnLaunch() async {
        preferences.store.setSavedLocations([SavedLocation(label: "London", latitude: nil, longitude: nil)])
        geocoding.onSearch = { _ in [geocodingResult(name: "London", country: "GB", lat: 51.51, lon: -0.13)] }

        let viewModel = makeViewModel()
        await waitUntil { viewModel.locations.first?.latitude != nil }

        let geocoded = SavedLocation(label: "London", latitude: 51.51, longitude: -0.13)
        XCTAssertEqual(viewModel.locations, [geocoded])
        XCTAssertEqual(preferences.reopened().savedLocations, [geocoded])
    }

    func testRetryingWhileALookupIsInFlightDoesNotLookItUpTwice() async {
        let search = Gate<[GeocodingDirectDTO]>()
        geocoding.onSearch = { _ in try await search.value() }
        let viewModel = makeViewModel()
        viewModel.addLocation(SavedLocation(label: "London", latitude: nil, longitude: nil))
        await waitUntil { self.geocoding.queries.count == 1 }

        viewModel.fillInMissingCoordinates()
        search.succeed([geocodingResult(name: "London", country: "GB", lat: 51.51, lon: -0.13)])
        await waitUntil { viewModel.locations.first?.latitude != nil }

        XCTAssertEqual(geocoding.queries, ["London"])
    }

    func testAddLocationWithDuplicateLabelSwitchesToExistingInsteadOfDuplicating() async {
        preferences.store.setSavedLocations([austin, denver])
        preferences.store.setActiveLocationIndex(1)
        let viewModel = makeViewModel()

        viewModel.addLocation(SavedLocation(label: "Austin", latitude: 1, longitude: 2))

        XCTAssertEqual(viewModel.locations, [austin, denver])
        XCTAssertEqual(viewModel.activeIndex, 0)
    }

    func testOnlyANewCityIsReportedAsAdded() {
        preferences.store.setSavedLocations([austin])
        var added: [CityAdded] = []
        let viewModel = CityListViewModel(
            preferences: preferences.store,
            geocodingRepository: geocoding.repository,
            onCityAdded: { added.append($0) }
        )

        viewModel.addLocation(denver)
        viewModel.addLocation(SavedLocation(label: "Austin", latitude: 1, longitude: 2))

        XCTAssertEqual(added.count, 1)
    }

    /// `city_added` says how: as the Add screen says, or else My Location or a typed name, with the
    /// provider search would use.
    func testAnAddedCityIsReportedWithHowItWasAdded() {
        var added: [CityAdded] = []
        var policy = CitySearchPolicy.standard
        policy.provider = .openWeather
        let viewModel = CityListViewModel(
            preferences: preferences.store,
            geocodingRepository: geocoding.repository,
            onCityAdded: { added.append($0) },
            readPolicy: { policy }
        )

        viewModel.addLocation(denver, added: CityAdded(source: .suggestion, provider: .openMeteo))
        viewModel.addLocation(myLocation)
        viewModel.addLocation(seattle)

        XCTAssertEqual(added, [
            CityAdded(source: .suggestion, provider: .openMeteo),
            CityAdded(source: .myLocation, provider: .openWeather),
            CityAdded(source: .typedName, provider: .openWeather),
        ])
    }

    /// Looked up as Add would with nothing tapped: a row named as the entry is, or none at all.
    func testANameOnlyCityStaysNameOnlyWithoutARowOfItsName() async {
        geocoding.onSearch = { _ in [geocodingResult(name: "Nashville", state: "Tennessee", lat: 36.17, lon: -86.78)] }
        let viewModel = makeViewModel()

        viewModel.addLocation(SavedLocation(label: "Nashvil", latitude: nil, longitude: nil))
        await waitUntil { self.geocoding.completedSearches == 1 }
        await settle()

        XCTAssertEqual(viewModel.locations, [SavedLocation(label: "Nashvil", latitude: nil, longitude: nil)])
    }

    /// Regression: the geocoded label used to replace the typed one, defeating the duplicate check.
    func testReAddingAGeocodedNameOnlyCityDoesNotDuplicateIt() async {
        geocoding.onSearch = { _ in [geocodingResult(name: "Paris", country: "FR", lat: 48.85, lon: 2.35)] }
        let viewModel = makeViewModel()
        viewModel.addLocation(SavedLocation(label: "paris", latitude: nil, longitude: nil))
        await waitUntil { viewModel.locations.first?.latitude != nil }

        viewModel.addLocation(SavedLocation(label: "paris", latitude: nil, longitude: nil))

        XCTAssertEqual(viewModel.locations.count, 1)
        XCTAssertEqual(geocoding.queries.count, 1)
    }

    // MARK: - removeLocation

    func testRemoveLocationRemovesEntryAtIndexAndPersists() {
        preferences.store.setSavedLocations([austin, denver, seattle])
        let viewModel = makeViewModel()

        viewModel.removeLocation(at: 1)

        XCTAssertEqual(viewModel.locations, [austin, seattle])
        XCTAssertEqual(preferences.reopened().savedLocations, [austin, seattle])
    }

    func testRemoveLocationClampsActiveIndexWhenActiveTabIsRemoved() {
        preferences.store.setSavedLocations([austin, denver])
        preferences.store.setActiveLocationIndex(1)
        let viewModel = makeViewModel()

        viewModel.removeLocation(at: 1)

        XCTAssertEqual(viewModel.activeIndex, 0)
        XCTAssertEqual(viewModel.activeLocation, austin)
        XCTAssertEqual(preferences.reopened().activeLocationIndex, 0)
    }

    func testRemoveLocationOnLastEntryResultsInEmptyListAndNilActiveLocation() {
        preferences.store.setSavedLocations([austin])
        let viewModel = makeViewModel()

        viewModel.removeLocation(at: 0)

        XCTAssertTrue(viewModel.locations.isEmpty)
        XCTAssertNil(viewModel.activeLocation)
    }

    func testRemoveLocationIgnoresOutOfRangeIndex() {
        preferences.store.setSavedLocations([austin])
        let viewModel = makeViewModel()

        viewModel.removeLocation(at: 4)

        XCTAssertEqual(viewModel.locations, [austin])
    }

    // MARK: - setActiveIndex

    func testSetActiveIndexUpdatesIndexAndPersists() {
        preferences.store.setSavedLocations([austin, denver])
        let viewModel = makeViewModel()

        viewModel.setActiveIndex(1)

        XCTAssertEqual(viewModel.activeLocation, denver)
        XCTAssertEqual(preferences.reopened().activeLocationIndex, 1)
    }

    func testSetActiveIndexIgnoresOutOfRangeIndex() {
        preferences.store.setSavedLocations([austin, denver])
        let viewModel = makeViewModel()

        viewModel.setActiveIndex(7)

        XCTAssertEqual(viewModel.activeIndex, 0)
        XCTAssertEqual(preferences.reopened().activeLocationIndex, 0)
    }

    // MARK: - reorderLocations (destination uses SwiftUI onMove semantics: the offset before removal)

    func testReorderLocationsMovesItemAndPersistsNewOrder() {
        preferences.store.setSavedLocations([austin, denver, seattle])
        let viewModel = makeViewModel()

        viewModel.reorderLocations(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(viewModel.locations, [denver, seattle, austin])
        XCTAssertEqual(preferences.reopened().savedLocations, [denver, seattle, austin])
    }

    func testReorderLocationsTracksActiveLocationWhenItMoves() {
        preferences.store.setSavedLocations([austin, denver, seattle])
        let viewModel = makeViewModel()

        viewModel.reorderLocations(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(viewModel.activeLocation, austin)
        XCTAssertEqual(preferences.reopened().activeLocationIndex, 2)
    }

    func testReorderLocationsAdjustsActiveIndexWhenItemMovesOverItFromBelow() {
        preferences.store.setSavedLocations([austin, denver, seattle])
        preferences.store.setActiveLocationIndex(1)
        let viewModel = makeViewModel()

        viewModel.reorderLocations(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(viewModel.locations, [denver, seattle, austin])
        XCTAssertEqual(viewModel.activeLocation, denver)
    }

    func testReorderLocationsAdjustsActiveIndexWhenItemMovesOverItFromAbove() {
        preferences.store.setSavedLocations([austin, denver, seattle])
        preferences.store.setActiveLocationIndex(1)
        let viewModel = makeViewModel()

        viewModel.reorderLocations(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(viewModel.locations, [seattle, austin, denver])
        XCTAssertEqual(viewModel.activeLocation, denver)
    }

    func testReorderLocationsLeavesActiveIndexAloneWhenMoveDoesNotCrossIt() {
        preferences.store.setSavedLocations([austin, denver, seattle])
        let viewModel = makeViewModel()

        viewModel.reorderLocations(from: IndexSet(integer: 1), to: 3)

        XCTAssertEqual(viewModel.locations, [austin, seattle, denver])
        XCTAssertEqual(viewModel.activeLocation, austin)
    }

    func testDroppingAnItemBackInPlaceChangesNothing() {
        preferences.store.setSavedLocations([austin, denver, seattle])
        let viewModel = makeViewModel()

        viewModel.reorderLocations(from: IndexSet(integer: 1), to: 1)

        XCTAssertEqual(viewModel.locations, [austin, denver, seattle])
    }

    private func makeViewModel() -> CityListViewModel {
        CityListViewModel(preferences: preferences.store, geocodingRepository: geocoding.repository, onCityAdded: { _ in })
    }

    func testMyLocationIsCheckedForAMoveAtMostEveryFifteenMinutes() {
        let viewModel = CityListViewModel(preferences: preferences.store)
        let start = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertTrue(viewModel.claimMyLocationCheck(now: start))
        XCTAssertFalse(viewModel.claimMyLocationCheck(now: start.addingTimeInterval(60)))
        XCTAssertFalse(viewModel.claimMyLocationCheck(now: start.addingTimeInterval(CityListViewModel.myLocationCheckInterval - 1)))
        XCTAssertTrue(viewModel.claimMyLocationCheck(now: start.addingTimeInterval(CityListViewModel.myLocationCheckInterval)))
    }

}
