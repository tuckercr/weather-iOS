import Foundation

/// Town and city search, as SEARCH.md describes: Open-Meteo's prefix search, falling back to
/// OpenWeather's whole-name search when it fails, then filtered, labelled and sorted on the phone
/// (`CitySearchRanking`).
struct GeocodingRepository {
    private let client: any GeocodingAPI
    /// Nil searches OpenWeather only, as if Open-Meteo were switched off.
    private let openMeteo: (any OpenMeteoGeocodingAPI)?

    /// Rows asked of Open-Meteo, so filtering and sorting have room before trimming.
    static let openMeteoCount = 20
    /// With text after a comma, which is matched on the phone, the most Open-Meteo gives: "Richmond,
    /// North Yorkshire" is the 22nd Richmond.
    static let openMeteoQualifiedCount = 100
    /// OpenWeather's maximum, whatever `limit` asks for.
    static let openWeatherLimit = 5

    init(client: any GeocodingAPI = GeocodingClient(), openMeteo: (any OpenMeteoGeocodingAPI)? = nil) {
        self.client = client
        self.openMeteo = openMeteo
    }

    /// Both providers, for the app.
    static var live: GeocodingRepository {
        GeocodingRepository(client: GeocodingClient(), openMeteo: OpenMeteoGeocodingClient())
    }

    func searchCities(
        query: String,
        policy: CitySearchPolicy = .standard,
        origin: CitySearchOrigin = CitySearchOrigin()
    ) async -> Result<[CitySuggestion], Error> {
        let parsed = CitySearchQuery.parse(query)
        let name: String
        var count = Self.openMeteoCount
        switch parsed {
        case .nothing: return .success([])
        case let .zip(zip): name = zip
        case let .name(typedName, qualifiers):
            name = typedName
            if !qualifiers.isEmpty { count = Self.openMeteoQualifiedCount }
        }

        if policy.provider == .openMeteo, let openMeteo {
            do {
                let places = try await openMeteo.search(name: name, count: count)
                let rows = places.map(Self.suggestion(from:))
                return .success(CitySearchRanking.rank(rows, query: parsed, provider: .openMeteo, policy: policy, origin: origin))
            } catch {
                // An empty answer is an answer; only a failure falls back.
            }
        }

        // OpenWeather's direct search doesn't take postcodes.
        if case .zip = parsed { return .success([]) }
        do {
            // The text as typed: OpenWeather reads "Springfield, IL, US" itself.
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let results = try await client.directSearch(query: trimmed, limit: Self.openWeatherLimit)
            let rows = results.map(Self.suggestion(from:))
            return .success(CitySearchRanking.rank(rows, query: parsed, provider: .openWeather, policy: policy, origin: origin))
        } catch {
            return .failure(error)
        }
    }

    /// "Nashville, Tennessee, US"; the county is added later only where two rows would read the same.
    static func suggestion(from place: OpenMeteoPlaceDTO) -> CitySuggestion {
        let countryCode = place.countryCode ?? ""
        return CitySuggestion(
            label: [place.name, place.admin1, countryCode].compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: ", "),
            weatherLat: place.latitude,
            weatherLon: place.longitude,
            name: place.name,
            countryCode: countryCode,
            population: place.population,
            admin1: place.admin1,
            admin2: place.admin2,
            countryName: place.country,
            featureCode: place.featureCode,
            provider: .openMeteo
        )
    }

    static func suggestion(from dto: GeocodingDirectDTO) -> CitySuggestion {
        let state = dto.state?.isEmpty == false ? dto.state : nil
        return CitySuggestion(
            label: [dto.name, state, dto.country].compactMap { $0 }.joined(separator: ", "),
            weatherLat: dto.lat,
            weatherLon: dto.lon,
            name: dto.name,
            countryCode: dto.country,
            admin1: state,
            provider: .openWeather
        )
    }
}
