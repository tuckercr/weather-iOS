import CoreLocation
import Foundation
import Observation
import UserNotifications

/// iOS only lists a permission in the Settings app once the app has asked for it, so a permission
/// that was never requested has to be requested in-app; only a denied one can be fixed in Settings.
enum PermissionStatus: Equatable {
    case granted
    case notDetermined
    case denied

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: self = .granted
        case .notDetermined: self = .notDetermined
        default: self = .denied
        }
    }

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral: self = .granted
        case .notDetermined: self = .notDetermined
        default: self = .denied
        }
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    private(set) var unitOverride: UnitOverride
    private(set) var shareUsageStatistics: Bool
    private(set) var showWalkCard: Bool
    private(set) var notifyMorningBriefing: Bool
    private(set) var notifyWalkTime: Bool
    private(set) var notifyRain: Bool
    private(set) var locationPermission: PermissionStatus = .notDetermined
    private(set) var notificationPermission: PermissionStatus = .notDetermined
    /// Whether there's a My Location to follow: Follow my location only shows then.
    private(set) var hasMyLocation: Bool

    private let preferences: PreferencesStore
    private let locationStatus: () -> CLAuthorizationStatus
    private let notificationStatus: () async -> UNAuthorizationStatus
    private let requestNotificationAuthorization: () async -> Bool
    private let rescheduleNotifications: () async -> Void
    private let applyUsageSharing: () -> Void
    private let remotelyEnabled: (NotificationKind) -> Bool

    init(
        preferences: PreferencesStore? = nil,
        locationStatus: (() -> CLAuthorizationStatus)? = nil,
        notificationStatus: (() async -> UNAuthorizationStatus)? = nil,
        requestNotificationAuthorization: (() async -> Bool)? = nil,
        rescheduleNotifications: (() async -> Void)? = nil,
        applyUsageSharing: (() -> Void)? = nil,
        remotelyEnabled: ((NotificationKind) -> Bool)? = nil
    ) {
        let preferences = preferences ?? .shared
        self.preferences = preferences
        self.locationStatus = locationStatus ?? { CLLocationManager().authorizationStatus }
        self.notificationStatus = notificationStatus ?? {
            await WeatherNotificationScheduler.shared.authorizationStatus()
        }
        self.requestNotificationAuthorization = requestNotificationAuthorization ?? {
            await WeatherNotificationScheduler.shared.requestAuthorization()
        }
        self.rescheduleNotifications = rescheduleNotifications ?? {
            await WeatherNotificationScheduler.shared.scheduleNotifications()
        }
        self.applyUsageSharing = applyUsageSharing ?? {
            AnalyticsRepository.shared.applyUsageSharingPreference()
        }
        self.remotelyEnabled = remotelyEnabled ?? { RemoteConfigRepository.shared.notificationsEnabled($0) }
        unitOverride = preferences.unitOverride
        shareUsageStatistics = preferences.shareUsageStatistics
        showWalkCard = preferences.showWalkCard
        notifyMorningBriefing = preferences.notifyMorningBriefing
        notifyWalkTime = preferences.notifyWalkTime
        notifyRain = preferences.notifyRain
        hasMyLocation = preferences.savedLocations.contains(where: \.isCurrentLocation)
    }

    func setUnitOverride(_ override: UnitOverride) {
        unitOverride = override
        preferences.setUnitOverride(override)
    }

    /// Deliberately not tracked itself.
    func setShareUsageStatistics(_ enabled: Bool) {
        shareUsageStatistics = enabled
        preferences.setShareUsageStatistics(enabled)
        applyUsageSharing()
    }

    /// "I have a dog": the walk card, Paw check, the briefing's walk sentence and Walk time. Walk time
    /// keeps its own value, so turning the dog back on brings it back as it was.
    func setShowWalkCard(_ show: Bool) {
        showWalkCard = show
        preferences.setShowWalkCard(show)
        Task { await rescheduleNotifications() }
    }

    /// Whether a kind's switch shows in Settings: not when Remote Config has switched it off for
    /// everyone, and Walk time only with a dog. A hidden switch keeps its value.
    func isAvailable(_ kind: NotificationKind) -> Bool {
        remotelyEnabled(kind) && (kind != .walkTime || showWalkCard)
    }

    /// For the Notifications row in Settings: how many of the shown switches are on.
    var notificationsOnCount: Int {
        let switches: [(NotificationKind, Bool)] = [
            (.morningBriefing, notifyMorningBriefing),
            (.walkTime, notifyWalkTime),
            (.rain, notifyRain),
        ]
        return switches.filter { isAvailable($0.0) && $0.1 }.count
    }

    /// The notification switches: each kind can be turned off on its own, and the queue is replanned.
    func setNotifyMorningBriefing(_ enabled: Bool) {
        notifyMorningBriefing = enabled
        preferences.setNotifyMorningBriefing(enabled)
        Task { await rescheduleNotifications() }
    }

    func setNotifyWalkTime(_ enabled: Bool) {
        notifyWalkTime = enabled
        preferences.setNotifyWalkTime(enabled)
        Task { await rescheduleNotifications() }
    }

    func setNotifyRain(_ enabled: Bool) {
        notifyRain = enabled
        preferences.setNotifyRain(enabled)
        Task { await rescheduleNotifications() }
    }

    func clearCache() {
        preferences.clearCache()
    }

    func refreshPermissions() async {
        locationPermission = PermissionStatus(locationStatus())
        hasMyLocation = preferences.savedLocations.contains(where: \.isCurrentLocation)
        notificationPermission = PermissionStatus(await notificationStatus())
    }

    /// Shows the system prompt. Only meaningful while the status is `.notDetermined`.
    func requestNotificationPermission() async {
        if await requestNotificationAuthorization() {
            await rescheduleNotifications()
        }
        await refreshPermissions()
    }
}
