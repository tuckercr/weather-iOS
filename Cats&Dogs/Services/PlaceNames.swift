import CoreLocation
import Foundation

/// Names My Location ("Knoxville") for the hero and notifications, which Open-Meteo's reading
/// doesn't. Same rules as Android's `PlaceNames.kt`.
protocol PlaceNaming: Sendable {
    func name(latitude: Double, longitude: Double) async -> String?
}

/// The phone's own reverse geocoding (Apple's here, Google's on Android). The last name is kept and
/// reused until My Location moves (`SavedLocation.myLocationMoveMeters`), as Apple asks: it limits
/// how often an app may look places up.
struct DevicePlaceNames: PlaceNaming {
    static let rememberedKey = "my_location_place_name"

    private let defaults: UserDefaults
    private let lookUp: @Sendable (Double, Double) async -> String?

    init(defaults: UserDefaults = .standard, lookUp: (@Sendable (Double, Double) async -> String?)? = nil) {
        self.defaults = defaults
        self.lookUp = lookUp ?? { latitude, longitude in await Self.geocode(latitude: latitude, longitude: longitude) }
    }

    /// Nil when the lookup finds nothing or fails (offline, or asked too often).
    func name(latitude: Double, longitude: Double) async -> String? {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        if let remembered = defaults.dictionary(forKey: Self.rememberedKey),
           let name = remembered["name"] as? String,
           let rememberedLatitude = remembered["latitude"] as? Double,
           let rememberedLongitude = remembered["longitude"] as? Double,
           here.distance(from: CLLocation(latitude: rememberedLatitude, longitude: rememberedLongitude))
           < SavedLocation.myLocationMoveMeters {
            return name
        }
        guard let name = await lookUp(latitude, longitude)?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty else { return nil }
        defaults.set(["name": name, "latitude": latitude, "longitude": longitude], forKey: Self.rememberedKey)
        return name
    }

    /// The town, else the county, else the state: never a street address.
    private static func geocode(latitude: Double, longitude: Double) async -> String? {
        let places = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
        guard let place = places?.first else { return nil }
        return [place.locality, place.subAdministrativeArea, place.administrativeArea]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }
}
