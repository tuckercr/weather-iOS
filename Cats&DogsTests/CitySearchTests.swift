import CoreLocation
import XCTest
@testable import Cats_Dogs

/// SEARCH.md's rules, and its worked examples checked against live Open-Meteo rows.
@MainActor
final class CitySearchTests: XCTestCase {
    private let nashville = CLLocationCoordinate2D(latitude: 36.17, longitude: -86.78)
    private let augusta = CLLocationCoordinate2D(latitude: 44.31, longitude: -69.78)

    /// "Name, state, country code" of the first `count` rows, as a phone in `region` would see them.
    private func ranked(
        _ places: [OpenMeteoPlaceDTO],
        _ query: String,
        region: String?,
        myLocation: CLLocationCoordinate2D? = nil,
        policy: CitySearchPolicy? = nil,
        count: Int = 3
    ) -> [String] {
        let policy = policy ?? .standard
        let rows = places.map(GeocodingRepository.suggestion(from:))
        let origin = CitySearchOrigin(region: region, myLocation: myLocation)
        return CitySearchRanking.rank(rows, query: .parse(query), provider: .openMeteo, policy: policy, origin: origin)
            .prefix(count)
            .map { [$0.name, $0.admin1, $0.countryCode].compactMap { $0 }.joined(separator: ", ") }
    }

    // MARK: - What was typed

    func testTheTypedTextIsANameWithQualifiersAZipOrNothing() {
        XCTAssertEqual(CitySearchQuery.parse("Nashv"), .name("Nashv", qualifiers: []))
        XCTAssertEqual(CitySearchQuery.parse("  Paris , TX "), .name("Paris", qualifiers: ["TX"]))
        XCTAssertEqual(CitySearchQuery.parse("Richmond, North Yorkshire, GB"), .name("Richmond", qualifiers: ["North Yorkshire", "GB"]))
        XCTAssertEqual(CitySearchQuery.parse("90210"), .zip("90210"))
        XCTAssertEqual(CitySearchQuery.parse("N"), .nothing)
        XCTAssertEqual(CitySearchQuery.parse(", Texas"), .nothing)
    }

    func testPostcodesSearchNothingButTownsWithNumbersStillSearch() {
        for postcode in ["E14", "M1", "SW1A 1AA", "K1A 0B1", "D02 X285", "90210-1234", "1234", "123 45"] {
            XCTAssertEqual(CitySearchQuery.parse(postcode), .nothing, postcode)
        }
        for town in ["100 Mile House", "23 August", "10th of Ramadan City", "1012 AB"] {
            XCTAssertEqual(CitySearchQuery.parse(town), .name(town, qualifiers: []), town)
        }
    }

    // MARK: - Filtering

    func testOnlyPopulatedPlacesAreKeptAndNeverHistoricalAbandonedOrDestroyedOnes() {
        func row(_ code: String?) -> CitySuggestion {
            CitySuggestion(label: "Town, X, GB", weatherLat: 0, weatherLon: 0, featureCode: code, provider: .openMeteo)
        }
        XCTAssertEqual(["PPL", "PPLA2", "PPLC", "PPLX"].map { CitySearchRanking.isPopulatedPlace(row($0)) }, [true, true, true, true])
        XCTAssertEqual(["PPLH", "PPLQ", "PPLW", "AIRP", "PRK"].map { CitySearchRanking.isPopulatedPlace(row($0)) }, [false, false, false, false, false])
        XCTAssertTrue(CitySearchRanking.isPopulatedPlace(row(nil)), "OpenWeather's rows have no kind")
    }

