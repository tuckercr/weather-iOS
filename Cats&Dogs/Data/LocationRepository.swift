import CoreLocation
import Foundation

/// Where the phone is, for My Location. `LocationRepository` provides it; tests fake it.
@MainActor
protocol DevicePositioning: AnyObject {
    func hasLocationPermission() -> Bool
    /// The phone's position now, waited for; nil without permission or without a fix.
    func currentPosition() async -> SavedLocation?
}

/// The phone's location and what the app has been allowed: the one owner of the
/// `CLLocationManager` the screens use, its permission prompt and its fixes. The location screens'
/// view models, Settings and the weather screen all go through it, so two of them asking at once
/// share one request. Follow my location keeps its own manager for watching significant moves in
/// the background. Same job as Android's `LocationRepository`.
@MainActor
final class LocationRepository: NSObject, CLLocationManagerDelegate, DevicePositioning {
    static let shared = LocationRepository()

    /// Give up on a fix after this, as Android does: with no signal (or no simulated location)
    /// Core Location can take minutes to fail.
    static let fixTimeout: Duration = .seconds(10)
    /// A position iOS already has, this recent, is used straight away.
    static let recentFixAge: TimeInterval = 10 * 60

    private let manager = CLLocationManager()
    /// Everyone waiting on the fix under way: one request answers them all.
    private var waiting: [CheckedContinuation<CLLocation?, Error>] = []
    private var timeout: Task<Void, Never>?
    /// Everyone waiting on the answer to the permission prompt.
    private var awaitingAnswer: [CheckedContinuation<Bool, Never>] = []
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

    var authorizationStatus: CLAuthorizationStatus {
        authorizationStatusOverride?() ?? manager.authorizationStatus
    }

    func hasLocationPermission() -> Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    /// Whether asking would show the system prompt: before the first answer, and again each launch
    /// for "Allow Once" or "Ask Next Time", which iOS reports as not yet decided.
    func canRequestPermission() -> Bool {
        authorizationStatus == .notDetermined
    }

    /// Once denied, iOS won't ask again; only the Settings app can grant it.
    func isPermissionDenied() -> Bool {
        switch authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    /// Shows the system prompt while iOS still will, and waits for the answer: true once allowed.
    /// Without a prompt to show, says whether access is on already.
    func requestPermission() async -> Bool {
        guard canRequestPermission() else { return hasLocationPermission() }
        return await withCheckedContinuation { continuation in
            awaitingAnswer.append(continuation)
            if awaitingAnswer.count == 1 { manager.requestWhenInUseAuthorization() }
        }
    }

    /// The phone's position now, waited for: a recent one iOS already has, otherwise a fresh fix
    /// (up to `fixTimeout`). Nil without permission or a fix.
    func currentPosition() async -> SavedLocation? {
        guard hasLocationPermission() else { return nil }
        return (try? await locate()) ?? nil
    }

    /// As `currentPosition`, but throws when the lookup fails outright rather than finding nothing.
    func locate() async throws -> SavedLocation? {
        guard let location = try await requestLocation() else { return nil }
        return SavedLocation(
            label: SavedLocation.myLocationLabel,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            isCurrentLocation: true
        )
    }

    private func requestLocation() async throws -> CLLocation? {
        if let locationFetcherOverride {
            return try await locationFetcherOverride()
        }
        if let known = manager.location, -known.timestamp.timeIntervalSinceNow < Self.recentFixAge {
            return known
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            guard waiting.count == 1 else { return }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: Self.fixTimeout)
                guard !Task.isCancelled else { return }
                self?.finish(.success(nil))
            }
            manager.requestLocation()
        }
    }

    /// Answers everyone waiting on the request under way, once: the fix, the error or the timeout,
    /// whichever is first.
    private func finish(_ result: Result<CLLocation?, Error>) {
        timeout?.cancel()
        timeout = nil
        let waiters = waiting
        waiting = []
        for continuation in waiters { continuation.resume(with: result) }
    }

    private func answered(_ status: CLAuthorizationStatus) {
        guard status != .notDetermined, !awaitingAnswer.isEmpty else { return }
        let waiters = awaitingAnswer
        awaitingAnswer = []
        let granted = status == .authorizedWhenInUse || status == .authorizedAlways
        for continuation in waiters { continuation.resume(returning: granted) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in answered(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let first = locations.first
        Task { @MainActor in finish(.success(first)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }
}
