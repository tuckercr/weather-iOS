import CoreLocation
import Foundation

/// Where search suggestions come from (Remote Config `city_search_provider`).
enum CitySearchProvider: String, Sendable {
    /// Prefix search ("Nashv" finds Nashville), with populations for sorting.
    case openMeteo = "open_meteo"
    /// Whole-name search, at most 5 rows: the fallback when Open-Meteo fails or is switched off.
    case openWeather = "openweather"
}

/// How search behaves, from Remote Config (`city_search_*`, SEARCH.md "Remote Config design"),
/// read on every search.
struct CitySearchPolicy: Equatable, Sendable {
    var provider: CitySearchProvider = .openMeteo
    /// Most suggestions shown.
    var results = 8
    /// Suggestions in the phone's country go first.
    var countryFirst = true
    /// Places with the same name are listed nearest My Location first.
    var nearestFirst = true
    /// Neither rule can lift a place past one this many times its population; 0 turns that off. The
    /// same ratio limits which row Add takes with nothing tapped.
    var sizeRatio = 20
    /// Wait after the last keystroke before searching.
    var delayMilliseconds = 280

    static let standard = CitySearchPolicy()
}

/// What sorting knows about the user, all already on the phone: nothing is read or sent for it.
struct CitySearchOrigin: Equatable, Sendable {
    /// The phone's region ("US"), for country-first.
    var region: String?
    /// My Location's coordinates when it's saved, for nearest-first.
    var myLocation: CLLocationCoordinate2D?

    static func == (lhs: CitySearchOrigin, rhs: CitySearchOrigin) -> Bool {
        lhs.region == rhs.region
            && lhs.myLocation?.latitude == rhs.myLocation?.latitude
            && lhs.myLocation?.longitude == rhs.myLocation?.longitude
    }

    /// The phone's region, and My Location from the saved list.
    static func current(savedLocations: [SavedLocation]) -> CitySearchOrigin {
        let myLocation = savedLocations.first(where: \.isCurrentLocation).flatMap { location -> CLLocationCoordinate2D? in
            guard let latitude = location.latitude, let longitude = location.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        return CitySearchOrigin(region: Locale.current.region?.identifier, myLocation: myLocation)
    }
}

/// What was typed, read the way SEARCH.md's "Postcodes" and "Copy" say.
enum CitySearchQuery: Equatable {
    /// Too short to search, or a postcode other than a US ZIP: search nothing.
    case nothing
    /// Five digits: searched as usual, keeping only US rows.
    case zip(String)
    /// A name ("Richmond"), with whatever came after commas ("North Yorkshire"), matched on the phone.
    case name(String, qualifiers: [String])

    static func parse(_ text: String) -> CitySearchQuery {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let name = parts.first ?? ""
        guard name.count >= AddLocationRules.minSearchLength else { return .nothing }
        if name.count == 5, name.allSatisfy(\.isASCIIDigit) { return .zip(name) }
        if looksLikePostcode(name) { return .nothing }
        return .name(name, qualifiers: parts.dropFirst().filter { !$0.isEmpty })
    }

    /// A word mixing letters and digits (E14, SW1A 1AA, K1A 0B1), unless it's an ordinal (10th), or
    /// only digits, spaces and hyphens (90210-1234). Real towns keep a number as a word of its own
    /// (100 Mile House, 23 August), so those still search.
    static func looksLikePostcode(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        let mixed = words.contains { word in
            word.contains(where: \.isLetter) && word.contains(where: \.isNumber) && !isOrdinal(word)
        }
        if mixed { return true }
        return text.contains(where: \.isNumber) && text.allSatisfy { $0.isNumber || $0 == "-" || $0.isWhitespace }
    }

