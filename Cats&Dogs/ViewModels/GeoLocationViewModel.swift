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

    /// Where sorting measures from: the phone's region and My Location. Set by the screen.
    var origin = CitySearchOrigin()

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
