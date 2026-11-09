import CoreLocation
import Foundation

/// A city pinned by the user. Coordinates are nil for a name-only entry (typed without picking a
/// suggestion, or legacy migration) until `CityListViewModel` geocodes it.
struct SavedLocation: Codable, Equatable, Identifiable {
    var id: String { cacheKey }
    let label: String
    let latitude: Double?
    let longitude: Double?
    let isCurrentLocation: Bool

    var cacheKey: String {
        if let latitude, let longitude {
            return String(format: "%.4f,%.4f", latitude, longitude)
        }
        return label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The moon is lit from the other side down south, on screen and in a notification's picture.
    /// A name-only city counts as northern.
    var isSouthernHemisphere: Bool {
        (latitude ?? 0) < 0
    }

    init(
        label: String,
        latitude: Double?,
        longitude: Double?,
        isCurrentLocation: Bool = false
    ) {
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
        self.isCurrentLocation = isCurrentLocation
    }
}

extension Array where Element == SavedLocation {
    /// The city notifications are about: My Location when it's saved, otherwise the first city.
    /// Fixed on purpose, so looking at another city's tab doesn't move tomorrow's briefing there.
    var notificationLocation: SavedLocation? {
        notificationIndex.map { self[$0] }
    }

    /// Where `notificationLocation` is in the list, for marking it in Manage Locations.
    var notificationIndex: Int? {
        firstIndex(where: \.isCurrentLocation) ?? indices.first
    }

    /// The list with My Location moved to `latitude`, `longitude`. Nil when there's no My Location,
    /// or it has moved less than `SavedLocation.myLocationMoveMeters`: that's GPS wobble, and new
    /// coordinates would just miss the cache. Same as Android's `withMyLocationAt`.
    func withMyLocation(atLatitude latitude: Double, longitude: Double) -> [SavedLocation]? {
        guard let index = firstIndex(where: \.isCurrentLocation) else { return nil }
        let current = self[index]
        if let oldLatitude = current.latitude, let oldLongitude = current.longitude {
            let moved = CLLocation(latitude: oldLatitude, longitude: oldLongitude)
                .distance(from: CLLocation(latitude: latitude, longitude: longitude))
            guard moved >= SavedLocation.myLocationMoveMeters else { return nil }
        }
        var updated = self
        updated[index] = SavedLocation(
            label: current.label,
            latitude: latitude,
            longitude: longitude,
            isCurrentLocation: true
        )
        return updated
    }
}

extension SavedLocation {
    /// My Location's label, and its name in the hero when the phone can't name the place.
    static let myLocationLabel = "My Location"

    /// How far the device has to move before My Location follows it.
    static let myLocationMoveMeters: CLLocationDistance = 1_000
}
