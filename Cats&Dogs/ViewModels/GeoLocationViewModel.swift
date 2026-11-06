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

    private let geocodingRepository: GeocodingRepository
    private var suggestTask: Task<Void, Never>?

    init(geocodingRepository: GeocodingRepository? = nil) {
        self.geocodingRepository = geocodingRepository ?? GeocodingRepository()
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

        suggestTask = Task {
            citySuggestLoading = true
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, cityInput.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                citySuggestLoading = false
                return
            }

            let result = await geocodingRepository.searchCities(query: trimmed)
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
