import Foundation
import Observation

@MainActor
@Observable
final class CityListViewModel {
    private(set) var locations: [SavedLocation] = []
    private(set) var activeIndex = 0

    var activeLocation: SavedLocation? {
        locations.indices.contains(activeIndex) ? locations[activeIndex] : nil
    }

    private let preferences: PreferencesStore
    private let geocodingRepository: GeocodingRepository
    private let onCityAdded: @MainActor (CityAdded) -> Void
    /// Remote Config's search settings, for looking up name-only locations as search would.
    private let readPolicy: @MainActor () -> CitySearchPolicy

    init(
        preferences: PreferencesStore? = nil,
        geocodingRepository: GeocodingRepository? = nil,
        onCityAdded: (@MainActor (CityAdded) -> Void)? = nil,
        readPolicy: (@MainActor () -> CitySearchPolicy)? = nil
    ) {
        self.preferences = preferences ?? .shared
        self.geocodingRepository = geocodingRepository ?? .live
        self.onCityAdded = onCityAdded ?? { AnalyticsRepository.shared.logCityAdded($0) }
        self.readPolicy = readPolicy ?? { RemoteConfigRepository.shared.citySearchPolicy }
        loadFromPreferences()
        fillInMissingCoordinates()
    }

    /// `added` says how, for `city_added`; without it, My Location counts as `my_location` and
    /// anything else as a typed name, with the provider search would use.
    func addLocation(_ location: SavedLocation, added: CityAdded? = nil) {
        if let existingIndex = locations.firstIndex(where: { $0.label == location.label }) {
            setActiveIndex(existingIndex)
            return
        }

        // Append before any await so the city shows up at once (even offline) and a second add of
        // the same label hits the duplicate check above.
        let updated = locations + [location]
        let newIndex = updated.count - 1
        locations = updated
        activeIndex = newIndex
        onCityAdded(added ?? CityAdded(
            source: location.isCurrentLocation ? .myLocation : .typedName,
            provider: readPolicy().provider
        ))
        preferences.setSavedLocations(updated)
        preferences.setActiveLocationIndex(newIndex)

        fillInMissingCoordinates()
    }

    /// Labels being geocoded now, so launch and a quick return to the app don't look one up twice.
    private var geocodingLabels: Set<String> = []

    /// Geocodes every name-only city. Runs on launch and whenever the app comes back as well as on
    /// add, so a city whose lookup failed (offline, say) still gets its radar later.
    func fillInMissingCoordinates() {
        for location in locations where location.latitude == nil || location.longitude == nil {
            let label = location.label
            guard geocodingLabels.insert(label).inserted else { continue }
            Task {
                await fillInCoordinates(forLabel: label)
                geocodingLabels.remove(label)
            }
        }
    }

    /// Geocodes a name-only entry so it gets a radar and an unambiguous forecast, the way Add would
    /// with nothing tapped (SEARCH.md, "Add with nothing picked"): the same search, filtering and
    /// sorting, then the first row named as the entry is, unless one far bigger sits above it. No
    /// such row leaves it name-only, on the forecast by name. The entered label is kept so the
    /// duplicate check in `addLocation` still matches it.
    private func fillInCoordinates(forLabel label: String) async {
        let policy = readPolicy()
        let rows = await geocodingRepository.searchCities(
            query: label,
            policy: policy,
            origin: CitySearchOrigin.current(savedLocations: locations)
        ).getOrNil() ?? []
        guard let geocoded = AddLocationRules.typedMatch(label, in: rows, sizeRatio: policy.sizeRatio),
              // The list may have changed while geocoding was in flight.
              let index = locations.firstIndex(where: { $0.label == label && $0.latitude == nil })
        else { return }

        var updated = locations
        updated[index] = SavedLocation(
            label: label,
            latitude: geocoded.weatherLat,
            longitude: geocoded.weatherLon,
            isCurrentLocation: updated[index].isCurrentLocation
        )
        locations = updated
        preferences.setSavedLocations(updated)
    }

