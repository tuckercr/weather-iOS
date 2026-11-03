import CoreLocation
import Foundation
import Observation
import UIKit

/// "Follow my location". With the switch on and "Always" location allowed, iOS wakes the app after a
/// significant move (cell and Wi-Fi changes, so cheap on battery), even when it isn't running. My
/// Location then moves there by the app's own rule, the weather is refreshed and the notifications
/// replanned. The background refresh also moves it to the last position iOS has. Without it My
/// Location only moves while the app is open, so the briefing can be for the last place the app was
/// opened. Same as Android's `MyLocationFollower`.
@MainActor
@Observable
final class MyLocationFollower: NSObject, CLLocationManagerDelegate {
    static let shared = MyLocationFollower()

    /// The switch as set.
    private(set) var switchedOn: Bool
    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let refresh: () async -> Void
    @ObservationIgnored private let authorizationOverride: CLAuthorizationStatus?

    init(
        preferences: PreferencesStore? = nil,
        authorization: CLAuthorizationStatus? = nil,
        refresh: (() async -> Void)? = nil
    ) {
        let preferences = preferences ?? .shared
        self.preferences = preferences
        authorizationOverride = authorization
        self.refresh = refresh ?? {
            _ = await WeatherBackgroundRefresher.shared.performRefresh(replan: true)
        }
        switchedOn = preferences.followMyLocation
        self.authorization = authorization ?? .notDetermined
        super.init()
        manager.delegate = self
        if authorization == nil { self.authorization = manager.authorizationStatus }
    }

    /// What the switch shows: on only while it's set and "Always" is allowed.
    var isFollowing: Bool {
        switchedOn && authorization == .authorizedAlways
    }

    /// At launch, including a relaunch for a move: iOS hands the move over once watching restarts.
    func start() {
        updateMonitoring()
    }

    /// The switch turned on, after the explanation. Asks for "Always", which iOS only does once;
    /// after that, or with location denied, only the Settings app can grant it.
    func turnOn(openSettings: () -> Void) {
        switchedOn = true
        preferences.setFollowMyLocation(true)
        switch authorization {
        case .authorizedAlways:
            updateMonitoring()
        case .authorizedWhenInUse, .notDetermined:
            if preferences.alwaysLocationAsked {
                openSettings()
            } else {
                preferences.setAlwaysLocationAsked()
                manager.requestAlwaysAuthorization()
            }
        default:
            openSettings()
        }
    }

    func turnOff() {
        switchedOn = false
        preferences.setFollowMyLocation(false)
        updateMonitoring()
    }

    /// For the background refresh: My Location moves to the last position iOS has, when following.
    func followLastKnownPosition() {
        guard isFollowing, let location = manager.location else { return }
        preferences.moveMyLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// A move reported by iOS: My Location follows a real one, then the weather and notifications.
    func handle(_ location: CLLocation) async {
        guard isFollowing,
              preferences.moveMyLocation(
                  latitude: location.coordinate.latitude,
                  longitude: location.coordinate.longitude
              ) else { return }
        await refresh()
    }

    private func updateMonitoring() {
        if isFollowing {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard authorizationOverride == nil else { return }
            authorization = manager.authorizationStatus
            updateMonitoring()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            // A relaunch for a move gets a few seconds; this asks for enough to fetch the weather.
            let task = UIApplication.shared.beginBackgroundTask(withName: "Follow my location")
            await handle(location)
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
