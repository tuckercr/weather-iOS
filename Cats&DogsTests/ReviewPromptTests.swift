import XCTest
@testable import Cats_Dogs

/// The ratings prompt: the rule, its Remote Config values, what the weather screen counts as a
/// happy moment, and the view model's timing. Same cases as Android's `ReviewPromptTest`.
@MainActor
final class ReviewPromptTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Mon 1 Jan 2024, 00:00 UTC.
    private let dayStart = fixtureDayStart
    private let hour = 3600
    private let day: TimeInterval = 86400
    private var installed: Date { Date(timeIntervalSince1970: TimeInterval(dayStart + 10 * hour)) }
    private var on: ReviewPromptSettings {
        var settings = ReviewPromptSettings.standard
        settings.enabled = true
        return settings
    }

    private func date(days: Double, hours: Int = 12) -> Date {
        Date(timeIntervalSince1970: TimeInterval(dayStart + hours * hour) + days * day)
    }

    private func shouldAsk(
        moment: ReviewPromptMoment = .greatWalk,
        history: ReviewPromptHistory = ReviewPromptHistory(activeDays: 5),
        settings: ReviewPromptSettings? = nil,
        now: Date? = nil,
        version: String = "1.1",
        visit: ReviewPromptVisit = ReviewPromptVisit()
    ) -> Bool {
        ReviewPromptPolicy.shouldAsk(
            moment: moment,
            history: history,
            settings: settings ?? on,
            installedAt: installed,
            now: now ?? date(days: 7),
            version: version,
            visit: visit,
            calendar: calendar
        )
    }

    // MARK: - The rule

    func testAsksSomeoneWhoKeepsComingBackAtAHappyMoment() {
        XCTAssertTrue(shouldAsk())
        XCTAssertTrue(shouldAsk(moment: .pleasantWeather))
    }

    func testOffByDefaultAndWhenSwitchedOff() {
        XCTAssertFalse(ReviewPromptSettings.standard.enabled)
        XCTAssertFalse(shouldAsk(settings: .standard))
    }

    func testWaitsForTheDaysInstalledByTheCalendar() {
        // Installed at 10 AM on the 1st: the 7th day after starts at midnight on the 8th.
        XCTAssertFalse(shouldAsk(now: date(days: 6, hours: 23)))
        XCTAssertTrue(shouldAsk(now: date(days: 7, hours: 0)))
    }

    func testNeverOnTheDayOfInstallEvenWithNoWait() {
        var settings = on
        settings.minDaysInstalled = 0
        XCTAssertFalse(shouldAsk(settings: settings, now: date(days: 0, hours: 23)))
        XCTAssertTrue(shouldAsk(settings: settings, now: date(days: 1, hours: 0)))
    }

    func testWaitsForTheActiveDays() {
        XCTAssertFalse(shouldAsk(history: ReviewPromptHistory(activeDays: 4)))
        XCTAssertTrue(shouldAsk(history: ReviewPromptHistory(activeDays: 5)))
    }

    func testOnlyTheMomentsSwitchedOn() {
        var settings = on
        settings.moments = [.pleasantWeather]
        XCTAssertFalse(shouldAsk(moment: .greatWalk, settings: settings))
        XCTAssertTrue(shouldAsk(moment: .pleasantWeather, settings: settings))
        settings.moments = []
        XCTAssertFalse(shouldAsk(moment: .pleasantWeather, settings: settings))
    }

    func testNotAfterAnInterruptionOrFromANotification() {
        XCTAssertFalse(shouldAsk(visit: ReviewPromptVisit(interrupted: true)))
        XCTAssertFalse(shouldAsk(visit: ReviewPromptVisit(fromNotification: true)))
        var settings = on
        settings.onNotificationOpen = true
        XCTAssertTrue(shouldAsk(settings: settings, visit: ReviewPromptVisit(fromNotification: true)))
    }

    func testOncePerVersion() {
        let askedInThisVersion = ReviewPromptHistory(activeDays: 50, requests: 1, lastRequestAt: date(days: -300), lastRequestVersion: "1.1")
        XCTAssertFalse(shouldAsk(history: askedInThisVersion, now: date(days: 7)))
        XCTAssertTrue(shouldAsk(history: askedInThisVersion, version: "1.2"))
        var settings = on
        settings.oncePerVersion = false
        XCTAssertTrue(shouldAsk(history: askedInThisVersion, settings: settings))
    }

    func testTheCooldownBetweenAsks() {
        let asked = ReviewPromptHistory(activeDays: 50, requests: 1, lastRequestAt: date(days: 7), lastRequestVersion: "1.0")
        XCTAssertFalse(shouldAsk(history: asked, now: date(days: 126)))
        XCTAssertTrue(shouldAsk(history: asked, now: date(days: 127)))
    }

    func testTheLimitOnAsksInAll() {
        let three = ReviewPromptHistory(activeDays: 50, requests: 3, lastRequestAt: date(days: -400), lastRequestVersion: "1.0")
        XCTAssertFalse(shouldAsk(history: three))
        var settings = on
        settings.maxRequests = 0
        XCTAssertTrue(shouldAsk(history: three, settings: settings))
    }

    func testCountsEachCalendarDayOnce() {
        var history = ReviewPromptHistory()
        history = ReviewPromptPolicy.recordingActiveDay(history, now: date(days: 0, hours: 8), calendar: calendar)
        history = ReviewPromptPolicy.recordingActiveDay(history, now: date(days: 0, hours: 23), calendar: calendar)
        history = ReviewPromptPolicy.recordingActiveDay(history, now: date(days: 1, hours: 0), calendar: calendar)
        history = ReviewPromptPolicy.recordingActiveDay(history, now: date(days: 4), calendar: calendar)
        XCTAssertEqual(history.activeDays, 3)
        XCTAssertEqual(history.lastActiveDay, date(days: 4, hours: 0))
    }

    // MARK: - Remote Config values

    func testRemoteConfigValuesAreValidated() {
        let read = RemoteConfigRepository.reviewPromptSettings(
            enabled: true, minDaysInstalled: 3, minActiveDays: 2, moments: "pleasant_weather, nonsense",
            delaySeconds: 5, oncePerVersion: false, cooldownDays: 60, maxRequests: 0, onNotificationOpen: true
        )
        XCTAssertEqual(read, ReviewPromptSettings(
            enabled: true, minDaysInstalled: 3, minActiveDays: 2, moments: [.pleasantWeather], delaySeconds: 5,
            oncePerVersion: false, cooldownDays: 60, maxRequests: 0, onNotificationOpen: true
        ))

        let bad = RemoteConfigRepository.reviewPromptSettings(
            enabled: true, minDaysInstalled: 0, minActiveDays: 2.5, moments: nil,
            delaySeconds: 60, oncePerVersion: true, cooldownDays: 1, maxRequests: -1, onNotificationOpen: false
        )
        var expected = ReviewPromptSettings.standard
        expected.enabled = true
        XCTAssertEqual(bad, expected)

        XCTAssertEqual(RemoteConfigRepository.reviewPromptSettings(
            enabled: true, minDaysInstalled: nil, minActiveDays: nil, moments: "", delaySeconds: nil,
            oncePerVersion: true, cooldownDays: nil, maxRequests: nil, onNotificationOpen: false
        ).moments, [])
    }

    // MARK: - The weather screen's moments

    func testAGreatWalkForDogOwners() {
        XCTAssertEqual(screen(forecast: goodDay()), ReviewPromptScreen(visible: true, moment: .greatWalk))
    }

    func testPleasantWeatherWithoutADog() {
        XCTAssertEqual(screen(forecast: goodDay(), hasDog: false), ReviewPromptScreen(visible: true, moment: .pleasantWeather))
        XCTAssertEqual(screen(), ReviewPromptScreen(visible: true, moment: .pleasantWeather))
    }

    func testNoMomentInStormsAtNightOrWithOldWeather() {
        XCTAssertEqual(screen(icon: "11d", condition: "Thunderstorm"), ReviewPromptScreen(visible: true))
        XCTAssertEqual(screen(icon: "01n", now: dayStart + 22 * hour), ReviewPromptScreen(visible: true))
        XCTAssertEqual(screen(observedAt: dayStart + 11 * hour, staleErrorKey: "offline"), ReviewPromptScreen(visible: true))
        XCTAssertEqual(screen(isRefreshing: true), ReviewPromptScreen(visible: true))
        XCTAssertEqual(screen(forecastError: true), ReviewPromptScreen(visible: true))
    }

    func testNothingWhenTheScreenIsCovered() {
        XCTAssertEqual(screen(frontmost: false), .hidden)
        XCTAssertEqual(ReviewPromptScreen(screen: .loading, isRefreshing: false, frontmost: true), .hidden)
    }

    // MARK: - The view model

    func testAsksAfterTheDelayAndRecordsIt() async {
        let model = makeModel()
        model.subject.screenChanged(ReviewPromptScreen(visible: true, moment: .greatWalk))
        await model.settle()
        XCTAssertEqual(model.subject.requests, 1)
        XCTAssertEqual(model.logged.first?.0, .greatWalk)
        XCTAssertEqual(model.logged.first?.1, 1)
        XCTAssertEqual(model.slept, [.seconds(3)])
        let history = model.preferences.store.reviewPromptHistory
        XCTAssertEqual(history.requests, 1)
        XCTAssertEqual(history.lastRequestVersion, "1.1")
        // Once per version.
        model.subject.screenChanged(.hidden)
        model.subject.screenChanged(ReviewPromptScreen(visible: true, moment: .pleasantWeather))
        await model.settle()
        XCTAssertEqual(model.subject.requests, 1)
    }

    func testNotIfTheScreenChangesDuringTheDelay() async {
        let model = makeModel(holdSleep: true)
        model.subject.screenChanged(ReviewPromptScreen(visible: true, moment: .greatWalk))
        await model.settle()
        model.subject.screenChanged(ReviewPromptScreen(visible: true))
        model.releaseSleep()
        await model.settle()
        XCTAssertEqual(model.subject.requests, 0)
    }

    func testCountsTheDaysTheWeatherWasShown() {
        let model = makeModel(activeDays: 0)
        model.subject.screenChanged(ReviewPromptScreen(visible: true))
        model.now = date(days: 8)
        model.subject.screenChanged(.hidden)
        model.subject.screenChanged(ReviewPromptScreen(visible: true))
        XCTAssertEqual(model.preferences.store.reviewPromptHistory.activeDays, 2)
    }

    func testAnInterruptionLastsUntilTheNextVisit() async {
        let model = makeModel()
        model.subject.becameInactive()
        model.subject.screenChanged(ReviewPromptScreen(visible: true, moment: .greatWalk))
        await model.settle()
        XCTAssertEqual(model.subject.requests, 0)

        model.subject.enteredBackground()
        model.now = date(days: 7, hours: 14)
        model.subject.becameActive()
        await model.settle()
        XCTAssertEqual(model.subject.requests, 1)
    }

    func testNotInAVisitFromANotification() async {
        let model = makeModel()
        model.notificationOpenedAt = model.now
        model.subject.screenChanged(ReviewPromptScreen(visible: true, moment: .greatWalk))
        await model.settle()
        XCTAssertEqual(model.subject.requests, 0)
    }

    // MARK: - Helpers

    private func screen(
        icon: String = "01d",
        condition: String = "Clear",
        observedAt: Int? = nil,
        now: Int? = nil,
        forecast: [DayForecast]? = nil,
        forecastError: Bool = false,
        staleErrorKey: String? = nil,
        hasDog: Bool = true,
        isRefreshing: Bool = false,
        frontmost: Bool = true
    ) -> ReviewPromptScreen {
        let now = now ?? dayStart + 12 * hour
        let reading = CurrentWeather(
            cityName: "Austin", conditionMain: condition, description: "clear sky", iconCode: icon,
            temperature: 12, feelsLike: 12, tempMin: 8, tempMax: 15, humidityPercent: 50, pressureHpa: 1013,
            windSpeed: 2, windDeg: 90, visibilityMeters: 10_000, cloudPercent: 5, units: .metric,
            sunriseEpoch: dayStart + 7 * hour, sunsetEpoch: dayStart + 17 * hour,
            timezoneOffsetSeconds: 0, observedAtEpoch: observedAt ?? now
        )
        let forecastState: LoadingState<[DayForecast]> = forecastError
            ? .error(errorKey: "network", canRetry: true)
            : forecast.map { .success($0) } ?? .idle
        let weatherScreen = WeatherScreen.make(
            current: .success(reading),
            forecast: forecastState,
            staleErrorKey: staleErrorKey,
            now: Date(timeIntervalSince1970: TimeInterval(now)),
            hasDog: hasDog,
            config: WeatherScreenConfig()
        )
        return ReviewPromptScreen(screen: weatherScreen, isRefreshing: isRefreshing, frontmost: frontmost)
    }

    /// A clear, cool day, every hour fine for a walk.
    private func goodDay() -> [DayForecast] {
        let slots = (0 ..< 24).map { index in
            HourlySlot(
                timeLabel: String(index), iconCode: "01d", description: "clear", temperature: 12,
                feelsLike: 12, windSpeed: 2, windDeg: 0, humidity: 50, pressure: 1013, units: .metric,
                epochSeconds: dayStart + index * hour
            )
        }
        return [DayForecast(
            dateLabel: "Mon, Jan 1", conditionMain: "Clear", description: "clear", iconCode: "01d",
            temperature: 12, feelsLike: 12, tempMin: 8, tempMax: 15, units: .metric, hourlySlots: slots
        )]
    }

    private func makeModel(activeDays: Int = 5, holdSleep: Bool = false) -> ModelHarness {
        let harness = ModelHarness(now: date(days: 7), holdSleep: holdSleep)
        harness.preferences.store.setReviewPromptHistory(ReviewPromptHistory(activeDays: activeDays))
        harness.subject = ReviewPromptViewModel(
            preferences: harness.preferences.store,
            settings: { [on] in on },
            version: "1.1",
            now: { harness.now },
            calendar: calendar,
            notificationOpenedAt: { harness.notificationOpenedAt },
            logRequest: { harness.logged.append(($0, $1)) },
            sleep: { try await harness.sleep($0) },
            installedAt: installed,
            forced: false
        )
        harnesses.append(harness)
        return harness
    }

    override func tearDown() async throws {
        for harness in harnesses { harness.preferences.destroy() }
        harnesses = []
    }

    private var harnesses: [ModelHarness] = []
}

/// The view model with a fake clock and sleep.
@MainActor
private final class ModelHarness {
    let preferences = IsolatedPreferences()
    var subject: ReviewPromptViewModel!
    var now: Date
    var notificationOpenedAt: Date?
    var logged: [(ReviewPromptMoment, Int)] = []
    var slept: [Duration] = []
    private let holdSleep: Bool
    private var held: CheckedContinuation<Void, Never>?

    init(now: Date, holdSleep: Bool) {
        self.now = now
        self.holdSleep = holdSleep
    }

    func sleep(_ duration: Duration) async throws {
        slept.append(duration)
        if holdSleep { await withCheckedContinuation { held = $0 } }
    }

    func releaseSleep() {
        held?.resume()
        held = nil
    }

    /// Lets the pending task run.
    func settle() async {
        for _ in 0 ..< 10 { await Task.yield() }
    }
}
