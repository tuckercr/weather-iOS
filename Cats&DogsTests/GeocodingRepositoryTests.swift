import XCTest
@testable import Cats_Dogs

@MainActor
final class GeocodingRepositoryTests: XCTestCase {
    func testSearchCitiesTrimsInputAndFormatsSuggestionLabels() async {
        let api = FakeGeocodingAPI(
            response: [
                GeocodingDirectDTO(name: "Austin", lat: 30.2672, lon: -97.7431, country: "US", state: "TX"),
                GeocodingDirectDTO(name: "London", lat: 51.5072, lon: -0.1276, country: "GB", state: ""),
            ]
        )
        let repository = GeocodingRepository(client: api)

        let result = await repository.searchCities(query: "  Austin  ")
        let suggestions = try! result.get()

        XCTAssertEqual(api.lastQuery, "Austin")
        XCTAssertEqual(api.lastLimit, 8)
        XCTAssertEqual(suggestions.count, 2)
        XCTAssertEqual(suggestions.first?.label, "Austin, TX, US")
        XCTAssertEqual(suggestions.first?.weatherLat ?? 0, 30.2672, accuracy: 0.0001)
        XCTAssertEqual(suggestions.first?.weatherLon ?? 0, -97.7431, accuracy: 0.0001)
        XCTAssertEqual(suggestions.last?.label, "London, GB")
    }

    func testAPlaceListedTwiceIsSuggestedOnceAtItsFirstMatch() async {
        let api = FakeGeocodingAPI(
            response: [
                GeocodingDirectDTO(name: "Amsterdam", lat: 52.3728, lon: 4.8936, country: "NL", state: "North Holland"),
                GeocodingDirectDTO(name: "Amsterdam", lat: 52.3676, lon: 4.9041, country: "NL", state: "North Holland"),
                GeocodingDirectDTO(name: "Amsterdam", lat: 42.9387, lon: -74.1882, country: "US", state: "New York"),
            ]
        )

        let suggestions = try! await GeocodingRepository(client: api).searchCities(query: "Amsterdam").get()

        XCTAssertEqual(suggestions.map(\.label), ["Amsterdam, North Holland, NL", "Amsterdam, New York, US"])
        XCTAssertEqual(suggestions.first?.weatherLon ?? 0, 4.8936, accuracy: 0.0001)
    }

    func testSearchCitiesReturnsEmptyResultForShortQueryWithoutCallingAPI() async {
        let api = FakeGeocodingAPI()
        let repository = GeocodingRepository(client: api)

        let result = await repository.searchCities(query: " a ")
        let suggestions = try! result.get()

        XCTAssertTrue(suggestions.isEmpty)
        XCTAssertEqual(api.callCount, 0)
    }

    func testSearchCitiesWithMissingApiKeyFailsBeforeCallingAPI() async {
        let api = FakeGeocodingAPI()
        let repository = GeocodingRepository(client: GeocodingClient(apiKey: "   "))

        let result = await repository.searchCities(query: "Austin")

        guard case .failure(let error as OpenWeatherClientError) = result else {
            return XCTFail("Expected missingApiKey failure")
        }
        XCTAssertEqual(error, .missingApiKey)
        XCTAssertEqual(api.callCount, 0)
    }

    func testSearchCitiesWrapsAPIFailures() async {
        struct BackendDown: Error {}
        let api = FakeGeocodingAPI(error: BackendDown())
        let repository = GeocodingRepository(client: api)

        let result = await repository.searchCities(query: "Austin")

        guard case .failure(let error as BackendDown) = result else {
            return XCTFail("Expected backend failure")
        }
        XCTAssertNotNil(error)
        XCTAssertEqual(api.callCount, 1)
    }
}

private final class FakeGeocodingAPI: GeocodingAPI, @unchecked Sendable {
    var callCount = 0
    var lastQuery: String?
    var lastLimit: Int?

    private let response: [GeocodingDirectDTO]
    private let error: Error?

    init(response: [GeocodingDirectDTO] = [], error: Error? = nil) {
        self.response = response
        self.error = error
    }

    func directSearch(query: String, limit: Int) async throws -> [GeocodingDirectDTO] {
        callCount += 1
        lastQuery = query
        lastLimit = limit
        if let error { throw error }
        return response
    }
}
