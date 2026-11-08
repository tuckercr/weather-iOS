import Foundation
import Observation

@MainActor
@Observable
final class GeoLocationViewModel {
    var cityInput = ""
    private(set) var citySuggestions: [CitySuggestion] = []
    private(set) var citySuggestLoading = false
    /// The last search failed (offline, say), as opposed to finding nothing, so Add location can
    /// save the typed name instead. Cleared when the text changes.
    private(set) var searchFailed = false

    /// Where sorting measures from: the phone's region and My Location. Set by `open(savedLocations:)`.
    var origin = CitySearchOrigin()
    /// The locations already saved, for Add location's rules.
    private(set) var savedLocations: [SavedLocation] = []

    private let geocodingRepository: GeocodingRepository
    /// Remote Config's search settings, read on every search.
    private let readPolicy: @MainActor () -> CitySearchPolicy
    private var suggestTask: Task<Void, Never>?

    init(
        geocodingRepository: GeocodingRepository? = nil,
        readPolicy: (@MainActor () -> CitySearchPolicy)? = nil
    ) {
        self.geocodingRepository = geocodingRepository ?? .live
        self.readPolicy = readPolicy ?? { RemoteConfigRepository.shared.citySearchPolicy }
    }

    /// The settings the next search uses, for the screen's own rules (Add's size check).
    var policy: CitySearchPolicy { readPolicy() }

    /// Add location opens: remembers what's saved, and sorts from the phone's region and My
    /// Location, both already on the phone.
    func open(savedLocations: [SavedLocation]) {
        self.savedLocations = savedLocations
        origin = CitySearchOrigin.current(savedLocations: savedLocations)
    }

    /// What Add location's button (and the keyboard's Search key) does with what's typed.
    var action: AddLocationAction {
        AddLocationRules.action(
            typed: cityInput,
            suggestions: citySuggestions,
            searching: citySuggestLoading,
            searchFailed: searchFailed,
            saved: savedLocations,
            sizeRatio: policy.sizeRatio
        )
    }

    /// The row the button would take, highlighted in the list.
    var target: CitySuggestion? {
        switch action {
        case .add(let suggestion), .goTo(let suggestion, _): suggestion
        default: nil
        }
    }

    /// My Location is saved already, so Add location doesn't offer it.
    var hasMyLocation: Bool { savedLocations.contains(where: \.isCurrentLocation) }

    /// Where `suggestion` is saved already, if it is.
    func savedIndex(of suggestion: CitySuggestion) -> Int? {
        AddLocationRules.savedIndex(of: suggestion, in: savedLocations)
    }

    /// What a choice on Add location comes to: a location to save, with the name to confirm it
    /// with ("Malmö added") and how it was added (for `city_added`), or a saved place to show.
    enum Choice: Equatable {
        case add(SavedLocation, name: String, CityAdded)
        case goTo(Int)
    }

    /// Tapping `suggestion`'s row: shows it if it's saved, otherwise adds it.
    func choose(_ suggestion: CitySuggestion) -> Choice {
        savedIndex(of: suggestion).map { .goTo($0) } ?? adding(suggestion, source: .suggestion)
    }

    /// The button or the keyboard's Search key; nil when there's nothing to do.
    func submit() -> Choice? {
        switch action {
        case .add(let suggestion):
            adding(suggestion, source: .typedMatch)
        case .goTo(_, let index):
            .goTo(index)
        case .addByName(let name):
            .add(SavedLocation(label: name, latitude: nil, longitude: nil), name: name, CityAdded(source: .typedName, provider: policy.provider))
        case .none, .pickFromList, .notFound:
            nil
        }
    }

    /// My Location, once its fix arrives.
    func addingMyLocation(_ location: SavedLocation) -> Choice {
        .add(location, name: location.label, CityAdded(source: .myLocation, provider: policy.provider))
    }

    /// Saved under its own label, or with its county when that label is taken.
    private func adding(_ suggestion: CitySuggestion, source: CityAddedSource) -> Choice {
        .add(
            SavedLocation(
                label: AddLocationRules.labelToSave(suggestion, saved: savedLocations),
                latitude: suggestion.weatherLat,
                longitude: suggestion.weatherLon
            ),
            name: suggestion.name,
            CityAdded(source: source, provider: suggestion.provider)
        )
    }

    func onCityInputChange(_ value: String) {
        cityInput = value
        searchFailed = false
        suggestTask?.cancel()

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= AddLocationRules.minSearchLength else {
            citySuggestions = []
            citySuggestLoading = false
            return
        }

        let policy = readPolicy()
        let origin = origin
        suggestTask = Task {
            citySuggestLoading = true
            try? await Task.sleep(for: .milliseconds(policy.delayMilliseconds))
            guard !Task.isCancelled, cityInput.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                citySuggestLoading = false
                return
            }

            let result = await geocodingRepository.searchCities(query: trimmed, policy: policy, origin: origin)
            guard !Task.isCancelled, cityInput.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                citySuggestLoading = false
                return
            }

            citySuggestLoading = false
            citySuggestions = (try? result.get()) ?? []
            if case .failure = result { searchFailed = true }
        }
    }
}
