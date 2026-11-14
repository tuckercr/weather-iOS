import Observation
import UserNotifications

/// The app's notification centre delegate. iOS Settings shows a link to the app's own notification
/// settings on its notification page (asked for with `.providesAppNotificationSettings`). Tapping it
/// opens the app with this set, and RootView goes to the Notifications screen. Taps on the app's
/// notifications are counted for analytics.
@MainActor
@Observable
final class NotificationSettingsLink: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationSettingsLink()

    var isRequested = false

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        Task { @MainActor in self.isRequested = true }
    }

    /// One of the app's notifications was tapped: counted as `notification_opened` by its kind.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let category = response.notification.request.content.categoryIdentifier
        await MainActor.run {
            if let kind = NotificationKind.allCases.first(where: {
                WeatherNotificationScheduler.threadIdentifier($0) == category
            }) {
                AnalyticsRepository.shared.logNotificationOpened(kind)
            }
        }
    }

    #if DEBUG
    /// Debug builds only: show them with the app open too, for the samples. Release builds keep
    /// the system default, which doesn't.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
    #endif
}
