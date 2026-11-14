import CoreLocation
import XCTest
@testable import Cats_Dogs

@MainActor
final class AnalyticsRepositoryTests: XCTestCase {
    private var preferences: IsolatedPreferences!
    private var sent: [(name: String, parameters: [String: Any]?)] = []
    private var collectionSettings: [Bool] = []
    private var userProperties: [String: String] = [:]
    private let added = CityAdded(source: .suggestion, provider: .openWeather)

    override func setUp() async throws {
        preferences = IsolatedPreferences()
        sent = []
        collectionSettings = []
        userProperties = [:]
    }

    override func tearDown() async throws {
        preferences.destroy()
    }

    func testSendsEventsWhenEveryGateIsOpen() {
        let analytics = makeRepository()

        analytics.logOnboardingComplete(OnboardingAnswers(hasDog: true, notifications: .granted, location: .skipped))
        analytics.logCityAdded(CityAdded(source: .typedMatch, provider: .openMeteo))
        analytics.logSettingsOpened()
        analytics.logWeatherError(WeatherRequestFailure(provider: .openMeteo, request: .airQuality, errorKey: "offline"))

        XCTAssertEqual(sent.map(\.name), ["onboarding_complete", "city_added", "settings_opened", "weather_error"])
        XCTAssertEqual(strings(sent[0]), ["has_dog": "yes", "notifications": "granted", "location": "skipped"])
        XCTAssertEqual(strings(sent[1]), ["source": "typed_match", "provider": "open_meteo"])
        XCTAssertEqual(strings(sent[3]), ["error_key": "offline", "provider": "open_meteo", "request": "air_quality"])
    }

    func testOnboardingStepsPermissionsAndNotificationOpens() {
        let analytics = makeRepository()

        for step in [OnboardingStep.welcome, .dog, .notifications, .location, .done] {
            analytics.logOnboardingStep(step)
        }
        analytics.logPermissionChanged(.locationAlways, granted: false, from: .followMyLocation)
        analytics.logPermissionChanged(.notifications, granted: true, from: .settings)
        analytics.logPermissionChanged(.location, granted: true, from: .addMyLocation)
        analytics.logNotificationOpened(.morningBriefing)
        analytics.logNotificationOpened(.walkTime)
        analytics.logNotificationOpened(.rain)

        XCTAssertEqual(sent.prefix(4).map { strings($0)["step"] }, ["welcome", "dog", "notifications", "location"])
        XCTAssertEqual(sent.dropFirst(4).prefix(3).map(strings), [
            ["permission": "location_always", "result": "denied", "from": "follow_my_location"],
            ["permission": "notifications", "result": "granted", "from": "settings"],
            ["permission": "location", "result": "granted", "from": "add_my_location"],
        ])
        XCTAssertEqual(sent.suffix(3).map { $0.name }, Array(repeating: "notification_opened", count: 3))
        XCTAssertEqual(sent.suffix(3).map { strings($0)["kind"] }, ["briefing", "walk", "rain"])
    }

    func testUserPropertiesAreSetBehindTheGates() async {
        let properties = AnalyticsUserProperties(
            hasDog: true, briefingOn: true, walkTimeOn: false, locationAccess: .authorizedWhenInUse,
            followLocation: false, units: .imperial, cityCount: 3
        )

        await makeRepository(remotelyEnabled: false, properties: properties).refreshUserProperties()
        XCTAssertEqual(userProperties, [:])

        await makeRepository(properties: properties).refreshUserProperties()
        XCTAssertEqual(userProperties, [
            "has_dog": "yes", "briefing_on": "yes", "walk_time_on": "no", "location_access": "while_using",
            "follow_location": "no", "units": "imperial", "city_count": "2-3",
        ])
    }

    func testUserPropertyBands() {
        XCTAssertEqual([0, 1, 2, 3, 4, 9].map(AnalyticsUserProperties.band), ["0", "1", "2-3", "2-3", "4+", "4+"])
        XCTAssertEqual(
            [CLAuthorizationStatus.notDetermined, .denied, .authorizedWhenInUse, .authorizedAlways].map(AnalyticsUserProperties.access),
            ["none", "none", "while_using", "always"]
        )
        XCTAssertEqual(
            [PermissionStatus.granted, .denied, .notDetermined].map { OnboardingAnswers.Permission($0).rawValue },
            ["granted", "denied", "skipped"]
        )
    }

    private func strings(_ event: (name: String, parameters: [String: Any]?)) -> [String: String] {
        (event.parameters ?? [:]).compactMapValues { $0 as? String }
    }

    func testDropsEventsWithoutFirebase() {
        makeRepository(configured: false).logCityAdded(added)

        XCTAssertTrue(sent.isEmpty)
    }

    func testRemoteKillSwitchDropsEvents() {
        makeRepository(remotelyEnabled: false).logCityAdded(added)

        XCTAssertTrue(sent.isEmpty)
    }

    func testUserOptOutDropsEvents() {
        preferences.store.setShareUsageStatistics(false)

        makeRepository().logCityAdded(added)

        XCTAssertTrue(sent.isEmpty)
    }

    func testUsageSharingPreferenceIsPushedToTheSdk() {
        let analytics = makeRepository()

        analytics.applyUsageSharingPreference()
        preferences.store.setShareUsageStatistics(false)
        analytics.applyUsageSharingPreference()

        XCTAssertEqual(collectionSettings, [true, false])
    }

    func testKillSwitchAlsoTurnsOffSdkCollection() {
        makeRepository(remotelyEnabled: false).applyUsageSharingPreference()

        XCTAssertEqual(collectionSettings, [false])
    }

    func testUsageSharingPreferenceIsNotPushedWithoutFirebase() {
        makeRepository(configured: false).applyUsageSharingPreference()

        XCTAssertTrue(collectionSettings.isEmpty)
    }

    @discardableResult
    private func makeRepository(
        configured: Bool = true,
        remotelyEnabled: Bool = true,
        properties: AnalyticsUserProperties? = nil
    ) -> AnalyticsRepository {
        AnalyticsRepository(
            preferences: preferences.store,
            isConfigured: { configured },
            remotelyEnabled: { remotelyEnabled },
            sendEvent: { [unowned self] in sent.append(($0, $1)) },
            setCollectionEnabled: { [unowned self] in collectionSettings.append($0) },
            setUserProperty: { [unowned self] value, name in userProperties[name] = value },
            readUserProperties: {
                properties ?? AnalyticsUserProperties(
                    hasDog: false, briefingOn: false, walkTimeOn: false, locationAccess: .notDetermined,
                    followLocation: false, units: .metric, cityCount: 0
                )
            }
        )
    }
}
