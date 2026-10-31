import Foundation

struct GeocodingRepository {
    private let client: any GeocodingAPI

    init(client: any GeocodingAPI = GeocodingClient()) {
        self.client = client
    }

    func searchCities(query: String) async -> Result<[CitySuggestion], Error> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return .success([]) }

        do {
            let results = try await client.directSearch(query: trimmed, limit: 8)
            // The geocoder can list a place twice a few metres apart ("Amsterdam, North Holland, NL"),
            // which looks broken and gives the list two rows with one id. The first is its best match.
            var seen = Set<String>()
            return .success(results.map(mapSuggestion).filter { seen.insert($0.label).inserted })
        } catch {
            return .failure(error)
        }
    }

    private func mapSuggestion(_ dto: GeocodingDirectDTO) -> CitySuggestion {
        let labelParts = [dto.name, dto.state?.nilIfEmpty, dto.country].compactMap { $0 }
        return CitySuggestion(
            label: labelParts.joined(separator: ", "),
            weatherLat: dto.lat,
            weatherLon: dto.lon
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
