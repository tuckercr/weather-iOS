import Foundation
import Observation

/// Locations and Add location: the saved cities, and adding, removing, reordering and picking them.
/// The cities themselves are kept by `CityRepository`, which the weather screen reads too.
@MainActor
@Observable
final class CityListViewModel {
    @ObservationIgnored private let cities: CityRepository

    init(cities: CityRepository? = nil) {
        self.cities = cities ?? CityRepository()
    }

    var locations: [SavedLocation] { cities.locations }

    func addLocation(_ location: SavedLocation, added: CityAdded? = nil) {
        cities.addLocation(location, added: added)
    }

    func removeLocation(at index: Int) {
        cities.removeLocation(at: index)
    }

    func setActiveIndex(_ index: Int) {
        cities.setActiveIndex(index)
    }

    func reorderLocations(from source: IndexSet, to destination: Int) {
        cities.reorderLocations(from: source, to: destination)
    }
}
