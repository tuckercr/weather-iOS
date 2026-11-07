import XCTest
@testable import Cats_Dogs

@MainActor
final class UpdatePromptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testComparesVersionsNumberByNumber() {
        XCTAssertTrue(UpdatePrompt.isOlder("1.9", than: "1.10"))
        XCTAssertTrue(UpdatePrompt.isOlder("1.0", than: "1.0.1"))
        XCTAssertFalse(UpdatePrompt.isOlder("1.2", than: "1.2.0"))
        XCTAssertFalse(UpdatePrompt.isOlder("2.0", than: "1.10"))
        XCTAssertFalse(UpdatePrompt.isOlder("1.0", than: nil))
        XCTAssertFalse(UpdatePrompt.isOlder("1.0", than: "  "))
    }

    func testUnsetKeysNeverAsk() {
        XCTAssertEqual(UpdatePrompt.forVersion("1.0", minSupported: nil, minRecommended: nil, bannerDismissedAt: nil), .none)
    }

    func testBelowTheMinimumSupportedVersionTheUpdateIsRequiredEvenWhenTheBannerWasDismissed() {
        XCTAssertEqual(
            UpdatePrompt.forVersion("1.0", minSupported: "1.1", minRecommended: "1.2", bannerDismissedAt: now, now: now),
            .required
        )
    }

    func testBelowTheRecommendedVersionTheBannerShowsUntilDismissedForAWeek() {
        let ask = { (dismissed: Date?) in
            UpdatePrompt.forVersion("1.0", minSupported: "1.0", minRecommended: "1.1", bannerDismissedAt: dismissed, now: self.now)
        }
        XCTAssertEqual(ask(nil), .recommended)
        XCTAssertEqual(ask(now.addingTimeInterval(-60)), .none)
        XCTAssertEqual(ask(now.addingTimeInterval(-UpdatePrompt.snooze)), .recommended)
    }

    func testUpToDateNeverAsks() {
        XCTAssertEqual(UpdatePrompt.forVersion("1.2", minSupported: "1.0", minRecommended: "1.2", bannerDismissedAt: nil), .none)
    }
}

@MainActor
final class UpdatePromptViewModelTests: XCTestCase {
    private var preferences: IsolatedPreferences!

    override func setUp() async throws {
        preferences = IsolatedPreferences()
    }

    override func tearDown() async throws {
        preferences.destroy()
    }

    func testNotNowHidesTheBannerAndIsRemembered() {
        let viewModel = makeViewModel(minRecommended: "1.1")
        XCTAssertEqual(viewModel.prompt, .recommended)

        viewModel.dismissBanner()

        XCTAssertEqual(viewModel.prompt, .none)
        XCTAssertEqual(makeViewModel(minRecommended: "1.1").prompt, .none)
    }

    func testRefreshPicksUpNewRemoteConfigValues() {
        var minSupported: String?
        let viewModel = UpdatePromptViewModel(
            preferences: preferences.store,
            version: "1.0",
            minSupported: { minSupported },
            minRecommended: { nil },
            appStoreURL: { nil }
        )
        XCTAssertEqual(viewModel.prompt, .none)

        minSupported = "1.1"
        viewModel.refresh()

        XCTAssertEqual(viewModel.prompt, .required)
    }

    private func makeViewModel(minRecommended: String?) -> UpdatePromptViewModel {
        UpdatePromptViewModel(
            preferences: preferences.store,
            version: "1.0",
            minSupported: { nil },
            minRecommended: { minRecommended },
            appStoreURL: { URL(string: "https://apps.apple.com") }
        )
    }
}
