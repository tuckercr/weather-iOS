import Foundation
import Observation

enum LocationFetchState: Equatable {
    case idle
    case locating
    case located(SavedLocation)
    case permissionDenied
    case failed
}

/// The location steps a screen takes: onboarding's "Use my location" and Add location's "Add My
/// Location". The location itself and what's been allowed come from `LocationRepository`.
@MainActor
@Observable
final class LocationPermissionViewModel {
    private(set) var state: LocationFetchState = .idle

    @ObservationIgnored private let location: LocationRepository
    /// Where the prompt was asked from, for `permission_changed`; nil in onboarding, which reports
    /// its answers in `onboarding_complete` instead.
    @ObservationIgnored private let permissionSource: AnalyticsPermissionSource?
    @ObservationIgnored private let onPermissionAnswered: @MainActor (_ granted: Bool, AnalyticsPermissionSource) -> Void

    init(
        location: LocationRepository? = nil,
        permissionSource: AnalyticsPermissionSource? = nil,
        onPermissionAnswered: (@MainActor (_ granted: Bool, AnalyticsPermissionSource) -> Void)? = nil
    ) {
        self.location = location ?? .shared
        self.permissionSource = permissionSource
        self.onPermissionAnswered = onPermissionAnswered ?? { granted, source in
            AnalyticsRepository.shared.logPermissionChanged(.location, granted: granted, from: source)
        }
    }

    func hasLocationPermission() -> Bool { location.hasLocationPermission() }

    func canRequestPermission() -> Bool { location.canRequestPermission() }

    /// Whether "Use my location" / "Add My Location" can do anything: access is on, or iOS can still ask.
    var canOfferMyLocation: Bool { hasLocationPermission() || canRequestPermission() }

    /// "Use my location" and "Add My Location": fetches the position when allowed, asks when iOS still
    /// can (and fetches once allowed), and otherwise reports it's denied, since iOS won't ask again.
    /// The outcome arrives in `state`.
    func useMyLocation() {
        if hasLocationPermission() {
            fetchLocation()
        } else if location.isPermissionDenied() {
            state = .permissionDenied
        } else {
            Task {
                let granted = await location.requestPermission()
                if let permissionSource { onPermissionAnswered(granted, permissionSource) }
                if granted {
                    fetchLocation()
                } else {
                    state = .permissionDenied
                }
            }
        }
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
                state = try await location.locate().map { .located($0) } ?? .failed
            } catch {
                state = .failed
            }
        }
    }
}
