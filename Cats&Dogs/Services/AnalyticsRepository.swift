import CoreLocation
import FirebaseAnalytics
import Foundation

/// A request to a weather service that failed, for `weather_error`. Logged for every failure,
/// including ones a fallback covered (Open-Meteo's reading failing before OpenWeather's is used).
struct WeatherRequestFailure: Equatable, Sendable {
    enum Provider: String, Sendable {
        case openMeteo = "open_meteo"
        case openWeather = "openweather"
    }

    enum Request: String, Sendable {
        case current
        case forecast
        case airQuality = "air_quality"
    }

    let provider: Provider
    let request: Request
    let errorKey: String
}

/// How onboarding went, for `onboarding_complete`.
struct OnboardingAnswers: Equatable {
    enum Permission: String {
        /// Allowed at the end of onboarding.
        case granted
        /// Asked and refused.
        case denied
        /// Never asked: "Not now", or a town or city typed instead.
        case skipped

        init(_ status: PermissionStatus) {
            switch status {
            case .granted: self = .granted
            case .denied: self = .denied
            case .notDetermined: self = .skipped
            }
        }
    }

    let hasDog: Bool
    let notifications: Permission
    let location: Permission
}

/// The permissions `permission_changed` reports, and where the app asked for them.
enum AnalyticsPermission: String {
    case notifications
    case location
    case locationAlways = "location_always"
}

enum AnalyticsPermissionSource: String {
    case settings
    case addMyLocation = "add_my_location"
    case followMyLocation = "follow_my_location"
}

/// Each phone's setup, sent as user properties so every event can be split by it. Categories only.
struct AnalyticsUserProperties: Equatable {
    let hasDog: Bool
    /// Briefings would arrive: the switch on, Remote Config has them on and notifications are allowed.
    let briefingOn: Bool
    /// The same for walk nudges, which also need a dog.
    let walkTimeOn: Bool
    let locationAccess: CLAuthorizationStatus
    let followLocation: Bool
    let units: WeatherUnits
    let cityCount: Int

    var values: [String: String] {
        [
            "has_dog": Self.yesNo(hasDog),
            "briefing_on": Self.yesNo(briefingOn),
            "walk_time_on": Self.yesNo(walkTimeOn),
            "location_access": Self.access(locationAccess),
            "follow_location": Self.yesNo(followLocation),
            "units": units.rawValue,
            "city_count": Self.band(cityCount),
        ]
    }

    static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    static func access(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "while_using"
        default: "none"
        }
    }

    static func band(_ count: Int) -> String {
        switch count {
        case ..<1: "0"
        case 1: "1"
        case 2...3: "2-3"
        default: "4+"
        }
    }

    /// Read from the app's settings, Remote Config and what iOS allows.
    @MainActor
    static func current() async -> AnalyticsUserProperties {
        let preferences = PreferencesStore.shared
        let remoteConfig = RemoteConfigRepository.shared
        let notificationsAllowed = PermissionStatus(await WeatherNotificationScheduler.shared.authorizationStatus()) == .granted
        let hasDog = preferences.showWalkCard
        return AnalyticsUserProperties(
            hasDog: hasDog,
            briefingOn: notificationsAllowed && preferences.notifyMorningBriefing
                && remoteConfig.notificationsEnabled(.morningBriefing),
            walkTimeOn: notificationsAllowed && hasDog && preferences.notifyWalkTime
                && remoteConfig.notificationsEnabled(.walkTime),
            locationAccess: LocationRepository.shared.authorizationStatus,
            followLocation: MyLocationFollower.shared.isFollowing,
            units: WeatherUnitsResolver.resolve(override: preferences.unitOverride),
            cityCount: preferences.savedLocations.count
        )
    }
}

/// Same events and parameter names as Android's `AnalyticsRepository`, so both platforms report into
/// one set of Firebase dashboards.
///
/// An event is only sent when all three gates are open, as on Android:
/// 1. Firebase is configured (`GoogleService-Info.plist` is bundled).
/// 2. The Remote Config kill switch `analytics_enabled` is on.
/// 3. The user hasn't turned off "Share usage statistics".
/// The last two are also enforced in the SDK, so Firebase's automatic events (sessions, screen views)
/// stop too.
@MainActor
final class AnalyticsRepository {
    static let shared = AnalyticsRepository()

    nonisolated static let eventOnboardingComplete = "onboarding_complete"
    nonisolated static let eventCityAdded = "city_added"
    nonisolated static let eventSettingsOpened = "settings_opened"
    nonisolated static let eventWeatherError = "weather_error"
    nonisolated static let paramErrorKey = "error_key"
    /// `city_added`: how it was added and which search provider found it (`CityAdded`).
    nonisolated static let paramSource = "source"
    nonisolated static let paramProvider = "provider"
    nonisolated static let eventOnboardingStep = "onboarding_step"
    nonisolated static let eventPermissionChanged = "permission_changed"
    nonisolated static let eventNotificationOpened = "notification_opened"

