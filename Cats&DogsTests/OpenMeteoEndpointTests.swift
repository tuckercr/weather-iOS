import XCTest
@testable import Cats_Dogs

final class OpenMeteoEndpointTests: XCTestCase {
    private let forecast = URL(string: "https://api.open-meteo.com/v1/forecast")!
    private let query = [URLQueryItem(name: "latitude", value: "51.5")]

    func testWithAKeyRequestsGoToTheCustomerServersWithTheKey() {
        let url = OpenMeteoEndpoint.url(forecast, apiKey: "abc", query: query)
        XCTAssertEqual(url.absoluteString, "https://customer-api.open-meteo.com/v1/forecast?latitude=51.5&apikey=abc")
    }

    func testEachApiKeepsItsOwnHostOnTheCustomerServers() {
        let airQuality = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        let search = URL(string: "https://geocoding-api.open-meteo.com/v1/search")!
        XCTAssertEqual(OpenMeteoEndpoint.url(airQuality, apiKey: "abc", query: []).host, "customer-air-quality-api.open-meteo.com")
        XCTAssertEqual(OpenMeteoEndpoint.url(search, apiKey: "abc", query: []).host, "customer-geocoding-api.open-meteo.com")
    }

    func testWithoutAKeyRequestsGoToTheFreeServers() {
        let url = OpenMeteoEndpoint.url(forecast, apiKey: "", query: query)
        XCTAssertEqual(url.absoluteString, "https://api.open-meteo.com/v1/forecast?latitude=51.5")
    }
}