    /// Moves My Location to where the device is now, after a real move (`withMyLocation`).
    /// True when My Location moved.
    @discardableResult
    func updateCurrentLocation(_ location: SavedLocation) -> Bool {
        guard let latitude = location.latitude, let longitude = location.longitude,
              let updated = locations.withMyLocation(atLatitude: latitude, longitude: longitude) else { return false }
        locations = updated
        preferences.setSavedLocations(updated)
        return true
    }

    /// Takes up My Location's position as stored, where Follow my location (and the background
    /// refresh) moves it, so a move made while the app is open shows at once. Same as Android's
    /// `followStoredMyLocation`.
    func followStoredMyLocation() {
        guard let stored = preferences.savedLocations.first(where: \.isCurrentLocation),
              let index = locations.firstIndex(where: \.isCurrentLocation),
              locations[index] != stored else { return }
        var updated = locations
        updated[index] = stored
        locations = updated
    }

    /// Checking whether My Location has moved happens at most this often, so switching in and out of
    /// the app doesn't fetch the position each time. Adding My Location always fetches.
    static let myLocationCheckInterval: TimeInterval = 15 * 60
    private var myLocationCheckedAt: Date?

    /// Whether it's time to check whether My Location has moved, and if so, notes the time.
    func claimMyLocationCheck(now: Date = Date()) -> Bool {
        if let last = myLocationCheckedAt, now.timeIntervalSince(last) < Self.myLocationCheckInterval {
            return false
        }
        myLocationCheckedAt = now
        return true
    }

    /// A check made anyway (pull to refresh asks whatever the interval), so returning to the app
    /// straight after doesn't make another.
    func noteMyLocationChecked(now: Date = Date()) {
        myLocationCheckedAt = now
    }

    func removeLocation(at index: Int) {
        guard locations.indices.contains(index) else { return }
        var updated = locations
        updated.remove(at: index)
        let newIndex = min(activeIndex, max(updated.count - 1, 0))
        locations = updated
        activeIndex = newIndex
        preferences.setSavedLocations(updated)
        preferences.setActiveLocationIndex(newIndex)
    }

    func setActiveIndex(_ index: Int) {
        guard index != activeIndex, locations.indices.contains(index) else { return }
        activeIndex = index
        preferences.setActiveLocationIndex(index)
    }

    func reorderLocations(from source: IndexSet, to destination: Int) {
        guard let fromIndex = source.first else { return }
        reorderLocations(fromIndex: fromIndex, toIndex: destination)
    }

    func reorderLocations(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              locations.indices.contains(fromIndex),
              toIndex >= 0,
              toIndex <= locations.count else { return }

        var updated = locations
        let item = updated.remove(at: fromIndex)
        let adjustedDestination = toIndex > fromIndex ? toIndex - 1 : toIndex
        updated.insert(item, at: adjustedDestination)

        let newActiveIndex: Int
        if activeIndex == fromIndex {
            newActiveIndex = adjustedDestination
        } else if fromIndex < activeIndex && adjustedDestination >= activeIndex {
            newActiveIndex = activeIndex - 1
        } else if fromIndex > activeIndex && adjustedDestination <= activeIndex {
            newActiveIndex = activeIndex + 1
        } else {
            newActiveIndex = activeIndex
        }

        locations = updated
        activeIndex = newActiveIndex
        preferences.setSavedLocations(updated)
        preferences.setActiveLocationIndex(newActiveIndex)
    }

    private func loadFromPreferences() {
        var loaded = preferences.savedLocations
        if loaded.isEmpty, let lastCity = preferences.lastCity {
            loaded = [SavedLocation(label: lastCity, latitude: nil, longitude: nil)]
            preferences.setSavedLocations(loaded)
        }
        locations = loaded
        activeIndex = min(preferences.activeLocationIndex, max(loaded.count - 1, 0))
    }
}

private extension Result {
    func getOrNil() -> Success? {
        if case .success(let value) = self { return value }
        return nil
    }
}
