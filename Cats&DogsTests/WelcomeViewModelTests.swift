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

        viewModel.completeDogQuestion()
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

    func testOnlyTheLastOnboardingStepReportsOnboardingComplete() {
        var completions = 0
        let viewModel = WelcomeViewModel(preferences: preferences.store, onOnboardingComplete: { completions += 1 })

        viewModel.completeWelcome()
        viewModel.completeNotificationOnboarding()
        XCTAssertEqual(completions, 0)

        viewModel.completeLocationOnboarding()
        XCTAssertEqual(completions, 1)
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
}