    func testTextAfterACommaStartsAWordOfTheStateCountyOrCountry() {
        XCTAssertEqual(ranked(LiveSearchFixtures.paris, "Paris, TX", region: "GB", count: 1), ["Paris, Texas, US"])
        XCTAssertEqual(ranked(LiveSearchFixtures.paris, "paris, france", region: "US", count: 1), ["Paris, Île-de-France Region, FR"])
        XCTAssertEqual(ranked(LiveSearchFixtures.london, "London, Ontario", region: "GB", count: 1), ["London, Ontario, CA"])
        XCTAssertEqual(ranked(LiveSearchFixtures.richmond, "Richmond, North Yorkshire", region: "US", count: 5), ["Richmond, England, GB"])
        // "London" starts a word of "Greater London".
        XCTAssertEqual(ranked(LiveSearchFixtures.richmond, "Richmond, London", region: "US", count: 5), ["Richmond, England, GB"])
    }

    func testAZipKeepsOnlyUSRows() {
        let rows = [
            CitySuggestion(label: "Beverly Hills, California, US", weatherLat: 34.07, weatherLon: -118.4, countryCode: "US", featureCode: "PPL", provider: .openMeteo),
            CitySuggestion(label: "Somewhere, Bavaria, DE", weatherLat: 48, weatherLon: 11, countryCode: "DE", featureCode: "PPL", provider: .openMeteo),
        ]
        let shown = CitySearchRanking.rank(rows, query: .zip("90210"), provider: .openMeteo, policy: .standard, origin: CitySearchOrigin())
        XCTAssertEqual(shown.map(\.countryCode), ["US"])
    }

    func testRowsMergeOnlyWhenTheSameLabelIsWithin2Km() {
        let paris = CitySuggestion(label: "Paris, Ile-de-France, FR", weatherLat: 48.8534, weatherLon: 2.3488)
        let parisAgain = CitySuggestion(label: "Paris, Ile-de-France, FR", weatherLat: 48.8566, weatherLon: 2.3522)
        let richmondA = CitySuggestion(label: "Richmond, England, GB", weatherLat: 51.46, weatherLon: -0.30)
        let richmondB = CitySuggestion(label: "Richmond, England, GB", weatherLat: 54.40, weatherLon: -1.74)

        XCTAssertEqual(CitySearchRanking.mergingSamePlaces([paris, parisAgain, richmondA, richmondB]), [paris, richmondA, richmondB])
    }

    func testPlacesThatWouldReadTheSameGetTheirCounty() {
        let rows = [
            CitySuggestion(label: "Richmond, England, GB", weatherLat: 51.46, weatherLon: -0.30, admin1: "England", admin2: "Greater London"),
            CitySuggestion(label: "Richmond, England, GB", weatherLat: 54.40, weatherLon: -1.74, admin1: "England", admin2: "North Yorkshire"),
            CitySuggestion(label: "Richmond, Virginia, US", weatherLat: 37.55, weatherLon: -77.46, admin1: "Virginia", admin2: "City of Richmond"),
        ]
        XCTAssertEqual(CitySearchRanking.withCounties(rows).map(\.label), [
            "Richmond, Greater London, England, GB",
            "Richmond, North Yorkshire, England, GB",
            "Richmond, Virginia, US",
        ])
    }

    // MARK: - Sorting: SEARCH.md's worked examples

    func testParisStaysFirstForAUSPhoneThanksToTheSizeGuard() {
        XCTAssertEqual(ranked(LiveSearchFixtures.paris, "Paris", region: "US", count: 2), ["Paris, Île-de-France Region, FR", "Paris, Texas, US"])
        // Without the guard, Texas would pass France.
        var noGuard = CitySearchPolicy.standard
        noGuard.sizeRatio = 0
        XCTAssertEqual(ranked(LiveSearchFixtures.paris, "Paris", region: "US", policy: noGuard, count: 1), ["Paris, Texas, US"])
    }

    func testParisFromTennesseeGivesTheNearestParisesAfterFrance() {
        XCTAssertEqual(
            ranked(LiveSearchFixtures.paris, "Paris", region: "US", myLocation: nashville, count: 4),
            ["Paris, Île-de-France Region, FR", "Paris, Tennessee, US", "Paris, Kentucky, US", "Paris, Illinois, US"]
        )
    }

