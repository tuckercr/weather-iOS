import UIKit
import UserNotifications
import XCTest
@testable import Cats_Dogs

@MainActor
final class WeatherNotificationSchedulerTests: XCTestCase {
    private let dayStart = fixtureDayStart // Mon 1 Jan 2024, 00:00 UTC
    private let hour = 3600
    private let london = SavedLocation(label: "London, GB", latitude: 51.5074, longitude: -0.1278)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var suite: ThrowawayDefaults!
    private var preferences: PreferencesStore!
    private var center: FakeNotificationCentre!
    private var pictures: StubPetPictures!

    override func setUp() async throws {
        suite = ThrowawayDefaults()
        preferences = PreferencesStore(defaults: suite.defaults)
        center = FakeNotificationCentre()
        pictures = StubPetPictures()
    }

    override func tearDown() async throws {
        suite.destroy()
    }

    private func at(_ hours: Double) -> Date { Date(timeIntervalSince1970: TimeInterval(dayStart) + hours * 3600) }

    private func makeScheduler(now: Double = 7, remoteConfig: FakeRemoteConfig? = nil) -> WeatherNotificationScheduler {
        WeatherNotificationScheduler(
            center: center,
            preferences: preferences,
            remoteConfig: remoteConfig ?? FakeRemoteConfig(),
            pictures: pictures,
            now: { [unowned self] in at(now) },
            calendar: calendar
        )
    }

    /// London cached at 6:00: rain until 11:00 (so the walk is at 11:00), and in the 15-minute
    /// forecast rain from 8:30 (so the rain alert is at 7:30). Every switch on, with a dog.
    private func cacheLondonAndSwitchEverythingOn() {
        preferences.setSavedLocations([london])
        preferences.setShowWalkCard(true)
        preferences.setNotifyMorningBriefing(true)
        preferences.setNotifyWalkTime(true)
        preferences.setNotifyRain(true)
        let slots = (6 ... 20).map { hourOfDay in
            HourlySlot(
                timeLabel: "\(hourOfDay)",
                iconCode: hourOfDay < 11 ? "10d" : "01d",
                description: hourOfDay < 11 ? "Light rain" : "Clear sky",
                temperature: 15,
                feelsLike: 15,
                windSpeed: 2,
                windDeg: 0,
                humidity: 50,
                pressure: 1013,
                units: .metric,
                precipitationChance: hourOfDay < 11 ? 90 : 0,
                localHour: hourOfDay,
                epochSeconds: dayStart + hourOfDay * hour
            )
        }
        let quarters = (0 ..< 16).map { i -> QuarterHour in
            let start = dayStart + 6 * hour + i * 900
            return QuarterHour(epochSeconds: start, precipitationMm: start >= dayStart + 8 * hour + 1800 ? 0.5 : 0)
        }
        let day = DayForecast(
            dateLabel: "Mon, Jan 1",
            conditionMain: "Clear",
            description: "clear sky",
            iconCode: "01d",
            temperature: 15,
            feelsLike: 15,
            tempMin: 10,
            tempMax: 18,
            units: .metric,
            hourlySlots: slots,
            precipitationChance: 0,
            quarterHours: quarters
        )
        var weather = sampleWeather()
        weather.observedAtEpoch = Int(at(6).timeIntervalSince1970)
        preferences.setCachedWeather(weather, for: london.cacheKey)
        preferences.setCachedForecast([day], for: london.cacheKey, fetchedAt: at(6))
    }

    func testItRemovesOnlyThisAppsPendingNotifications() async {
        center.queue("briefing_3", "weather_daily_9", "walk_1", "rain_next", "someone_else")

        await makeScheduler().scheduleNotifications()

        XCTAssertEqual(Set(center.removed), ["briefing_3", "weather_daily_9", "walk_1", "rain_next"])
        XCTAssertEqual(center.identifiers, ["someone_else"], "nothing to plan without a city, and the rest is left alone")
    }