    private static func isOrdinal(_ word: Substring) -> Bool {
        let digits = word.prefix(while: \.isNumber)
        let suffix = word.dropFirst(digits.count).lowercased()
        return !digits.isEmpty && ["st", "nd", "rd", "th"].contains(suffix)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

/// Filtering, labels, sorting and trimming, as SEARCH.md "Behaviour", "Filtering" and "Labels" say.
/// Pure, so each rule is tested without the network.
enum CitySearchRanking {
    /// Two rows closer than this are the same place.
    static let samePlaceMeters: CLLocationDistance = 2_000

    /// Open-Meteo's place kinds that aren't wanted: historical, abandoned and destroyed.
    private static let unwantedFeatureCodes: Set<String> = ["PPLH", "PPLQ", "PPLW"]

    static func rank(
        _ rows: [CitySuggestion],
        query: CitySearchQuery,
        provider: CitySearchProvider,
        policy: CitySearchPolicy,
        origin: CitySearchOrigin
    ) -> [CitySuggestion] {
        var rows = rows
        if provider == .openMeteo {
            rows = rows.filter { isPopulatedPlace($0) }
            switch query {
            case .zip: rows = rows.filter { $0.countryCode.uppercased() == "US" }
            case let .name(_, qualifiers): rows = rows.filter { matches($0, qualifiers: qualifiers) }
            case .nothing: rows = []
            }
        }
        rows = mergingSamePlaces(rows)
        if provider == .openMeteo {
            rows = withCounties(rows)
            rows = sorted(rows, policy: policy, origin: origin)
        }
        return Array(rows.prefix(policy.results))
    }

    /// Populated places (`PPL…`), except historical, abandoned and destroyed ones. A row without a
    /// code (OpenWeather's) is kept.
    static func isPopulatedPlace(_ row: CitySuggestion) -> Bool {
        guard let code = row.featureCode else { return true }
        return code.hasPrefix("PPL") && !unwantedFeatureCodes.contains(code)
    }

    /// Every qualifier ("North Yorkshire", "TX", "France") starts a word of the row's state, county,
    /// country or country code, ignoring case and accents: "London" finds "Greater London".
    static func matches(_ row: CitySuggestion, qualifiers: [String]) -> Bool {
        var fields = [row.admin1, row.admin2, row.countryName, row.countryCode].compactMap { $0 }
        if row.countryCode.uppercased() == "US", let admin1 = row.admin1, let code = USStates.code(forName: admin1) {
            fields.append(code)
        }
        let folded = fields.map { AddLocationRules.fold($0) }
        return qualifiers.allSatisfy { qualifier in
            let wanted = AddLocationRules.fold(qualifier)
            return folded.contains { field in field.hasPrefix(wanted) || field.contains(" " + wanted) }
        }
    }

    /// Keeps the first of rows with the same label within `samePlaceMeters`; labels that match but
    /// are farther apart are different places (the two "Richmond, England, GB").
    static func mergingSamePlaces(_ rows: [CitySuggestion]) -> [CitySuggestion] {
        var kept: [CitySuggestion] = []
        for row in rows where !kept.contains(where: { $0.label == row.label && distance($0, row) < samePlaceMeters }) {
            kept.append(row)
        }
        return kept
    }

    /// Rows that would still read the same get their county: "Richmond, North Yorkshire, England, GB".
    static func withCounties(_ rows: [CitySuggestion]) -> [CitySuggestion] {
        let counts = Dictionary(rows.map { ($0.label, 1) }, uniquingKeysWith: +)
        return rows.map { row in
            guard counts[row.label, default: 0] > 1, let county = row.admin2, !county.isEmpty else { return row }
            return row.relabelled([row.name, county, row.admin1, row.countryCode])
        }
    }

    /// The provider's order, with rows in the phone's country lifted first and same-name places
    /// lifted nearest My Location first, but never past a row `sizeRatio` times their population.
    static func sorted(_ rows: [CitySuggestion], policy: CitySearchPolicy, origin: CitySearchOrigin) -> [CitySuggestion] {
        guard rows.count > 1 else { return rows }
        var target = Array(rows.indices)
        if policy.countryFirst, let region = origin.region?.uppercased() {
            let home = target.filter { rows[$0].countryCode.uppercased() == region }
            target = home + target.filter { rows[$0].countryCode.uppercased() != region }
        }
        if policy.nearestFirst, let here = origin.myLocation {
            let hereLocation = CLLocation(latitude: here.latitude, longitude: here.longitude)
            func distance(_ index: Int) -> CLLocationDistance {
                CLLocation(latitude: rows[index].weatherLat, longitude: rows[index].weatherLon).distance(from: hereLocation)
            }
            var placed = Set<Int>()
            var regrouped: [Int] = []
            // Each name's rows move together to where its first one was, nearest first.
            for index in target where !placed.contains(index) {
                let name = AddLocationRules.fold(rows[index].name)
                let group = target.filter { AddLocationRules.fold(rows[$0].name) == name }
                let nearestFirst = group.enumerated().sorted { a, b in
                    let (da, db) = (distance(a.element), distance(b.element))
                    return da == db ? a.offset < b.offset : da < db
                }.map(\.element)
                regrouped += nearestFirst
                placed.formUnion(group)
            }
            target = regrouped
        }
        // Move rows towards that order one place at a time, each only past rows it may pass.
        let wanted = Dictionary(uniqueKeysWithValues: target.enumerated().map { ($1, $0) })
        var order = Array(rows.indices)
        var moved = true
        while moved {
            moved = false
            for position in 1 ..< order.count {
                let (row, above) = (order[position], order[position - 1])
                if wanted[row]! < wanted[above]!,
                   AddLocationRules.canPass(rows[row], above: rows[above], sizeRatio: policy.sizeRatio) {
                    order.swapAt(position, position - 1)
                    moved = true
                }
            }
        }
        return order.map { rows[$0] }
    }

    private static func distance(_ a: CitySuggestion, _ b: CitySuggestion) -> CLLocationDistance {
        CLLocation(latitude: a.weatherLat, longitude: a.weatherLon)
            .distance(from: CLLocation(latitude: b.weatherLat, longitude: b.weatherLon))
    }
}

/// US state and territory postal codes, so "Paris, TX" finds Paris, Texas: Open-Meteo gives the
/// state's name only.
enum USStates {
    static func code(forName name: String) -> String? {
        codes[AddLocationRules.fold(name)]
    }

    private static let codes: [String: String] = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR", "california": "CA",
        "colorado": "CO", "connecticut": "CT", "delaware": "DE", "district of columbia": "DC",
        "washington, d.c.": "DC", "florida": "FL", "georgia": "GA", "hawaii": "HI", "idaho": "ID",
        "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS", "kentucky": "KY",
        "louisiana": "LA", "maine": "ME", "maryland": "MD", "massachusetts": "MA", "michigan": "MI",
        "minnesota": "MN", "mississippi": "MS", "missouri": "MO", "montana": "MT", "nebraska": "NE",
        "nevada": "NV", "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM", "new york": "NY",
        "north carolina": "NC", "north dakota": "ND", "ohio": "OH", "oklahoma": "OK", "oregon": "OR",
        "pennsylvania": "PA", "rhode island": "RI", "south carolina": "SC", "south dakota": "SD",
        "tennessee": "TN", "texas": "TX", "utah": "UT", "vermont": "VT", "virginia": "VA",
        "washington": "WA", "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY",
        "puerto rico": "PR", "guam": "GU", "u.s. virgin islands": "VI",
    ]
}

/// How a location was added, for `city_added`'s `source` parameter (SEARCH.md "Analytics").
enum CityAddedSource: String, Sendable {
    /// A row was tapped.
    case suggestion
    /// Add took the row named what was typed.
    case typedMatch = "typed_match"
    /// Saved by name with no list (offline, say).
    case typedName = "typed_name"
    case myLocation = "my_location"
}

/// `city_added`'s parameters: anonymous categories, never which place.
struct CityAdded: Equatable, Sendable {
    let source: CityAddedSource
    /// The provider of the row added; for a typed name or My Location, the one the search would use.
    let provider: CitySearchProvider
}
