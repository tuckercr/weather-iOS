import XCTest
@testable import Cats_Dogs

@MainActor
final class WelcomeViewModelTests: XCTestCase {
    private var preferences: IsolatedPreferences!

    override func setUp() async throws {
        preferences = IsolatedPreferences()
    }

    override func tearDown() async throws {
        preferences.destroy()
    }

    func testFreshInstallHasNothingCompleted() {
        let viewModel = WelcomeViewModel(preferences: preferences.store)

        XCTAssertEqual(
            viewModel.onboardingState,
            OnboardingState(hasSeenWelcome: false, notificationOnboardingDone: false, locationOnboardingDone: false)
        )
    }

    func testInitialStateReflectsStoredFlags() {
        preferences.store.setHasSeenWelcome(true)
        preferences.store.setNotificationOnboardingDone()

        let viewModel = WelcomeViewModel(preferences: preferences.store)

        XCTAssertEqual(
            viewModel.onboardingState,
            OnboardingState(hasSeenWelcome: true, notificationOnboardingDone: true, locationOnboardingDone: false)
        )
    }

    func testCompleteWelcomeMarksStateDoneAndPersists() {
        let viewModel = WelcomeViewModel(preferences: preferences.store)

        viewModel.completeWelcome()

        XCTAssertEqual(viewModel.onboardingState?.hasSeenWelcome, true)
        XCTAssertEqual(viewModel.onboardingState?.notificationOnboardingDone, false)
        XCTAssertTrue(preferences.reopened().hasSeenWelcome)
    }

    func testWelcomeLeadsToTheDogQuestionOnlyInTheSameRun() {
        let viewModel = WelcomeViewModel(preferences: preferences.store)
        XCTAssertFalse(viewModel.isAskingAboutDog)

        viewModel.completeWelcome()
        XCTAssertTrue(viewModel.isAskingAboutDog)

        viewModel.answerDogQuestion(true)
        XCTAssertFalse(viewModel.isAskingAboutDog)
        XCTAssertFalse(
            WelcomeViewModel(preferences: preferences.reopened()).isAskingAboutDog,
            "A later launch, or an existing user after an update, isn't asked"
        )
    }

    func testCompleteNotificationOnboardingMarksStateDoneAndPersists() {
        let viewModel = WelcomeViewModel(preferences: preferences.store)

        viewModel.completeNotificationOnboarding()

        XCTAssertEqual(viewModel.onboardingState?.notificationOnboardingDone, true)
        XCTAssertEqual(viewModel.onboardingState?.locationOnboardingDone, false)
        XCTAssertTrue(preferences.reopened().notificationOnboardingDone)
    }

    func testCompleteLocationOnboardingMarksStateDoneAndPersists() {
        let viewModel = WelcomeViewModel(preferences: preferences.store)

        viewModel.completeLocationOnboarding()

        XCTAssertEqual(viewModel.onboardingState?.locationOnboardingDone, true)
        XCTAssertTrue(preferences.reopened().locationOnboardingDone)
    }

    func testOnlyTheLastOnboardingStepReportsOnboardingCompleteWithTheAnswers() async {
        var completions: [OnboardingAnswers] = []
        let viewModel = WelcomeViewModel(
            preferences: preferences.store,
            onOnboardingComplete: { completions.append($0) },
            permissionStatuses: { (.denied, .notDetermined) }
        )

        viewModel.completeWelcome()
        viewModel.answerDogQuestion(true)
        viewModel.completeNotificationOnboarding()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(completions, [])

        viewModel.completeLocationOnboarding()
        await waitUntil { completions.count == 1 }
        XCTAssertEqual(completions, [OnboardingAnswers(hasDog: true, notifications: .denied, location: .skipped)])
    }

    func testEachStepIsReportedOnceWhenShown() {
        var shown: [OnboardingStep] = []
        let viewModel = WelcomeViewModel(preferences: preferences.store, onStepShown: { shown.append($0) })

        viewModel.stepShown(.welcome)
        viewModel.stepShown(.welcome)
        viewModel.stepShown(.dog)
        viewModel.stepShown(.notifications)
        viewModel.stepShown(.location)
        viewModel.stepShown(.done)

        XCTAssertEqual(shown, [.welcome, .dog, .notifications, .location])
    }

    /// Installs from before the notification step existed must not be sent back through onboarding.
    func testLegacyInstallThatFinishedLocationOnboardingSkipsNotificationStep() {
        preferences.store.setHasSeenWelcome(true)
        preferences.store.setLocationOnboardingDone()

        let viewModel = WelcomeViewModel(preferences: preferences.store)

        XCTAssertEqual(viewModel.onboardingState?.notificationOnboardingDone, true)
    }

    // MARK: - Notification onboarding

    func testTheNotificationPromiseMentionsTheWalkWithADogAndRainWhileRemoteConfigAllows() {
        preferences.store.setShowWalkCard(true)
        let all = WelcomeViewModel(preferences: preferences.store, remotelyEnabled: { _ in true })
        XCTAssertEqual(
            all.notificationOnboardingText,
            "Each morning, Sunny & Misty will send a weather briefing for your location, and Sunny will nudge you at the best time for a walk."
                + "\n\nYou can turn on rain alerts in Settings."
        )

        preferences.store.setShowWalkCard(false)
        let noDog = WelcomeViewModel(preferences: preferences.store, remotelyEnabled: { $0 != .rain })
        XCTAssertEqual(noDog.notificationOnboardingText, "Each morning, Sunny & Misty will send a weather briefing for your location.")
    }

    func testAllowingNotificationsPlansThemOnlyWhenGrantedAndMovesOnEitherWay() async {
        for granted in [true, false] {
            var planned = 0
            let viewModel = WelcomeViewModel(
                preferences: preferences.store,
                requestNotificationAuthorization: { granted },
                scheduleNotifications: { planned += 1 }
            )

            await viewModel.allowNotifications()

            XCTAssertEqual(planned, granted ? 1 : 0)
            XCTAssertEqual(viewModel.onboardingState?.notificationOnboardingDone, true)
        }
    }

    // MARK: - Steps

    func testTheStepsGoWelcomeDogNotificationsLocationThenTheApp() async {
        var dog: Bool?
        var chosen: SavedLocation?
        let viewModel = WelcomeViewModel(
            preferences: preferences.store,
            onOnboardingComplete: { _ in },
            requestNotificationAuthorization: { false },
            onDogAnswered: { dog = $0 },
            onLocationChosen: { chosen = $0 }
        )
        XCTAssertEqual(viewModel.step, .welcome)
        viewModel.completeWelcome()
        XCTAssertEqual(viewModel.step, .dog)
        viewModel.answerDogQuestion(false)
        XCTAssertEqual(dog, false)
        XCTAssertEqual(viewModel.step, .notifications)
        await viewModel.allowNotifications()
        XCTAssertEqual(viewModel.step, .location)
        let austin = SavedLocation(label: "Austin", latitude: 30.27, longitude: -97.74)
        viewModel.chooseLocation(austin)
        XCTAssertEqual(chosen, austin)
        XCTAssertEqual(viewModel.step, .done)
    }

    func testWithoutAnotherViewModelTheDogAnswerIsSaved() {
        let viewModel = WelcomeViewModel(preferences: preferences.store)
        viewModel.answerDogQuestion(false)
        XCTAssertFalse(preferences.store.showWalkCard)
    }
}
