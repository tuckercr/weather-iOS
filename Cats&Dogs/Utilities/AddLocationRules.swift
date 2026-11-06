import CoreLocation
import Foundation

/// What the Add location screen's button does, from what's typed and what the search found. The
/// rules are SEARCH.md's "Add with nothing picked" and "Already saved". Same rules as Android's
/// `model/AddLocationRules.kt`.
enum AddLocationAction: Equatable {
    /// Nothing typed yet, or the first search still running: no button.
    case none
    /// Adds the row that matches what was typed: "Add Malmö, SE".
    case add(CitySuggestion)
    /// The matching row is already saved, at `index`: "Go to London, GB".
    case goTo(CitySuggestion, index: Int)
    /// No list because the search failed (offline, say): saves the typed name, looked up later.
    case addByName(String)
    /// A list with no row Add can take: "Pick a town or city from the list".
    case pickFromList
    /// The search found nothing.
    case notFound
}

enum AddLocationRules {
    /// The shortest text that's searched, as in `GeoLocationViewModel`.
    static let minSearchLength = 2
    /// Add with nothing tapped can't take a row past one this many times its population: Remote
    /// Config `city_search_size_ratio`'s default.
    static let sizeRatio = CitySearchPolicy.standard.sizeRatio
    /// Two places closer than this are the same place (SEARCH.md, "Already saved").
    static let samePlaceMeters: CLLocationDistance = 2_000

    static func action(
        typed: String,
        suggestions: [CitySuggestion],
        searching: Bool,
        searchFailed: Bool,
        saved: [SavedLocation],
        sizeRatio: Int = AddLocationRules.sizeRatio
    ) -> AddLocationAction {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= minSearchLength else { return .none }
        if suggestions.isEmpty {
            if searching { return .none }
            return searchFailed ? .addByName(query) : .notFound
        }
        guard let match = typedMatch(query, in: suggestions, sizeRatio: sizeRatio) else { return .pickFromList }
        if let index = savedIndex(of: match, in: saved) { return .goTo(match, index: index) }
        return .add(match)
    }

    /// The first row whose name is what was typed, ignoring case, accents and anything after a comma,
    /// unless a row above it has at least `sizeRatio` times its population: "Nas" never adds Nås,
    /// Sweden (205 people) from under Nashik. As with the size guard, a row with no population can't
    /// be taken past one that has one, a row with no population blocks nothing, and 0 turns it off.
    static func typedMatch(
        _ typed: String,
        in suggestions: [CitySuggestion],
        sizeRatio: Int = AddLocationRules.sizeRatio
    ) -> CitySuggestion? {
        let name = fold(beforeComma(typed))
        guard !name.isEmpty,
              let index = suggestions.firstIndex(where: { fold($0.name.trimmingCharacters(in: .whitespaces)) == name })
        else { return nil }
        let match = suggestions[index]
        let passesAll = suggestions[..<index].allSatisfy { canPass(match, above: $0, sizeRatio: sizeRatio) }
        return passesAll ? match : nil
    }

    /// Whether `row` may be put above `above`: the size guard, shared with `CitySearchRanking`.
    static func canPass(_ row: CitySuggestion, above: CitySuggestion, sizeRatio: Int) -> Bool {
        guard sizeRatio > 0, let abovePopulation = above.population else { return true }
        guard let population = row.population else { return false }
        return abovePopulation < sizeRatio * population
    }

    /// Where `suggestion` already is in the saved list: within `samePlaceMeters` (labels miss the same
    /// place spelt two ways, and two places can share one: "Richmond, England, GB" is in London and in
    /// North Yorkshire), or, for a name-only location, which has no coordinates, the same label. My
    /// Location is left out: it moves, and saving the town you're in as its own location is
    /// reasonable.
    static func savedIndex(of suggestion: CitySuggestion, in saved: [SavedLocation]) -> Int? {
        let place = CLLocation(latitude: suggestion.weatherLat, longitude: suggestion.weatherLon)
        return saved.firstIndex { location in
            if location.isCurrentLocation { return false }
            guard let latitude = location.latitude, let longitude = location.longitude else {
                return location.label == suggestion.label
            }
            return CLLocation(latitude: latitude, longitude: longitude).distance(from: place) < samePlaceMeters
        }
    }

    /// The label to save `suggestion` under: its own, or with its county when a different saved place
    /// already has that label, so the two read differently and the list's de-duplication by label
    /// doesn't take one for the other.
    static func labelToSave(_ suggestion: CitySuggestion, saved: [SavedLocation]) -> String {
        guard saved.contains(where: { !$0.isCurrentLocation && $0.label == suggestion.label }),
              let county = suggestion.admin2, !county.isEmpty else { return suggestion.label }
        return suggestion.relabelled([suggestion.name, county, suggestion.admin1, suggestion.countryCode]).label
    }

    /// How many characters at the start of `name` the typed text covers, accents ignored ("Nas" in
    /// "Nåshult" is 3), for showing them in bold; 0 when the name doesn't start with it.
    static func matchedPrefixLength(name: String, typed: String) -> Int {
        let query = fold(beforeComma(typed))
        guard !query.isEmpty else { return 0 }
        var folded = ""
        for (index, character) in name.enumerated() {
            folded += fold(String(character))
            if !query.hasPrefix(folded) && !folded.hasPrefix(query) { return 0 }
            if folded.count >= query.count { return folded.hasPrefix(query) ? index + 1 : 0 }
        }
        return 0
    }

    /// Lower case without accents, so "Malmo" finds Malmö and nobody has to type them.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func beforeComma(_ text: String) -> String {
        String(text.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
