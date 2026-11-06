import Foundation

/// A row from the geocoder shown while searching; `weatherLat`/`weatherLon` are used for the
/// forecasts when the user picks it. `label` is what's saved ("Malmö, Skåne County, SE"); the Add
/// location screen shows `name` above `detail`.
struct CitySuggestion: Equatable, Identifiable {
    var id: String { label }
    let label: String
    let weatherLat: Double
    let weatherLon: Double
    /// The place's own name ("Malmö"): the start of `label`.
    let name: String
    /// Its ISO country code ("SE"): the end of `label`.
    let countryCode: String
    /// People living there, when the provider says. OpenWeather never does.
    let population: Int?

    init(
        label: String,
        weatherLat: Double,
        weatherLon: Double,
        name: String? = nil,
        countryCode: String? = nil,
        population: Int? = nil
    ) {
        self.label = label
        self.weatherLat = weatherLat
        self.weatherLon = weatherLon
        let parts = label.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        self.name = name ?? parts.first ?? label
        self.countryCode = countryCode ?? (parts.count > 1 ? parts.last ?? "" : "")
        self.population = population
    }

    /// The rest of `label` after the name: "Skåne County, SE".
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
