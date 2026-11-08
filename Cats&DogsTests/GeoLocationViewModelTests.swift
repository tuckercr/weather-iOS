import XCTest
@testable import Cats_Dogs

@MainActor
final class GeoLocationViewModelTests: XCTestCase {
    private var api: ScriptedGeocodingAPI!
    private var viewModel: GeoLocationViewModel!

    override func setUp() async throws {
        api = ScriptedGeocodingAPI()
        viewModel = GeoLocationViewModel(geocodingRepository: api.repository)
    }

    func testShortInputClearsSuggestionsWithoutSearching() async {
        viewModel.onCityInputChange("A")
        await settle()

        XCTAssertEqual(viewModel.cityInput, "A")
        XCTAssertTrue(viewModel.citySuggestions.isEmpty)
        XCTAssertFalse(viewModel.citySuggestLoading)
        XCTAssertTrue(api.queries.isEmpty)
    }

    func testTypingSearchesAfterDebounceAndPublishesSuggestions() async {
        api.onSearch = { _ in [geocodingResult(name: "Austin", state: "Texas")] }

        viewModel.onCityInputChange("  Austin ")
        await waitUntil { !self.viewModel.citySuggestions.isEmpty }

        XCTAssertEqual(api.queries, ["Austin"])
        XCTAssertEqual(viewModel.citySuggestions.map(\.label), ["Austin, Texas, US"])
        XCTAssertFalse(viewModel.citySuggestLoading)
    }

    func testAddLocationShowsAPlaceThatsSavedRatherThanAddingItAgain() async {
        api.onSearch = { _ in [geocodingResult(name: "Austin", state: "Texas")] }
        viewModel.open(savedLocations: [SavedLocation(label: "Austin, Texas, US", latitude: 30.27, longitude: -97.74)])

        viewModel.onCityInputChange("Austin")
        await waitUntil { !self.viewModel.citySuggestions.isEmpty }

        let austin = viewModel.citySuggestions[0]
        XCTAssertEqual(viewModel.choose(austin), .goTo(0))
        XCTAssertEqual(viewModel.submit(), .goTo(0))
        XCTAssertEqual(viewModel.target, austin)
        XCTAssertFalse(viewModel.hasMyLocation)
    }

    func testAddLocationAddsAnUnsavedPlaceAndSaysHow() async {
        api.onSearch = { _ in [geocodingResult(name: "Austin", state: "Texas")] }
        viewModel.open(savedLocations: [])

        viewModel.onCityInputChange("Austin")
        await waitUntil { !self.viewModel.citySuggestions.isEmpty }

        guard case let .add(location, name, tapped) = viewModel.choose(viewModel.citySuggestions[0]) else {
            return XCTFail("Expected the row to add Austin")
        }
        XCTAssertEqual(location.label, "Austin, Texas, US")
        XCTAssertEqual(name, "Austin")
        XCTAssertEqual(tapped.source, .suggestion)
        guard case let .add(_, _, typed)? = viewModel.submit() else {
            return XCTFail("Expected the button to add Austin")
        }
        XCTAssertEqual(typed.source, .typedMatch)
        let here = SavedLocation(label: "My Location", latitude: 30.3, longitude: -97.7, isCurrentLocation: true)
        XCTAssertEqual(viewModel.addingMyLocation(here), .add(here, name: "My Location", CityAdded(source: .myLocation, provider: viewModel.policy.provider)))
    }

    func testRapidTypingOnlySearchesForTheFinalInput() async {
        api.onSearch = { query in [geocodingResult(name: query)] }

        viewModel.onCityInputChange("Au")
        viewModel.onCityInputChange("Aus")
        viewModel.onCityInputChange("Austin")
        await waitUntil { !self.viewModel.citySuggestions.isEmpty }

        XCTAssertEqual(api.queries, ["Austin"])
    }

    func testLatestCityInputWinsWhenAnEarlierSearchIsStillRunning() async {
        let firstSearch = Gate<[GeocodingDirectDTO]>()
        let secondSearch = Gate<[GeocodingDirectDTO]>()
        api.onSearch = { query in
            try await (query == "Aus" ? firstSearch : secondSearch).value()
        }

        viewModel.onCityInputChange("Aus")
        await waitUntil { self.api.queries == ["Aus"] }
        viewModel.onCityInputChange("Denver")
        await waitUntil { self.api.queries == ["Aus", "Denver"] }

        secondSearch.succeed([geocodingResult(name: "Denver", state: "Colorado")])
        await waitUntil { !self.viewModel.citySuggestions.isEmpty }
        firstSearch.succeed([geocodingResult(name: "Austin", state: "Texas")])
        await waitUntil { self.api.completedSearches == 2 }
        await settle()

        XCTAssertEqual(viewModel.citySuggestions.map(\.label), ["Denver, Colorado, US"])
        XCTAssertFalse(viewModel.citySuggestLoading)
    }

    func testFailedSearchClearsSuggestionsAndLoading() async {
        api.onSearch = { _ in throw URLError(.notConnectedToInternet) }

        viewModel.onCityInputChange("Austin")
        await waitUntil { self.api.queries.count == 1 && !self.viewModel.citySuggestLoading }

        XCTAssertTrue(viewModel.citySuggestions.isEmpty)
    }

    func testAFailedSearchSaysSoUntilTheTextChanges() async {
        api.onSearch = { _ in throw URLError(.notConnectedToInternet) }

        viewModel.onCityInputChange("London")
        await waitUntil { self.api.queries.count == 1 && !self.viewModel.citySuggestLoading }

        XCTAssertTrue(viewModel.searchFailed)
        viewModel.onCityInputChange("Londo")
        XCTAssertFalse(viewModel.searchFailed)
    }

    func testASearchThatFindsNothingIsNotAFailure() async {
        api.onSearch = { _ in [] }

        viewModel.onCityInputChange("Nashvile")
        await waitUntil { self.api.completedSearches == 1 }
        await settle()

        XCTAssertFalse(viewModel.searchFailed)
        XCTAssertTrue(viewModel.citySuggestions.isEmpty)
    }
}
