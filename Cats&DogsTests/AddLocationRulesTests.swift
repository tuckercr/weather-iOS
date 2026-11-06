import XCTest
@testable import Cats_Dogs

/// The same cases as Android's `AddLocationRulesTest`.
@MainActor
final class AddLocationRulesTests: XCTestCase {
    // Live Open-Meteo rows (11-05), in the order a phone outside the US sees them.
    private let malmo = CitySuggestion(label: "Malmö, Skåne County, SE", weatherLat: 55.61, weatherLon: 13.0, population: 362_133)
    private let malmoNebraska = CitySuggestion(label: "Malmo, Nebraska, US", weatherLat: 41.27, weatherLon: -96.72, population: 118)
    private let nashik = CitySuggestion(label: "Nashik, Maharashtra, IN", weatherLat: 19.99, weatherLon: 73.79, population: 1_486_053)
    private let nashville = CitySuggestion(label: "Nashville, Tennessee, US", weatherLat: 36.17, weatherLon: -86.78, population: 689_447)
    private let nas = CitySuggestion(label: "Nås, Dalarna County, SE", weatherLat: 60.45, weatherLon: 14.48, population: 205)
    private let bathinda = CitySuggestion(label: "Bathinda, Punjab, IN", weatherLat: 30.21, weatherLon: 74.95, population: 285_788)
    private let bath = CitySuggestion(label: "Bath, England, GB", weatherLat: 51.38, weatherLon: -2.36, population: 101_557)
    private let bathMaine = CitySuggestion(label: "Bath, Maine, US", weatherLat: 43.91, weatherLon: -69.82, population: 8_305)
    private let london = CitySuggestion(label: "London, England, GB", weatherLat: 51.51, weatherLon: -0.13)
    private let londonOntario = CitySuggestion(label: "London, Ontario, CA", weatherLat: 42.98, weatherLon: -81.25)

    private func action(
        _ typed: String,
        _ suggestions: [CitySuggestion],
        saved: [SavedLocation] = [],
        searching: Bool = false,
        searchFailed: Bool = false
    ) -> AddLocationAction {
        AddLocationRules.action(typed: typed, suggestions: suggestions, searching: searching, searchFailed: searchFailed, saved: saved)
    }

    func testTypingWithoutAccentsAddsThePlaceThatHasThem() {
        XCTAssertEqual(action("Malmo", [malmo, malmoNebraska]), .add(malmo))
        XCTAssertEqual(action("malmö ", [malmo, malmoNebraska]), .add(malmo))
    }

    func testAMatchFarSmallerThanARowAboveItAsksForAPick() {
        // Nashik is over 7,000 times Nås, so "Nas" doesn't quietly add Sweden.
        XCTAssertEqual(action("Nas", [nashik, nashville, nas]), .pickFromList)
        // Bathinda is only 2.8 times Bath; Bath, Maine is 34 times smaller.
        XCTAssertEqual(action("Bath", [bathinda, bath]), .add(bath))
        XCTAssertEqual(action("Bath", [bathinda, bathMaine, bath]), .pickFromList)
    }

    func testTheSizeCheckFollowsTheGuardsRulesForMissingPopulationsAndZero() {
        let noPopulation = CitySuggestion(label: "Nash, Wales, GB", weatherLat: 51.6, weatherLon: -3.0)
        let village = CitySuggestion(label: "Nashville, Georgia, US", weatherLat: 31.2, weatherLon: -83.25, population: 4_900)
        // A row with no population can't pass one that has one...
        XCTAssertNil(AddLocationRules.typedMatch("Nash", in: [nashik, noPopulation]))
        // ...and a row with no population blocks nothing.
        XCTAssertEqual(AddLocationRules.typedMatch("Nashville", in: [london, village]), village)
        // 0 turns the check off.
        XCTAssertEqual(AddLocationRules.typedMatch("Nas", in: [nashik, nas], sizeRatio: 0), nas)
    }

    func testNoRowNamedWhatWasTypedAsksForAPickAndTextAfterACommaIsIgnored() {
        XCTAssertEqual(action("Nash", [nashik, nashville]), .pickFromList)
        XCTAssertEqual(action("London, Ontario", [london, londonOntario]), .add(london))
    }