    func testNothingIsQueuedWhenNotAuthorizedOrWithoutACity() async {
        cacheLondonAndSwitchEverythingOn()
        for status in [UNAuthorizationStatus.denied, .notDetermined] {
            center.status = status
            await makeScheduler().scheduleNotifications()
            XCTAssertTrue(center.identifiers.isEmpty, "\(status.rawValue)")
        }

        center.status = .authorized
        preferences.setSavedLocations([])
        await makeScheduler().scheduleNotifications()
        XCTAssertTrue(center.identifiers.isEmpty)
    }

    func testProvisionalAuthorizationQueuesThePlan() async {
        cacheLondonAndSwitchEverythingOn()
        center.status = .provisional

        await makeScheduler().scheduleNotifications()

        XCTAssertFalse(center.identifiers.isEmpty)
    }

    func testItQueuesThePlanWithItsIdentifiersTimesGroupsAndPictures() async {
        cacheLondonAndSwitchEverythingOn()

        await makeScheduler().scheduleNotifications()

        XCTAssertEqual(center.identifiers, ["rain_next", "briefing_0", "walk_0"] + (1 ... 6).map { "briefing_\($0)" })
        let rain = center.request("rain_next")
        XCTAssertEqual(rain?.content.title.hasPrefix("Rain starting around 8:30"), true)
        XCTAssertEqual(rain?.content.body, "Rain on the way in London. Walk now or wait it out.")
        XCTAssertEqual(rain?.content.threadIdentifier, "rain_alerts")
        XCTAssertEqual(rain?.content.categoryIdentifier, "rain_alerts")
        XCTAssertEqual(rain?.content.sound, .default)
        XCTAssertEqual(rain?.content.attachments.map(\.identifier), ["pets"])
        let rainTrigger = rain?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(rainTrigger?.dateComponents.hour, 7)
        XCTAssertEqual(rainTrigger?.dateComponents.minute, 30)
        XCTAssertEqual(rainTrigger?.repeats, false)

        let walk = center.request("walk_0")
        XCTAssertEqual(walk?.content.title, "Time for a walk")
        XCTAssertEqual(walk?.content.threadIdentifier, "walk_time")
        XCTAssertEqual((walk?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour, 11)

        let briefing = center.request("briefing_0")
        XCTAssertEqual(briefing?.content.threadIdentifier, "morning_briefing")
        XCTAssertEqual(briefing?.content.categoryIdentifier, "morning_briefing")
        XCTAssertEqual((briefing?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.day, 1)
        XCTAssertEqual(briefing?.content.attachments.count, 1, "the hour's weather, so the pets in its mood")
        // Beyond the cached forecast the briefing is generic, with no picture.
        XCTAssertEqual(center.request("briefing_6")?.content.body, "Tap to see today's weather.")
        XCTAssertEqual(center.request("briefing_6")?.content.attachments.count, 0)
        XCTAssertEqual((center.request("briefing_6")?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.day, 7)

        XCTAssertEqual(pictures.drawn.count, 3)
        XCTAssertTrue(pictures.drawn.contains { $0.mood == .rain })
        XCTAssertTrue(pictures.drawn.contains { $0.mood == .sunny })
        XCTAssertFalse(pictures.drawn.contains { $0.southernHemisphere })
    }

    func testDownSouthThePicturesAreDrawnForTheSouthernHemisphere() async throws {
        cacheLondonAndSwitchEverythingOn()
        let sydney = SavedLocation(label: "Sydney, AU", latitude: -33.87, longitude: 151.21)
        let weather = try XCTUnwrap(preferences.cachedWeather(for: london.cacheKey))
        let forecast = try XCTUnwrap(preferences.cachedForecast(for: london.cacheKey))
        preferences.setSavedLocations([sydney])
        preferences.setCachedWeather(weather, for: sydney.cacheKey)
        preferences.setCachedForecast(forecast, for: sydney.cacheKey, fetchedAt: at(6))

        await makeScheduler().scheduleNotifications()

        XCTAssertFalse(pictures.drawn.isEmpty)
        XCTAssertTrue(pictures.drawn.allSatisfy(\.southernHemisphere))
    }

    func testRemoteConfigSwitchesTheKindsOffForEveryone() async {
        cacheLondonAndSwitchEverythingOn()

        await makeScheduler(remoteConfig: FakeRemoteConfig(briefing: false, walkTime: false, rain: false)).scheduleNotifications()

        XCTAssertTrue(center.identifiers.isEmpty)
    }

    func testItRecordsTheWalkNudgesTodaysThatHaveGoneOffAndTheRainAlert() async {
        cacheLondonAndSwitchEverythingOn()
        // Yesterday's went off, and one queued for later is replaced by the new plan.
        preferences.setWalkNudgeDates([at(-13), at(12)])

        await makeScheduler().scheduleNotifications()

        XCTAssertEqual(preferences.walkNudgeDates, [at(11)])
        XCTAssertEqual(preferences.lastRainAlert, RainAlertRecord(rainStart: dayStart + 8 * hour + 1800, fireDate: at(7.5)))
    }

    func testANudgeThatHasGoneOffTodayStaysOnRecordAndIsNotSentAgain() async {
        cacheLondonAndSwitchEverythingOn()
        preferences.setWalkNudgeDates([at(6.5)])

        await makeScheduler().scheduleNotifications()

        XCTAssertNil(center.request("walk_0"))
        XCTAssertEqual(preferences.walkNudgeDates, [at(6.5)])
    }

    func testARainAlertThatHasGoneOffIsNotQueuedAgainAndStaysOnRecord() async {
        cacheLondonAndSwitchEverythingOn()
        let gone = RainAlertRecord(rainStart: dayStart + 8 * hour + 1800, fireDate: at(6.9))
        preferences.setLastRainAlert(gone)

        await makeScheduler().scheduleNotifications()

        XCTAssertNil(center.request("rain_next"))
        XCTAssertEqual(preferences.lastRainAlert, gone)
    }
}

@MainActor
final class FakeNotificationCentre: UserNotificationCentre {
    var status: UNAuthorizationStatus = .authorized
    private(set) var pending: [UNNotificationRequest] = []
    private(set) var removed: [String] = []

    var identifiers: [String] { pending.map(\.identifier) }

    func request(_ identifier: String) -> UNNotificationRequest? {
        pending.first { $0.identifier == identifier }
    }

    func queue(_ identifiers: String...) {
        for identifier in identifiers {
            pending.append(UNNotificationRequest(identifier: identifier, content: UNNotificationContent(), trigger: nil))
        }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { status == .authorized }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func add(_ request: UNNotificationRequest) async throws {
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func pendingRequestIdentifiers() async -> [String] { identifiers }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removed += identifiers
        pending.removeAll { identifiers.contains($0.identifier) }
    }
}

@MainActor
struct FakeRemoteConfig: NotificationRemoteConfig {
    var dailyWeatherNotificationsEnabled: Bool
    var walkTimeNotificationsEnabled: Bool
    var rainNotificationsEnabled: Bool
    var petWeatherThresholds = PetWeatherThresholds.standard

    init(briefing: Bool = true, walkTime: Bool = true, rain: Bool = true) {
        dailyWeatherNotificationsEnabled = briefing
        walkTimeNotificationsEnabled = walkTime
        rainNotificationsEnabled = rain
    }
}

/// A 1-pixel PNG, so the attachment is real, and a record of what was drawn.
@MainActor
final class StubPetPictures: PetPictureRendering {
    private(set) var drawn: [(mood: PetMood, southernHemisphere: Bool)] = []
    private let pixel = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { context in
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func png(mood: PetMood, southernHemisphere: Bool) -> Data? {
        drawn.append((mood, southernHemisphere))
        return pixel
    }
}
