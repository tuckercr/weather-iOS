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
    /// "Always" rather than "While Using the App".
    private(set) var locationAlways = false
    private(set) var notificationPermission: PermissionStatus = .notDetermined
    /// Whether there's a My Location to follow: Follow my location only shows then.
    private(set) var hasMyLocation: Bool

    private let preferences: PreferencesStore
    private let location: LocationRepository
    private let locationStatus: @MainActor () -> CLAuthorizationStatus
    private let addCity: @MainActor (SavedLocation) -> Void
    private let notificationStatus: () async -> UNAuthorizationStatus
    private let requestNotificationAuthorization: () async -> Bool
    private let rescheduleNotifications: () async -> Void
    private let applyUsageSharing: () -> Void
    private let remotelyEnabled: (NotificationKind) -> Bool
    private let follower: MyLocationFollower
    private let notificationSettingsLink: NotificationSettingsLink
    private let sendSamples: () async -> Void
    private let onPermissionAnswered: (AnalyticsPermission, _ granted: Bool) -> Void
    /// The analytics user properties follow every change made here.
    private let refreshAnalytics: () -> Void
    /// Turning Follow my location on without "Always" explains first.
    private(set) var isExplainingFollowMyLocation = false

    init(
        preferences: PreferencesStore? = nil,
        location: LocationRepository? = nil,
        locationStatus: (@MainActor () -> CLAuthorizationStatus)? = nil,
        addCity: (@MainActor (SavedLocation) -> Void)? = nil,
        notificationStatus: (() async -> UNAuthorizationStatus)? = nil,
        requestNotificationAuthorization: (() async -> Bool)? = nil,
        rescheduleNotifications: (() async -> Void)? = nil,
        applyUsageSharing: (() -> Void)? = nil,
        remotelyEnabled: ((NotificationKind) -> Bool)? = nil,
        follower: MyLocationFollower? = nil,
        notificationSettingsLink: NotificationSettingsLink? = nil,
        sendSamples: (() async -> Void)? = nil,
        onPermissionAnswered: ((AnalyticsPermission, _ granted: Bool) -> Void)? = nil,
        refreshAnalytics: (() -> Void)? = nil
    ) {
        let preferences = preferences ?? .shared
        self.preferences = preferences
        let location = location ?? .shared
        self.location = location
        self.locationStatus = locationStatus ?? { location.authorizationStatus }
        self.addCity = addCity ?? { _ in }
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
        self.follower = follower ?? .shared
        self.notificationSettingsLink = notificationSettingsLink ?? .shared
        self.sendSamples = sendSamples ?? {
            #if DEBUG
            await WeatherNotificationScheduler.shared.sendSamples()
            #endif
        }
        self.onPermissionAnswered = onPermissionAnswered ?? { permission, granted in
            AnalyticsRepository.shared.logPermissionChanged(permission, granted: granted, from: .settings)
        }
        self.refreshAnalytics = refreshAnalytics ?? {
            Task { await AnalyticsRepository.shared.refreshUserProperties() }
        }
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
        refreshAnalytics()
    }

    /// Deliberately not tracked itself.
    func setShareUsageStatistics(_ enabled: Bool) {
        shareUsageStatistics = enabled
        preferences.setShareUsageStatistics(enabled)
        applyUsageSharing()
        if enabled { refreshAnalytics() }
    }

    /// "I have a dog": the walk card, Paw check, the briefing's walk sentence and Walk time. Walk time
    /// keeps its own value, so turning the dog back on brings it back as it was.
    func setShowWalkCard(_ show: Bool) {
        showWalkCard = show
        preferences.setShowWalkCard(show)
        refreshAnalytics()
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
        refreshAnalytics()
        Task { await rescheduleNotifications() }
    }

    func setNotifyWalkTime(_ enabled: Bool) {
        notifyWalkTime = enabled
        preferences.setNotifyWalkTime(enabled)
        refreshAnalytics()
        Task { await rescheduleNotifications() }
    }

    func setNotifyRain(_ enabled: Bool) {
        notifyRain = enabled
        preferences.setNotifyRain(enabled)
        refreshAnalytics()
        Task { await rescheduleNotifications() }
    }

    func clearCache() {
        preferences.clearCache()
    }

    func refreshPermissions() async {
        let location = locationStatus()
        locationPermission = PermissionStatus(location)
        locationAlways = location == .authorizedAlways
        hasMyLocation = preferences.savedLocations.contains(where: \.isCurrentLocation)
        notificationPermission = PermissionStatus(await notificationStatus())
    }

    /// "Allow location access": the system prompt, then, once allowed, My Location as a saved city,
    /// as onboarding adds it: location is only useful as a city.
    func requestLocationAccess() async {
        let asks = location.canRequestPermission()
        let granted = await location.requestPermission()
        if asks { onPermissionAnswered(.location, granted) }
        if granted, let here = await location.currentPosition() {
            addCity(here)
        }
        await refreshPermissions()
        refreshAnalytics()
    }

    // MARK: - Follow my location

    /// What the switch shows: on only while it's set and "Always" is allowed.
    var followsMyLocation: Bool { follower.isFollowing }

    /// Off turns it straight off. On with "Always" already allowed has nothing to ask, so nothing to
    /// explain; otherwise the explanation shows first (`confirmFollowMyLocation`).
    func setFollowMyLocation(_ on: Bool) {
        if !on {
            follower.turnOff()
            refreshAnalytics()
        } else if follower.authorization == .authorizedAlways {
            follower.turnOn {}
            refreshAnalytics()
        } else {
            isExplainingFollowMyLocation = true
        }
    }

    /// "Continue" on the explanation: asks for "Always", which iOS only shows once; after that,
    /// `openSettings` opens the Settings app.
    func confirmFollowMyLocation(openSettings: () -> Void) {
        isExplainingFollowMyLocation = false
        follower.turnOn(openSettings: openSettings)
    }

    func dismissFollowMyLocationExplanation() {
        isExplainingFollowMyLocation = false
    }

    // MARK: - The Notifications screen from iOS Settings

    /// iOS Settings' link to the app's notification settings was tapped.
    var notificationSettingsRequested: Bool { notificationSettingsLink.isRequested }

    /// Handled: the root view has gone to the Notifications screen.
    func notificationSettingsShown() {
        notificationSettingsLink.isRequested = false
    }

    /// Debug builds only: one of each notification, a few seconds apart.
    func sendSampleNotifications() async {
        await sendSamples()
    }

    /// Shows the system prompt. Only meaningful while the status is `.notDetermined`.
    func requestNotificationPermission() async {
        let asks = PermissionStatus(await notificationStatus()) == .notDetermined
        let granted = await requestNotificationAuthorization()
        if asks { onPermissionAnswered(.notifications, granted) }
        if granted {
            await rescheduleNotifications()
        }
        await refreshPermissions()
        refreshAnalytics()
    }
}