    func testASavedPlaceIsGoneToNotAddedAgain() {
        let saved = [
            SavedLocation(label: "My Location", latitude: 51.5, longitude: -0.12, isCurrentLocation: true),
            SavedLocation(label: "Tokyo, JP", latitude: 35.68, longitude: 139.69),
            SavedLocation(label: "London, England, GB", latitude: 51.51, longitude: -0.13),
        ]
        XCTAssertEqual(action("London", [london], saved: saved), .goTo(london, index: 2))
    }

    func testTwoPlacesSharingALabelAreNotTakenForEachOther() {
        let richmondLondon = SavedLocation(label: "Richmond, England, GB", latitude: 51.46, longitude: -0.30)
        let richmondYorkshire = CitySuggestion(
            label: "Richmond, England, GB", weatherLat: 54.40, weatherLon: -1.74, admin1: "England", admin2: "North Yorkshire"
        )

        XCTAssertNil(AddLocationRules.savedIndex(of: richmondYorkshire, in: [richmondLondon]))
        XCTAssertEqual(AddLocationRules.labelToSave(richmondYorkshire, saved: [richmondLondon]), "Richmond, North Yorkshire, England, GB")
        XCTAssertEqual(AddLocationRules.labelToSave(richmondYorkshire, saved: []), "Richmond, England, GB")
    }

    func testSavedMeansWithin2KmOrTheSameLabelWhenNameOnlyButNeverMyLocation() {
        let myLocation = SavedLocation(label: "My Location", latitude: 55.61, longitude: 13.0, isCurrentLocation: true)
        let spelledOtherwise = SavedLocation(label: "Malmo, Skane, SE", latitude: 55.605, longitude: 13.003)
        let nameOnly = SavedLocation(label: "Malmö, Skåne County, SE", latitude: nil, longitude: nil)
        let farAway = SavedLocation(label: "Malmö, Kalmar, SE", latitude: 57.25, longitude: 16.47)

        XCTAssertNil(AddLocationRules.savedIndex(of: malmo, in: [myLocation]))
        XCTAssertEqual(AddLocationRules.savedIndex(of: malmo, in: [spelledOtherwise]), 0)
        XCTAssertEqual(AddLocationRules.savedIndex(of: malmo, in: [nameOnly]), 0)
        XCTAssertNil(AddLocationRules.savedIndex(of: malmo, in: [farAway]))
    }

    func testNoListSaysWhy() {
        XCTAssertEqual(action("M", []), AddLocationAction.none)
        XCTAssertEqual(action("Malmo", [], searching: true), AddLocationAction.none)
        XCTAssertEqual(action(" Malmo ", [], searchFailed: true), .addByName("Malmo"))
        XCTAssertEqual(action("Nashvile", []), .notFound)
    }

    func testAListStillOnScreenWhileTheNextSearchRunsKeepsItsButton() {
        XCTAssertEqual(action("Malmo", [malmo], searching: true), .add(malmo))
    }

    func testTheTypedLettersAreFoundInTheNameForBoldAccentsIgnored() {
        XCTAssertEqual(AddLocationRules.matchedPrefixLength(name: "Nashik", typed: "Nas"), 3)
        XCTAssertEqual(AddLocationRules.matchedPrefixLength(name: "Nåshult", typed: "nas"), 3)
        XCTAssertEqual(AddLocationRules.matchedPrefixLength(name: "Malmö", typed: "Malmo"), 5)
        XCTAssertEqual(AddLocationRules.matchedPrefixLength(name: "New York", typed: "New Y"), 5)
        XCTAssertEqual(AddLocationRules.matchedPrefixLength(name: "Ahvāz", typed: "Nas"), 0)
        XCTAssertEqual(AddLocationRules.matchedPrefixLength(name: "Nas", typed: "Nashville"), 0)
    }

    func testSuggestionsSplitTheirLabelForTheScreen() {
        XCTAssertEqual(malmo.name, "Malmö")
        XCTAssertEqual(malmo.detail, "Skåne County, SE")
        XCTAssertEqual(malmo.shortLabel, "Malmö, SE")
        let nameOnly = CitySuggestion(label: "London", weatherLat: 0, weatherLon: 0)
        XCTAssertEqual(nameOnly.detail, "")
        XCTAssertEqual(nameOnly.shortLabel, "London")
    }
}
