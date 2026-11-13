import Foundation
import Observation

/// Where a new user is: the welcome, the dog question, notifications, location, then the app.
enum OnboardingStep: Equatable {
    case welcome, dog, notifications, location, done
}

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
    private let onOnboardingComplete: @MainActor (OnboardingAnswers) -> Void
    private let onStepShown: @MainActor (OnboardingStep) -> Void
    /// What iOS allows now, notifications then location, for `onboarding_complete`.
    private let permissionStatuses: @MainActor () async -> (notifications: PermissionStatus, location: PermissionStatus)
    private var lastShownStep: OnboardingStep?
    private let remotelyEnabled: @MainActor (NotificationKind) -> Bool
    private let requestNotificationAuthorization: @MainActor () async -> Bool
    private let scheduleNotifications: @MainActor () async -> Void
    private let onDogAnswered: @MainActor (Bool) -> Void
    private let onLocationChosen: @MainActor (SavedLocation) -> Void

    init(
        preferences: PreferencesStore? = nil,
        onOnboardingComplete: (@MainActor (OnboardingAnswers) -> Void)? = nil,
        onStepShown: (@MainActor (OnboardingStep) -> Void)? = nil,
        permissionStatuses: (@MainActor () async -> (notifications: PermissionStatus, location: PermissionStatus))? = nil,
        remotelyEnabled: (@MainActor (NotificationKind) -> Bool)? = nil,
        requestNotificationAuthorization: (@MainActor () async -> Bool)? = nil,
        scheduleNotifications: (@MainActor () async -> Void)? = nil,
        onDogAnswered: (@MainActor (Bool) -> Void)? = nil,
        onLocationChosen: (@MainActor (SavedLocation) -> Void)? = nil
    ) {
        let preferences = preferences ?? .shared
        self.preferences = preferences
        self.onOnboardingComplete = onOnboardingComplete ?? { AnalyticsRepository.shared.logOnboardingComplete($0) }
        self.onStepShown = onStepShown ?? { AnalyticsRepository.shared.logOnboardingStep($0) }
        self.permissionStatuses = permissionStatuses ?? {
            (
                PermissionStatus(await WeatherNotificationScheduler.shared.authorizationStatus()),
                PermissionStatus(LocationRepository.shared.authorizationStatus)
            )
        }
        self.remotelyEnabled = remotelyEnabled ?? { RemoteConfigRepository.shared.notificationsEnabled($0) }
        self.requestNotificationAuthorization = requestNotificationAuthorization ?? {
            await WeatherNotificationScheduler.shared.requestAuthorization()
        }
        self.scheduleNotifications = scheduleNotifications ?? {
            await WeatherNotificationScheduler.shared.scheduleNotifications()
        }
        self.onDogAnswered = onDogAnswered ?? { preferences.setShowWalkCard($0) }
        self.onLocationChosen = onLocationChosen ?? { _ in }
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

    /// The step to show: nil until the state has loaded.
    var step: OnboardingStep? {
        guard let state = onboardingState else { return nil }
        if !state.hasSeenWelcome { return .welcome }
        if isAskingAboutDog { return .dog }
        if !state.notificationOnboardingDone { return .notifications }
        if !state.locationOnboardingDone { return .location }
        return .done
    }

    /// The root view showed `step`: counted once each time the step changes, for `onboarding_step`.
    func stepShown(_ step: OnboardingStep) {
        guard step != lastShownStep else { return }
        lastShownStep = step
        if step != .done { onStepShown(step) }
    }

    /// "Is there a dog at home?": the walk card, Paw Check and the walk notifications only show
    /// with one. The answer goes to Settings (`onDogAnswered`), then on to notifications.
    func answerDogQuestion(_ hasDog: Bool) {
        onDogAnswered(hasDog)
        isAskingAboutDog = false
    }

    /// A location from the onboarding location step: it becomes the first city, and onboarding ends.
    func chooseLocation(_ location: SavedLocation) {
        onLocationChosen(location)
        completeLocationOnboarding()
    }

    /// What "Stay in the loop" promises. With a dog (the question just before), the walk-time nudge
    /// is mentioned too; each kind only while Remote Config has it on.
    var notificationOnboardingText: String {
        let walkTime = preferences.showWalkCard && remotelyEnabled(.walkTime)
        return (walkTime
            ? String(localized: "Each morning, Sunny & Misty will send a weather briefing for your location, and Sunny will nudge you at the best time for a walk.", comment: "Onboarding: what the notifications will be")
            : String(localized: "Each morning, Sunny & Misty will send a weather briefing for your location.", comment: "Onboarding: what the notifications will be"))
            + (remotelyEnabled(.rain) ? "\n\n" + String(localized: "You can turn on rain alerts in Settings.", comment: "Onboarding: what the notifications will be") : "")
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
        // The answers are read from what's allowed now: on a new install a permission iOS hasn't
        // asked about yet was skipped, and a refused one was asked and denied.
        Task {
            let statuses = await permissionStatuses()
            onOnboardingComplete(OnboardingAnswers(
                hasDog: preferences.showWalkCard,
                notifications: OnboardingAnswers.Permission(statuses.notifications),
                location: OnboardingAnswers.Permission(statuses.location)
            ))
        }
    }
}
