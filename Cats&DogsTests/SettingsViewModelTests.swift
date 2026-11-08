import CoreLocation
import UserNotifications
import XCTest
@testable import Cats_Dogs

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var preferences: IsolatedPreferences!

    override func setUp() async throws {
        preferences = IsolatedPreferences()
    }

    override func tearDown() async throws {
        preferences.destroy()
    }

    func testUnitOverrideDefaultsToSystem() {
        XCTAssertEqual(SettingsViewModel(preferences: preferences.store).unitOverride, .system)
    }

    func testUnitOverrideReflectsStoredValue() {
        preferences.store.setUnitOverride(.imperial)

        XCTAssertEqual(SettingsViewModel(preferences: preferences.store).unitOverride, .imperial)
    }

    func testSetUnitOverrideUpdatesStateAndPersists() {
        let viewModel = SettingsViewModel(preferences: preferences.store)

        viewModel.setUnitOverride(.metric)

        XCTAssertEqual(viewModel.unitOverride, .metric)
        XCTAssertEqual(preferences.reopened().unitOverride, .metric)
    }

    func testWalkCardIsShownByDefault() {
        XCTAssertTrue(SettingsViewModel(preferences: preferences.store).showWalkCard)
    }

    func testTurningTheWalkCardOffUpdatesStateAndPersists() {
        let viewModel = SettingsViewModel(preferences: preferences.store, rescheduleNotifications: {})

        viewModel.setShowWalkCard(false)

        XCTAssertFalse(viewModel.showWalkCard)
        XCTAssertFalse(preferences.reopened().showWalkCard)
    }

    func testTheNotificationCountLeavesOutWalkTimeWithoutADogButKeepsItsValue() {
        let viewModel = SettingsViewModel(preferences: preferences.store, rescheduleNotifications: {})
        viewModel.setNotifyMorningBriefing(true)
        viewModel.setNotifyWalkTime(true)
        viewModel.setNotifyRain(false)
        viewModel.setShowWalkCard(true)
        XCTAssertEqual(viewModel.notificationsOnCount, 2)

        viewModel.setShowWalkCard(false)

        XCTAssertEqual(viewModel.notificationsOnCount, 1)
        XCTAssertTrue(viewModel.notifyWalkTime)
        XCTAssertTrue(preferences.reopened().notifyWalkTime)
    }

    func testKindsSwitchedOffRemotelyAreHiddenAndLeftOutOfTheCount() {
        var off: Set<NotificationKind> = []
        let viewModel = SettingsViewModel(
            preferences: preferences.store,
            rescheduleNotifications: {},
            remotelyEnabled: { !off.contains($0) }
        )
        viewModel.setNotifyMorningBriefing(true)
        viewModel.setNotifyWalkTime(true)
        viewModel.setNotifyRain(true)
        viewModel.setShowWalkCard(true)
        XCTAssertEqual(viewModel.notificationsOnCount, 3)

        off = [.morningBriefing, .rain]

        XCTAssertFalse(viewModel.isAvailable(.morningBriefing))
        XCTAssertTrue(viewModel.isAvailable(.walkTime))
        XCTAssertFalse(viewModel.isAvailable(.rain))
        XCTAssertEqual(viewModel.notificationsOnCount, 1)
        XCTAssertTrue(viewModel.notifyMorningBriefing, "the user's own choice is kept for when it's back")
    }

    func testUsageSharingIsOnByDefault() {
        XCTAssertTrue(SettingsViewModel(preferences: preferences.store).shareUsageStatistics)
    }

    func testUsageSharingDefaultsToOffWhereConsentIsNeededAndCanBeTurnedOn() {
        let suite = ThrowawayDefaults()
        let defaults = suite.defaults
        defer { suite.destroy() }
        let germany = PreferencesStore(defaults: defaults, region: "DE")
        XCTAssertFalse(germany.shareUsageStatistics)
        XCTAssertTrue(PreferencesStore(defaults: defaults, region: "US").shareUsageStatistics)

        germany.setShareUsageStatistics(true)
        XCTAssertTrue(germany.shareUsageStatistics)
    }

    func testTurningOffUsageSharingPersistsAndAppliesIt() {
        var applied = 0
        let viewModel = SettingsViewModel(preferences: preferences.store, applyUsageSharing: { applied += 1 })

        viewModel.setShareUsageStatistics(false)

        XCTAssertFalse(viewModel.shareUsageStatistics)
        XCTAssertFalse(preferences.reopened().shareUsageStatistics)
        XCTAssertEqual(applied, 1)
    }

    func testClearCacheKeepsTheUsageSharingChoice() {
        preferences.store.setShareUsageStatistics(false)

        SettingsViewModel(preferences: preferences.store).clearCache()

        XCTAssertFalse(preferences.reopened().shareUsageStatistics)
    }

    func testClearCacheRemovesCachedWeatherAndForecast() async {
        preferences.store.setCachedWeather(await makeCurrentWeather(), for: "austin")
        preferences.store.setCachedForecast(await makeForecast(), for: "austin")
        XCTAssertNotNil(preferences.store.cachedWeather(for: "austin"))

        SettingsViewModel(preferences: preferences.store).clearCache()

        XCTAssertNil(preferences.store.cachedWeather(for: "austin"))
        XCTAssertNil(preferences.store.cachedForecast(for: "austin"))
    }

    func testClearCacheKeepsSavedLocationsAndUnitOverride() {
        let austin = SavedLocation(label: "Austin", latitude: 30.27, longitude: -97.74)
        preferences.store.setSavedLocations([austin])
        preferences.store.setUnitOverride(.imperial)

        SettingsViewModel(preferences: preferences.store).clearCache()

        XCTAssertEqual(preferences.store.savedLocations, [austin])
        XCTAssertEqual(preferences.store.unitOverride, .imperial)
    }

    // MARK: - Permissions

    func testPermissionStatusMapping() {
        XCTAssertEqual(PermissionStatus(CLAuthorizationStatus.authorizedWhenInUse), .granted)
        XCTAssertEqual(PermissionStatus(CLAuthorizationStatus.authorizedAlways), .granted)
        XCTAssertEqual(PermissionStatus(CLAuthorizationStatus.notDetermined), .notDetermined)
        XCTAssertEqual(PermissionStatus(CLAuthorizationStatus.denied), .denied)
        XCTAssertEqual(PermissionStatus(CLAuthorizationStatus.restricted), .denied)

        XCTAssertEqual(PermissionStatus(UNAuthorizationStatus.authorized), .granted)
        XCTAssertEqual(PermissionStatus(UNAuthorizationStatus.provisional), .granted)
        XCTAssertEqual(PermissionStatus(UNAuthorizationStatus.notDetermined), .notDetermined)
        XCTAssertEqual(PermissionStatus(UNAuthorizationStatus.denied), .denied)
    }

    func testRefreshPermissionsReflectsSystemStatus() async {
        let viewModel = makeViewModel(location: .denied, notifications: { .notDetermined })

        await viewModel.refreshPermissions()

        XCTAssertEqual(viewModel.locationPermission, .denied)
        XCTAssertEqual(viewModel.notificationPermission, .notDetermined)
    }

    /// Regression: "Not now" during onboarding leaves the status undetermined, and iOS Settings has no
    /// Notifications entry for the app until it has asked — so the prompt must be reachable in-app.
    func testRequestingNotificationsWhenGrantedUpdatesStatusAndSchedulesNotifications() async {
        var systemStatus = UNAuthorizationStatus.notDetermined
        var prompts = 0
        var reschedules = 0
        let viewModel = makeViewModel(
            notifications: { systemStatus },
            onRequest: {
                prompts += 1
                systemStatus = .authorized
                return true
            },
            onReschedule: { reschedules += 1 }
        )
        await viewModel.refreshPermissions()
        XCTAssertEqual(viewModel.notificationPermission, .notDetermined)

        await viewModel.requestNotificationPermission()

        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(reschedules, 1)
        XCTAssertEqual(viewModel.notificationPermission, .granted)
    }

    func testDecliningTheNotificationPromptMarksDeniedAndSchedulesNothing() async {
        var systemStatus = UNAuthorizationStatus.notDetermined
        var reschedules = 0
        let viewModel = makeViewModel(
            notifications: { systemStatus },
            onRequest: {
                systemStatus = .denied
                return false
            },
            onReschedule: { reschedules += 1 }
        )

        await viewModel.requestNotificationPermission()

        XCTAssertEqual(reschedules, 0)
        XCTAssertEqual(viewModel.notificationPermission, .denied)
    }

    private func makeViewModel(
        location: CLAuthorizationStatus = .notDetermined,
        notifications: @escaping () -> UNAuthorizationStatus = { .notDetermined },
        onRequest: @escaping () -> Bool = { false },
        onReschedule: @escaping () -> Void = {}
    ) -> SettingsViewModel {
        SettingsViewModel(
            preferences: preferences.store,
            locationStatus: { location },
            notificationStatus: { notifications() },
            requestNotificationAuthorization: { onRequest() },
            rescheduleNotifications: { onReschedule() },
            applyUsageSharing: {}
        )
    }

    // MARK: - Follow my location

    func testFollowMyLocationExplainsFirstUnlessAlwaysIsAllowed() {
        let notYet = SettingsViewModel(
            preferences: preferences.store,
            follower: MyLocationFollower(preferences: preferences.store, authorization: .authorizedWhenInUse, refresh: {})
        )
        notYet.setFollowMyLocation(true)
        XCTAssertTrue(notYet.isExplainingFollowMyLocation)
        XCTAssertFalse(preferences.store.followMyLocation, "Nothing changes until Continue")

        var openedSettings = false
        notYet.confirmFollowMyLocation { openedSettings = true }
        XCTAssertFalse(notYet.isExplainingFollowMyLocation)
        XCTAssertTrue(preferences.store.followMyLocation)
        XCTAssertFalse(openedSettings, "The first time, iOS asks for Always itself")

        let always = SettingsViewModel(
            preferences: preferences.store,
            follower: MyLocationFollower(preferences: preferences.store, authorization: .authorizedAlways, refresh: {})
        )
        always.setFollowMyLocation(false)
        XCTAssertFalse(always.followsMyLocation)
        always.setFollowMyLocation(true)
        XCTAssertFalse(always.isExplainingFollowMyLocation)
        XCTAssertTrue(always.followsMyLocation)
    }

    func testTheLinkFromIOSSettingsIsHandledOnce() {
        let link = NotificationSettingsLink()
        let viewModel = SettingsViewModel(preferences: preferences.store, notificationSettingsLink: link)

        link.isRequested = true
        XCTAssertTrue(viewModel.notificationSettingsRequested)
        viewModel.notificationSettingsShown()
        XCTAssertFalse(viewModel.notificationSettingsRequested)
    }
}
