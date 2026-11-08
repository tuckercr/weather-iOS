import Foundation
import Observation

struct OnboardingState: Equatable {
    var hasSeenWelcome: Bool
    var notificationOnboardingDone: Bool
    var locationOnboardingDone: Bool
}

@MainActor
@Observable
final class WelcomeViewModel {
    private(set) var onboardingState: OnboardingState?
    /// True between the welcome screen and the "Is there a dog at home?" answer. In memory only: the step is
    /// part of a new user's first run, not resumed on a later launch, and not shown after an update.
    private(set) var isAskingAboutDog = false

    private let preferences: PreferencesStore
    private let onOnboardingComplete: @MainActor () -> Void
    private let remotelyEnabled: @MainActor (NotificationKind) -> Bool
    private let requestNotificationAuthorization: @MainActor () async -> Bool
    private let scheduleNotifications: @MainActor () async -> Void

    init(
        preferences: PreferencesStore? = nil,
        onOnboardingComplete: (@MainActor () -> Void)? = nil,
        remotelyEnabled: (@MainActor (NotificationKind) -> Bool)? = nil,
        requestNotificationAuthorization: (@MainActor () async -> Bool)? = nil,
        scheduleNotifications: (@MainActor () async -> Void)? = nil
    ) {
        let preferences = preferences ?? .shared
        self.preferences = preferences
        self.onOnboardingComplete = onOnboardingComplete ?? { AnalyticsRepository.shared.logOnboardingComplete() }
        self.remotelyEnabled = remotelyEnabled ?? { RemoteConfigRepository.shared.notificationsEnabled($0) }
        self.requestNotificationAuthorization = requestNotificationAuthorization ?? {
            await WeatherNotificationScheduler.shared.requestAuthorization()
        }
        self.scheduleNotifications = scheduleNotifications ?? {
            await WeatherNotificationScheduler.shared.scheduleNotifications()
        }
        onboardingState = OnboardingState(
            hasSeenWelcome: preferences.hasSeenWelcome,
            notificationOnboardingDone: preferences.notificationOnboardingDone,
            locationOnboardingDone: preferences.locationOnboardingDone
        )
    }

    func completeWelcome() {
        preferences.setHasSeenWelcome(true)
        isAskingAboutDog = true
        onboardingState = onboardingState.map { state in
            var updated = state
            updated.hasSeenWelcome = true
            return updated
        }
    }

    /// Moves on from "Is there a dog at home?". The answer itself goes to `SettingsViewModel.setShowWalkCard`.
    func completeDogQuestion() {
        isAskingAboutDog = false
    }

    /// What "Stay in the loop" promises. With a dog (the question just before), the walk-time nudge
    /// is mentioned too; each kind only while Remote Config has it on.
    var notificationOnboardingText: String {
        let walkTime = preferences.showWalkCard && remotelyEnabled(.walkTime)
        return (walkTime
            ? "Each morning, Sunny & Misty will send a weather briefing for your location, and Sunny will nudge you at the best time for a walk."
            : "Each morning, Sunny & Misty will send a weather briefing for your location.")
            + (remotelyEnabled(.rain) ? "\n\nYou can turn on rain alerts in Settings." : "")
    }

    /// "Allow notifications": asks iOS, plans the notifications if allowed, and moves on either way.
    func allowNotifications() async {
        if await requestNotificationAuthorization() {
            await scheduleNotifications()
        }
        completeNotificationOnboarding()
    }

    func completeNotificationOnboarding() {
        preferences.setNotificationOnboardingDone()
        onboardingState = onboardingState.map { state in
            var updated = state
            updated.notificationOnboardingDone = true
            return updated
        }
    }

    func completeLocationOnboarding() {
        preferences.setLocationOnboardingDone()
        onboardingState = onboardingState.map { state in
            var updated = state
            updated.locationOnboardingDone = true
            return updated
        }
        onOnboardingComplete()
    }
}
