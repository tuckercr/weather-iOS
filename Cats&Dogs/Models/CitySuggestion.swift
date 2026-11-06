import Foundation

/// A row from the geocoder shown while searching; `weatherLat`/`weatherLon` are used for the
/// forecasts when the user picks it. `label` is what's saved ("Malmö, Skåne, SE"); the Add location
/// screen shows `name` above `detail`.
struct CitySuggestion: Equatable, Identifiable {
    /// Two places can share a label (on the OpenWeather fallback, which has no county), so the
    /// coordinates keep rows apart.
    var id: String { "\(label)|\(weatherLat),\(weatherLon)" }
    let label: String
    let weatherLat: Double
    let weatherLon: Double
    /// The place's own name ("Malmö"): the start of `label`.
    let name: String
    /// Its ISO country code ("SE"): the end of `label`.
    let countryCode: String
    /// People living there, when the provider says. OpenWeather never does.
    let population: Int?
    /// State or region ("Tennessee"), county ("Davidson") and country name ("United States"), when
    /// the provider says: for matching what's typed after a comma and telling same-label places
    /// apart.
    let admin1: String?
    let admin2: String?
    let countryName: String?
    /// Open-Meteo's kind of place ("PPLA" for a state capital); nil from OpenWeather.
    let featureCode: String?
    let provider: CitySearchProvider

    init(
        label: String,
        weatherLat: Double,
        weatherLon: Double,
        name: String? = nil,
        countryCode: String? = nil,
        population: Int? = nil,
        admin1: String? = nil,
        admin2: String? = nil,
        countryName: String? = nil,
        featureCode: String? = nil,
        provider: CitySearchProvider = .openWeather
    ) {
        self.label = label
        self.weatherLat = weatherLat
        self.weatherLon = weatherLon
        let parts = label.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        self.name = name ?? parts.first ?? label
        self.countryCode = countryCode ?? (parts.count > 1 ? parts.last ?? "" : "")
        self.population = population
        self.admin1 = admin1
        self.admin2 = admin2
        self.countryName = countryName
        self.featureCode = featureCode
        self.provider = provider
    }

    /// The same place with a label made of `parts`, the blank ones left out.
    func relabelled(_ parts: [String?]) -> CitySuggestion {
        CitySuggestion(
            label: parts.compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", "),
            weatherLat: weatherLat,
            weatherLon: weatherLon,
            name: name,
            countryCode: countryCode,
            population: population,
            admin1: admin1,
            admin2: admin2,
            countryName: countryName,
            featureCode: featureCode,
            provider: provider
        )
    }

    /// The rest of `label` after the name: "Skåne, SE".
    var detail: String {
        var rest = label.hasPrefix(name) ? label.dropFirst(name.count) : Substring(label)
        if rest.hasPrefix(",") { rest = rest.dropFirst() }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// The name and country, for the Add location button: "Malmö, SE".
    var shortLabel: String {
        countryCode.isEmpty ? name : "\(name), \(countryCode)"
    }
}