    private let preferences: PreferencesStore
    private let isConfigured: () -> Bool
    private let remotelyEnabled: () -> Bool
    private let sendEvent: (_ name: String, _ parameters: [String: Any]?) -> Void
    private let setCollectionEnabled: (Bool) -> Void
    private let setUserProperty: (_ value: String, _ name: String) -> Void
    private let readUserProperties: () async -> AnalyticsUserProperties

    init(
        preferences: PreferencesStore? = nil,
        isConfigured: (() -> Bool)? = nil,
        remotelyEnabled: (() -> Bool)? = nil,
        sendEvent: ((_ name: String, _ parameters: [String: Any]?) -> Void)? = nil,
        setCollectionEnabled: ((Bool) -> Void)? = nil,
        setUserProperty: ((_ value: String, _ name: String) -> Void)? = nil,
        readUserProperties: (() async -> AnalyticsUserProperties)? = nil
    ) {
        self.preferences = preferences ?? .shared
        self.isConfigured = isConfigured ?? { FirebaseSetup.isConfigured }
        self.remotelyEnabled = remotelyEnabled ?? { RemoteConfigRepository.shared.analyticsEnabled }
        self.sendEvent = sendEvent ?? { Analytics.logEvent($0, parameters: $1) }
        self.setCollectionEnabled = setCollectionEnabled ?? { Analytics.setAnalyticsCollectionEnabled($0) }
        self.setUserProperty = setUserProperty ?? { Analytics.setUserProperty($0, forName: $1) }
        self.readUserProperties = readUserProperties ?? { await AnalyticsUserProperties.current() }
    }

    func logOnboardingStep(_ step: OnboardingStep) {
        let name: String
        switch step {
        case .welcome: name = "welcome"
        case .dog: name = "dog"
        case .notifications: name = "notifications"
        case .location: name = "location"
        case .done: return
        }
        log(Self.eventOnboardingStep, parameters: ["step": name])
    }

    func logOnboardingComplete(_ answers: OnboardingAnswers) {
        log(Self.eventOnboardingComplete, parameters: [
            "has_dog": AnalyticsUserProperties.yesNo(answers.hasDog),
            "notifications": answers.notifications.rawValue,
            "location": answers.location.rawValue,
        ])
    }

    /// The app asked for `permission` outside onboarding, and this was the answer.
    func logPermissionChanged(_ permission: AnalyticsPermission, granted: Bool, from source: AnalyticsPermissionSource) {
        log(Self.eventPermissionChanged, parameters: [
            "permission": permission.rawValue,
            "result": granted ? "granted" : "denied",
            "from": source.rawValue,
        ])
    }

    /// The app was opened from one of its notifications.
    func logNotificationOpened(_ kind: NotificationKind) {
        let name: String
        switch kind {
        case .morningBriefing: name = "briefing"
        case .walkTime: name = "walk"
        case .rain: name = "rain"
        }
        log(Self.eventNotificationOpened, parameters: ["kind": name])
    }

    func logCityAdded(_ added: CityAdded) {
        log(Self.eventCityAdded, parameters: [
            Self.paramSource: added.source.rawValue,
            Self.paramProvider: added.provider.rawValue,
        ])
    }

    func logSettingsOpened() { log(Self.eventSettingsOpened) }

    func logWeatherError(_ failure: WeatherRequestFailure) {
        log(Self.eventWeatherError, parameters: [
            Self.paramErrorKey: failure.errorKey,
            Self.paramProvider: failure.provider.rawValue,
            "request": failure.request.rawValue,
        ])
    }

    /// Sends the phone's setup as user properties, behind the same gates as events. Run when the
    /// app becomes active, after a change in Settings or the city list, and when sharing turns on.
    func refreshUserProperties() async {
        guard isEnabled else { return }
        let properties = await readUserProperties()
        guard isEnabled else { return }
        for (name, value) in properties.values.sorted(by: { $0.key < $1.key }) {
            setUserProperty(value, name)
        }
    }

    /// Pushes the user's choice and the kill switch into the SDK. Run at launch and whenever the
    /// setting changes.
    func applyUsageSharingPreference() {
        guard isConfigured() else { return }
        setCollectionEnabled(preferences.shareUsageStatistics && remotelyEnabled())
    }

    private var isEnabled: Bool {
        isConfigured() && remotelyEnabled() && preferences.shareUsageStatistics
    }

    private func log(_ event: String, parameters: [String: Any]? = nil) {
        guard isEnabled else { return }
        sendEvent(event, parameters)
    }
}
