import Foundation
import UserNotifications

/// What the app does at launch and when it goes to the background, kept out of the app type so it
/// only builds the scenes. Same jobs as Android's `WeatherApplication.onCreate`.
@MainActor
enum AppStartup {
    /// At every launch, including the relaunch iOS makes to report a move or run a refresh.
    static func launch() {
        FirebaseSetup.configureIfAvailable()
        AnalyticsRepository.shared.applyUsageSharingPreference()
        // Start the Remote Config fetch early so the values are ready by the next launch.
        _ = RemoteConfigRepository.shared
        // Set before launch finishes, so a tap on the iOS Settings link that opened the app arrives.
        UNUserNotificationCenter.current().delegate = NotificationSettingsLink.shared
        UNUserNotificationCenter.current().setNotificationCategories(WeatherNotificationScheduler.categories)
        Task { await WeatherNotificationScheduler.shared.refreshAuthorizationOptions() }
        // Follow my location: watching for moves has to restart at every launch, including the
        // relaunch iOS makes to report one.
        MyLocationFollower.shared.start()
        #if DEBUG
        // xcrun simctl launch <device> com.fangjet.weather -sendSampleNotifications
        if ProcessInfo.processInfo.arguments.contains("-sendSampleNotifications") {
            Task { await WeatherNotificationScheduler.shared.sendSamples() }
        }
        #endif
    }

    /// The app went to the background: ask iOS for the next refresh.
    static func enteredBackground() {
        WeatherBackgroundRefresher.shared.scheduleNextRefresh()
    }

    /// iOS granted background time for a refresh.
    static func backgroundRefresh() async {
        await WeatherBackgroundRefresher.shared.handleAppRefresh()
    }
}
