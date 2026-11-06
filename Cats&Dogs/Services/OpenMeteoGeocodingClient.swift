import Foundation

protocol OpenMeteoGeocodingAPI: Sendable {
    func search(name: String, count: Int) async throws -> [OpenMeteoPlaceDTO]
}

/// Open-Meteo's geocoding search: prefix matching from 3 letters, up to 100 rows, with populations.
/// Free and keyless for non-commercial use; data from GeoNames, credited in Settings.
struct OpenMeteoGeocodingClient: OpenMeteoGeocodingAPI {
    private let session: URLSession
    private static let baseURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(name: String, count: Int) async throws -> [OpenMeteoPlaceDTO] {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: String(count)),
            // English names and states, so labels read as they do from OpenWeather.
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: components.url!)
        } catch {
            throw OpenWeatherClientError.network
        }
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw OpenWeatherClientError.invalidPayload
        }
        do {
            // No `results` at all when nothing matches.
            return try JSONDecoder().decode(OpenMeteoSearchResponse.self, from: data).results ?? []
        } catch {
            throw OpenWeatherClientError.invalidPayload
        }
    }
}

struct OpenMeteoSearchResponse: Decodable {
    let results: [OpenMeteoPlaceDTO]?
}

struct OpenMeteoPlaceDTO: Decodable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    let featureCode: String?
    let countryCode: String?
    let country: String?
    let admin1: String?
    let admin2: String?
    let population: Int?

    enum CodingKeys: String, CodingKey {
        case name, latitude, longitude, country, admin1, admin2, population
        case featureCode = "feature_code"
        case countryCode = "country_code"
    }
}
