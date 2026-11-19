import Foundation
import Observation

/// What the weather screen shows, as far as the ratings prompt cares: whether it's the screen in
/// front, and the happy moment on it, if any.
struct ReviewPromptScreen: Equatable {
    /// The weather screen is in front with weather on it: counts as a day the app was used.
    var visible = false
    /// Set only when the weather is fresh and nothing is in the way (RATINGS.md, decisions 3 and 4).
    var moment: ReviewPromptMoment?

    static let hidden = ReviewPromptScreen()

    /// Bad verdicts that rule a moment out even when the sky looks nice: hot pavement, bad air,
    /// gales, storms and hurricane force wind.
    private static let blockingRatings: Set<WalkRating> = [.pawsHot, .badAir, .windy, .stormy, .danger]

    /// `frontmost` is false while anything covers the weather screen: Settings, a sheet, the
    /// update banner or screen, or onboarding.
    init(screen: WeatherScreen, isRefreshing: Bool, frontmost: Bool) {
        guard frontmost, case let .weather(state) = screen else { return }
        visible = true
        guard state.stale == nil, !state.showingForecast, !isRefreshing else { return }
        if case .error = state.week { return }
        if state.mood == .storm { return }
        if let advice = state.walkAdvice {
            if Self.blockingRatings.contains(advice.rating) || advice.warning != nil { return }
            if state.showsWalkCard, advice.rating == .great {
                moment = .greatWalk
                return
            }
        }
        if !state.darkNow, state.mood == .sunny || state.mood == .fair {
            moment = .pleasantWeather
        }
    }

    init(visible: Bool = false, moment: ReviewPromptMoment? = nil) {
        self.visible = visible
        self.moment = moment
    }
}

/// Asks for an App Store rating at the right moment (`ReviewPromptPolicy`). The weather screen
/// says what's on it and the app's comings and goings; when it's time, `requests` goes up and the
/// screen calls the system prompt. Same rules as Android's `ReviewPromptViewModel`.
@MainActor
@Observable
final class ReviewPromptViewModel {
    /// Goes up by one each time the system prompt should be asked for.
    private(set) var requests = 0

    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let settings: () -> ReviewPromptSettings
    @ObservationIgnored private let version: String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let notificationOpenedAt: () -> Date?
    @ObservationIgnored private let logRequest: (ReviewPromptMoment, Int) -> Void
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private let forced: Bool
    @ObservationIgnored private let installedAt: Date

    @ObservationIgnored private var screen = ReviewPromptScreen.hidden
    @ObservationIgnored private var visitStartedAt: Date
    @ObservationIgnored private var visitInterrupted = false
    @ObservationIgnored private var wentToBackground = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var forcedThisLaunch = false

    init(
        preferences: PreferencesStore? = nil,
        settings: (() -> ReviewPromptSettings)? = nil,
        version: String? = nil,
        now: (() -> Date)? = nil,
        calendar: Calendar = .current,
        notificationOpenedAt: (() -> Date?)? = nil,
        logRequest: ((ReviewPromptMoment, Int) -> Void)? = nil,
        sleep: ((Duration) async throws -> Void)? = nil,
        installedAt: Date? = nil,
        forced: Bool? = nil
    ) {
        let preferences = preferences ?? .shared
        let clock = now ?? { Date() }
        self.preferences = preferences
        self.settings = settings ?? { RemoteConfigRepository.shared.reviewPromptSettings }
        self.version = version ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        self.now = clock
        self.calendar = calendar
        self.notificationOpenedAt = notificationOpenedAt ?? { NotificationSettingsLink.shared.lastOpenedAt }
        self.logRequest = logRequest ?? { AnalyticsRepository.shared.logReviewPromptRequested($0, requestNumber: $1) }
        self.sleep = sleep ?? { try await Task.sleep(for: $0) }
        #if DEBUG
        // Launch with -reviewPromptForce YES to ask once, a few seconds after the weather shows,
        // whatever the counts and Remote Config say. Debug builds always show Apple's prompt;
        // TestFlight never does.
        self.forced = forced ?? UserDefaults.standard.bool(forKey: "reviewPromptForce")
        #else
        self.forced = forced ?? false
        #endif
        self.installedAt = installedAt ?? preferences.installedAt(fallback: clock())
        visitStartedAt = clock()
    }

    /// The weather screen changed what it shows.
    func screenChanged(_ screen: ReviewPromptScreen) {
        guard screen != self.screen else { return }
        self.screen = screen
        evaluate()
    }

    /// Counts the day and, at a moment that may ask, asks after the delay if nothing has changed.
    private func evaluate() {
        let screen = self.screen
        pending?.cancel()
        pending = nil
        guard screen.visible else { return }
        preferences.setReviewPromptHistory(
            ReviewPromptPolicy.recordingActiveDay(preferences.reviewPromptHistory, now: now(), calendar: calendar)
        )
        guard let moment = forced ? (screen.moment ?? .pleasantWeather) : screen.moment, mayAsk(moment) else { return }
        let delay = forced ? ReviewPromptSettings.standard.delaySeconds : settings().delaySeconds
        pending = Task { [weak self] in
            do { try await self?.sleep(.seconds(delay)) } catch { return }
            guard let self, !Task.isCancelled, self.screen == screen, self.mayAsk(moment) else { return }
            self.ask(moment)
        }
    }

    /// Something covered the app (a permission request, another system alert, Control Center).
    func becameInactive() {
        visitInterrupted = true
        pending?.cancel()
    }

    func enteredBackground() {
        wentToBackground = true
        pending?.cancel()
    }

    /// Back in front: a new visit if the app had gone to the background.
    func becameActive() {
        guard wentToBackground else { return }
        wentToBackground = false
        visitInterrupted = false
        visitStartedAt = now()
        evaluate()
    }

    private var visit: ReviewPromptVisit {
        // A tap's callback can land a moment after the app comes back, so allow a little slack.
        let fromNotification = notificationOpenedAt().map { $0 >= visitStartedAt.addingTimeInterval(-30) } ?? false
        return ReviewPromptVisit(fromNotification: fromNotification, interrupted: visitInterrupted)
    }

    private func mayAsk(_ moment: ReviewPromptMoment) -> Bool {
        if forced { return !forcedThisLaunch }
        return ReviewPromptPolicy.shouldAsk(
            moment: moment,
            history: preferences.reviewPromptHistory,
            settings: settings(),
            installedAt: installedAt,
            now: now(),
            version: version,
            visit: visit,
            calendar: calendar
        )
    }

    private func ask(_ moment: ReviewPromptMoment) {
        forcedThisLaunch = forced
        let history = ReviewPromptPolicy.recordingRequest(preferences.reviewPromptHistory, now: now(), version: version)
        preferences.setReviewPromptHistory(history)
        logRequest(moment, history.requests)
        requests += 1
    }
}