    func testNasOnAUSPhoneHasNashvilleFirstAndNashTexasEighth() {
        XCTAssertEqual(ranked(LiveSearchFixtures.nas, "Nas", region: "US", count: 8), [
            "Nashville, Tennessee, US", "Nashik, Maharashtra, IN", "Nassau, New Providence, BS", "Nasiriyah, Dhi Qar, IQ",
            "Ahvāz, Khuzestan, IR", "Grozny, Chechnya, RU", "Nasimshahr, Tehran, IR", "Nash, Texas, US",
        ])
        // Country-first off keeps the provider's order.
        var providerOrder = CitySearchPolicy.standard
        providerOrder.countryFirst = false
        XCTAssertEqual(ranked(LiveSearchFixtures.nas, "Nas", region: "US", policy: providerOrder, count: 1), ["Nashik, Maharashtra, IN"])
    }

    func testTheNearestSameNamePlaceComesFirstUnlessAFarBiggerOneIsAbove() {
        XCTAssertEqual(ranked(LiveSearchFixtures.springfield, "Springfield", region: "US", myLocation: nashville, count: 1), ["Springfield, Tennessee, US"])
        XCTAssertEqual(ranked(LiveSearchFixtures.portland, "Portland", region: "US", myLocation: augusta, count: 2), ["Portland, Maine, US", "Portland, Oregon, US"])
        XCTAssertEqual(ranked(LiveSearchFixtures.birmingham, "Birmingham", region: "US", count: 2), ["Birmingham, Alabama, US", "Birmingham, England, GB"])
        XCTAssertEqual(ranked(LiveSearchFixtures.sydney, "Sydney", region: "CA", count: 2), ["Sydney, New South Wales, AU", "Sydney, Nova Scotia, CA"])
        XCTAssertEqual(ranked(LiveSearchFixtures.london, "London", region: "CA", count: 2), ["London, England, GB", "London, Ontario, CA"])
        // London is 21 times London, Ontario: just over the default line.
        var looser = CitySearchPolicy.standard
        looser.sizeRatio = 25
        XCTAssertEqual(ranked(LiveSearchFixtures.london, "London", region: "CA", policy: looser, count: 1), ["London, Ontario, CA"])
    }

    func testResultsAreTrimmedToThePolicy() {
        var three = CitySearchPolicy.standard
        three.results = 3
        XCTAssertEqual(ranked(LiveSearchFixtures.nas, "Nas", region: "US", policy: three, count: 10).count, 3)
    }

    func testTheOpenWeatherFallbackIsNeitherFilteredNorSorted() {
        let rows = [
            CitySuggestion(label: "Paris, Ile-de-France, FR", weatherLat: 48.85, weatherLon: 2.35, countryCode: "FR"),
            CitySuggestion(label: "Paris, Texas, US", weatherLat: 33.66, weatherLon: -95.56, countryCode: "US"),
        ]
        let shown = CitySearchRanking.rank(
            rows, query: .parse("Paris, TX"), provider: .openWeather, policy: .standard,
            origin: CitySearchOrigin(region: "US", myLocation: nashville)
        )
        XCTAssertEqual(shown, rows)
    }
}

/// Open-Meteo's search, scripted.
@MainActor
final class ScriptedOpenMeteoGeocodingAPI: OpenMeteoGeocodingAPI, @unchecked Sendable {
    private(set) var searches: [(name: String, count: Int)] = []
    var onSearch: (String) async throws -> [OpenMeteoPlaceDTO] = { _ in [] }

    func search(name: String, count: Int) async throws -> [OpenMeteoPlaceDTO] {
        searches.append((name, count))
        return try await onSearch(name)
    }
}

@MainActor
final class CitySearchRepositoryTests: XCTestCase {
    private var openWeather: ScriptedGeocodingAPI!
    private var openMeteo: ScriptedOpenMeteoGeocodingAPI!
    private var repository: GeocodingRepository!

