import CoreLocation
import Foundation
import Observation

enum LocationFetchState: Equatable {
    case idle
    case locating
    case located(SavedLocation)
    case permissionDenied
    case failed
}

@MainActor
@Observable
final class LocationPermissionViewModel: NSObject, CLLocationManagerDelegate {
    private(set) var state: LocationFetchState = .idle

    /// Give up on a fix after this, as Android does: with no signal (or no simulated location)
    /// Core Location can take minutes to fail.
    static let fixTimeout: Duration = .seconds(10)
    /// A position iOS already has, this recent, is used straight away.
    static let recentFixAge: TimeInterval = 10 * 60

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Error>?
    private var awaitingAuthorization = false
    // Test seams; nil means use the real CLLocationManager.
    private let authorizationStatusOverride: (() -> CLAuthorizationStatus)?
    private let locationFetcherOverride: (() async throws -> CLLocation?)?

    init(
        authorizationStatus: (() -> CLAuthorizationStatus)? = nil,
        locationFetcher: (() async throws -> CLLocation?)? = nil
    ) {
        authorizationStatusOverride = authorizationStatus
        locationFetcherOverride = locationFetcher
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func hasLocationPermission() -> Bool {
        switch authorizationStatusOverride?() ?? manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    /// Whether asking would show the system prompt: before the first answer, and again each launch
    /// for "Allow Once" or "Ask Next Time", which iOS reports as not yet decided.
    func canRequestPermission() -> Bool {
        (authorizationStatusOverride?() ?? manager.authorizationStatus) == .notDetermined
    }

    /// Once denied, iOS won't ask again; only the Settings app can grant it.
    func isPermissionDenied() -> Bool {
        switch authorizationStatusOverride?() ?? manager.authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    func requestPermission() {
        awaitingAuthorization = true
        manager.requestWhenInUseAuthorization()
    }

    func onPermissionDenied() {
        state = .permissionDenied
    }

    func fetchLocation() {
        guard hasLocationPermission() else {
            state = .permissionDenied
            return
        }
        guard state != .locating else { return }
        state = .locating
        Task {
            do {
                let location = try await requestLocation()
                if let location {
                    state = .located(
                        SavedLocation(
                            label: SavedLocation.myLocationLabel,
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                            isCurrentLocation: true
                        )
                    )
                } else {
                    state = .failed
                }
            } catch {
                state = .failed
            }
        }
    }

    private func requestLocation() async throws -> CLLocation? {
        if let locationFetcherOverride {
            return try await locationFetcherOverride()
        }
        if let known = manager.location, -known.timestamp.timeIntervalSinceNow < Self.recentFixAge {
            return known
        }
        let timeout = Task { [weak self] in
            try await Task.sleep(for: Self.fixTimeout)
            self?.finish(.success(nil))
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    /// Resumes the request under way, once: the fix, the error or the timeout, whichever is first.
    private func finish(_ result: Result<CLLocation?, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if awaitingAuthorization {
                    awaitingAuthorization = false
                    fetchLocation()
                }
            case .denied, .restricted:
                if awaitingAuthorization {
                    awaitingAuthorization = false
                    state = .permissionDenied
                }
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in finish(.success(locations.first)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }
}