    override func setUp() async throws {
        openWeather = ScriptedGeocodingAPI()
        openMeteo = ScriptedOpenMeteoGeocodingAPI()
        repository = GeocodingRepository(client: openWeather, openMeteo: openMeteo)
    }

    func testOpenMeteoIsSearchedForTheNameAndItsRowsRanked() async {
        openMeteo.onSearch = { _ in LiveSearchFixtures.nas }

        let rows = try! await repository.searchCities(query: "Nas", origin: CitySearchOrigin(region: "US")).get()

        XCTAssertEqual(openMeteo.searches.map(\.name), ["Nas"])
        XCTAssertEqual(openMeteo.searches.first?.count, 20)
        XCTAssertEqual(rows.count, 8)
        XCTAssertEqual(rows.first?.label, "Nashville, Tennessee, US")
        XCTAssertEqual(rows.first?.provider, .openMeteo)
        XCTAssertTrue(openWeather.queries.isEmpty)
    }

    func testTextAfterACommaAsksForAHundredRowsAndOnlyTheNameIsSent() async {
        openMeteo.onSearch = { _ in LiveSearchFixtures.richmond }

        let rows = try! await repository.searchCities(query: "Richmond, North Yorkshire").get()

        XCTAssertEqual(openMeteo.searches.map(\.name), ["Richmond"])
        XCTAssertEqual(openMeteo.searches.first?.count, 100)
        XCTAssertEqual(rows.map(\.admin2), ["North Yorkshire"])
    }

    func testAFailureFallsBackToOpenWeatherWithTheTextAsTyped() async {
        openMeteo.onSearch = { _ in throw URLError(.timedOut) }
        openWeather.onSearch = { _ in [geocodingResult(name: "Paris", country: "FR", state: "Ile-de-France", lat: 48.85, lon: 2.35)] }

        let rows = try! await repository.searchCities(query: " Paris, FR ").get()

        XCTAssertEqual(openWeather.queries, ["Paris, FR"])
        XCTAssertEqual(rows.map(\.label), ["Paris, Ile-de-France, FR"])
        XCTAssertEqual(rows.first?.provider, .openWeather)
    }

    func testAnEmptyAnswerIsAnAnswerNotAFailure() async {
        openMeteo.onSearch = { _ in [] }

        let rows = try! await repository.searchCities(query: "Nashvile").get()

        XCTAssertTrue(rows.isEmpty)
        XCTAssertTrue(openWeather.queries.isEmpty)
    }

    func testOpenWeatherAloneWhenTheProviderSaysSo() async {
        var policy = CitySearchPolicy.standard
        policy.provider = .openWeather
        openWeather.onSearch = { _ in [geocodingResult(name: "Nashville", state: "Tennessee")] }

        _ = await repository.searchCities(query: "Nashville", policy: policy)

        XCTAssertTrue(openMeteo.searches.isEmpty)
        XCTAssertEqual(openWeather.queries, ["Nashville"])
    }

    func testPostcodesSearchNothingAndZipsOnlyOpenMeteo() async {
        openMeteo.onSearch = { _ in throw URLError(.timedOut) }

        let postcode = try! await repository.searchCities(query: "SW1A 1AA").get()
        let zip = try! await repository.searchCities(query: "90210").get()

        XCTAssertTrue(postcode.isEmpty)
        XCTAssertTrue(zip.isEmpty)
        XCTAssertEqual(openMeteo.searches.map(\.name), ["90210"])
        XCTAssertTrue(openWeather.queries.isEmpty, "OpenWeather's search doesn't take postcodes")
    }

    func testBothFailingIsAFailure() async {
        openMeteo.onSearch = { _ in throw URLError(.notConnectedToInternet) }
        openWeather.onSearch = { _ in throw URLError(.notConnectedToInternet) }

        let result = await repository.searchCities(query: "Paris")

        XCTAssertNil(try? result.get())
    }
}
