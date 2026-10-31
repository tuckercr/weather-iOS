import XCTest
@testable import Cats_Dogs

@MainActor
final class NotificationPlannerTests: XCTestCase {
    private let dayStart = fixtureDayStart // Mon 1 Jan 2024, 00:00 UTC
    private let hour = 3600
    private lazy var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func at(_ hours: Double) -> Date { Date(timeIntervalSince1970: TimeInterval(dayStart) + hours * 3600) }

    private func slot(
        _ hourOfDay: Int,
        day: Int = 0,
        rain: Int = 0,
        temp: Double = 15,
        air: AirQuality.Pollutant? = nil
    ) -> HourlySlot {
        var slot = HourlySlot(
            timeLabel: hourOfDay < 12 ? "\(hourOfDay) AM" : hourOfDay == 12 ? "12 PM" : "\(hourOfDay - 12) PM",
            iconCode: rain > 50 ? "10d" : "01d",
            description: rain > 50 ? "Light rain" : "Clear sky",
            temperature: temp,
            feelsLike: temp,
            windSpeed: 2,
            windDeg: 0,
            humidity: 50,
            pressure: 1013,
            units: .metric,
            precipitationChance: rain,
            localHour: hourOfDay,
            epochSeconds: dayStart + day * 24 * hour + hourOfDay * hour
        )
        // Unhealthy on the US index, the default bad-air band.
        slot.airQuality = air.map { AirQuality(index: 160, scale: .us, mainPollutant: $0) }
        return slot
    }

    private func day(_ slots: [HourlySlot], rainChance: Int = 0, quarters: [QuarterHour]? = nil) -> DayForecast {
        DayForecast(
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
            precipitationChance: rainChance,
            quarterHours: quarters
        )
    }

    private func plan(
        _ forecast: [DayForecast],
        now: Date? = nil,
        settings: NotificationSettings = NotificationSettings(),
        lastRainAlert: RainAlertRecord? = nil
    ) -> [PlannedNotification] {
        NotificationPlanner.plan(
            weather: sampleWeather(),
            forecast: forecast,
            now: now ?? at(6),
            settings: settings,
            lastRainAlert: lastRainAlert,
            calendar: calendar
        )
    }

    private let dry = (6 ... 20).map { $0 }

    // MARK: - Morning briefing

    func testAWeekOfBriefingsAt830() {
        let briefings = plan([day(dry.map { slot($0) })]).filter { $0.kind == .morningBriefing }

        XCTAssertEqual(briefings.count, 7)
        XCTAssertEqual(briefings.first?.date, at(8.5))
        XCTAssertEqual(briefings.last?.date, at(6 * 24 + 8.5))
        XCTAssertEqual(Set(briefings.map(\.identifier)).count, 7)
    }

    func testTheBriefingIsTheHourAt830AndTheDaysHighAndLow() {
        let first = plan([day(dry.map { slot($0) })]).first { $0.identifier == "briefing_0" }

        XCTAssertEqual(first?.title, "15° and clear in London")
        XCTAssertEqual(first?.body, "High 18°, low 10°.")
    }

    func testTheDaysRainChanceIsMentionedFrom40PercentRounded() {
        let wet = plan([day(dry.map { slot($0) }, rainChance: 57)]).first { $0.identifier == "briefing_0" }
        XCTAssertEqual(wet?.body, "High 18°, low 10°, 60% chance of rain.")
        let damp = plan([day(dry.map { slot($0) }, rainChance: 34)]).first { $0.identifier == "briefing_0" }
        XCTAssertEqual(damp?.body, "High 18°, low 10°.")
    }

    func testBeyondTheForecastTheBriefingIsGeneric() {
        let later = plan([day(dry.map { slot($0) })]).first { $0.identifier == "briefing_3" }

        XCTAssertEqual(later?.title, NotificationPlanner.fallbackBriefing.title)
        XCTAssertEqual(later?.body, NotificationPlanner.fallbackBriefing.body)
    }

    func testWithADogTheBriefingSaysWhenToWalk() {
        let withDog = NotificationSettings(hasDog: true)
        func body(_ slots: [HourlySlot]) -> String? {
            plan([day(slots)], settings: withDog).first { $0.identifier == "briefing_0" }?.body
        }

        XCTAssertEqual(body(dry.map { slot($0) }), "High 18°, low 10°. Sunny says now's a great time for a walk.")
        XCTAssertEqual(body(dry.map { slot($0, rain: $0 < 11 ? 90 : 0) }), "High 18°, low 10°. Sunny's picked 11 AM for a walk.")
        XCTAssertEqual(body(dry.map { slot($0, rain: 90) }), "High 18°, low 10°. Not a good day for walkies.")
    }

    func testWithADogTheBriefingSaysWhenBadAirShortensTheWalk() {
        let withDog = NotificationSettings(hasDog: true)
        func body(_ slots: [HourlySlot]) -> String? {
            plan([day(slots)], settings: withDog).first { $0.identifier == "briefing_0" }?.body
        }

        XCTAssertEqual(
            body(dry.map { slot($0, air: $0 >= 12 ? .fineParticles : nil) }),
            "High 18°, low 10°. Sunny says now's a great time for a walk. Smoky air today, so keep it short."
        )
        XCTAssertEqual(
            body(dry.map { slot($0, air: $0 < 11 ? .ozone : nil) }),
            "High 18°, low 10°. Sunny's picked 11 AM for a walk. High ozone today, so keep it short."
        )
        XCTAssertEqual(
            body(dry.map { slot($0, air: .nitrogenDioxide) }),
            "High 18°, low 10°. Poor air today, so potty breaks only."
        )
    }

    func testBadAirAtNightOrOnAnotherDayIsNotMentioned() {
        let withDog = NotificationSettings(hasDog: true)
        let slots = dry.map { slot($0) } + [slot(23, air: .fineParticles), slot(10, day: 1, air: .fineParticles)]
        XCTAssertEqual(
            plan([day(slots)], settings: withDog).first { $0.identifier == "briefing_0" }?.body,
            "High 18°, low 10°. Sunny says now's a great time for a walk."
        )
    }

    func testTheBriefingSwitchesQueueNoBriefings() {
        XCTAssertTrue(plan([day(dry.map { slot($0) })], settings: NotificationSettings(morningBriefing: false)).isEmpty)
        XCTAssertTrue(plan([day(dry.map { slot($0) })], settings: NotificationSettings(briefingRemotelyEnabled: false)).isEmpty)
    }

    // MARK: - Walk time

    func testTheWalkNudgeIsAtTheDaysFirstGoodHour() {
        let walks = plan(
            [day(dry.map { slot($0, rain: $0 < 11 ? 90 : 0) })],
            settings: NotificationSettings(walkTime: true, hasDog: true)
        ).filter { $0.kind == .walkTime }

        XCTAssertEqual(walks.map(\.date), [at(11)])
        XCTAssertEqual(walks.first?.title, "Time for a walk")
        XCTAssertEqual(walks.first?.body, "15° and clear in London. Sunny's waiting by the door.")
    }

    func testOnABadAirDayTheWalkNudgeSaysToKeepItShort() {
        let walks = plan(
            [day(dry.map { slot($0, air: $0 < 11 ? .fineParticles : nil) })],
            settings: NotificationSettings(walkTime: true, hasDog: true)
        ).filter { $0.kind == .walkTime }

        XCTAssertEqual(walks.map(\.date), [at(11)])
        XCTAssertEqual(walks.first?.body, "15° and clear in London. Sunny's waiting by the door. Smoky air today, so a short one.")
    }

    func testWhenTheBriefingHourIsGoodTheBriefingSaysSoOrWithoutItTheNudgeGoesThen() {
        let good = [day(dry.map { slot($0) })]
        XCTAssertTrue(plan(good, settings: NotificationSettings(walkTime: true, hasDog: true)).filter { $0.kind == .walkTime }.isEmpty)

        let walks = plan(good, settings: NotificationSettings(morningBriefing: false, walkTime: true, hasDog: true))
        XCTAssertEqual(walks.map(\.date), [at(8.5)])
    }

    func testWithoutADogThereIsNoWalkNudgeEvenWithItsSwitchOn() {
        let laterGood = [day(dry.map { slot($0, rain: $0 < 11 ? 90 : 0) })]
        XCTAssertTrue(plan(laterGood, settings: NotificationSettings(walkTime: true)).filter { $0.kind == .walkTime }.isEmpty)
        XCTAssertTrue(plan(laterGood, settings: NotificationSettings(morningBriefing: false, walkTime: true))
            .filter { $0.kind == .walkTime }.isEmpty)
    }

    func testRemoteConfigCanSwitchOffWalkNudgesAndRainAlertsForEveryone() {
        let laterGood = [day(dry.map { slot($0, rain: $0 < 11 ? 90 : 0) })]
        XCTAssertTrue(plan(laterGood, settings: NotificationSettings(walkTime: true, hasDog: true, walkTimeRemotelyEnabled: false))
            .filter { $0.kind == .walkTime }.isEmpty)
        XCTAssertTrue(plan(rainFrom(8.5), now: at(7), settings: NotificationSettings(rain: true, rainRemotelyEnabled: false))
            .filter { $0.kind == .rain }.isEmpty)
    }

    func testNoWalkNudgeWithoutAGoodHourOrWithItsSwitchOff() {
        XCTAssertTrue(plan([day(dry.map { slot($0, rain: 90) })], settings: NotificationSettings(walkTime: true, hasDog: true))
            .filter { $0.kind == .walkTime }.isEmpty)
        XCTAssertTrue(plan([day(dry.map { slot($0, rain: $0 < 11 ? 90 : 0) })])
            .filter { $0.kind == .walkTime }.isEmpty)
    }

    func testEachKindHasItsOwnNotificationCenterGroupNamedLikeAndroidsChannels() {
        XCTAssertEqual(WeatherNotificationScheduler.threadIdentifier(.morningBriefing), "morning_briefing")
        XCTAssertEqual(WeatherNotificationScheduler.threadIdentifier(.walkTime), "walk_time")
        XCTAssertEqual(WeatherNotificationScheduler.threadIdentifier(.rain), "rain_alerts")
    }

    // MARK: - Rain alerts

    /// Dry, then rain from `startHours` after midnight, in 15-minute steps from 6 AM.
    private func rainFrom(_ startHours: Double) -> [DayForecast] {
        let quarters = (0 ..< 16).map { i -> QuarterHour in
            let start = dayStart + 6 * hour + i * 900
            return QuarterHour(epochSeconds: start, precipitationMm: Double(start) >= Double(dayStart) + startHours * 3600 ? 0.5 : 0)
        }
        return [day(dry.map { slot($0) }, quarters: quarters)]
    }

    func testTheRainAlertIsAnHourBeforeTheRain() {
        let alert = plan(rainFrom(8.5), now: at(7), settings: NotificationSettings(morningBriefing: false, rain: true, hasDog: true)).first

        XCTAssertEqual(alert?.kind, .rain)
        XCTAssertEqual(alert?.date, at(7.5))
        XCTAssertTrue(alert?.title.hasPrefix("Rain starting around 8:30") == true)
        XCTAssertEqual(alert?.body, "Rain on the way in London. Walk now or wait it out.")
        XCTAssertEqual(alert?.rainStart, dayStart + 8 * hour + 1800)
    }

    func testWithoutADogTheRainAlertDoesNotMentionTheWalk() {
        let alert = plan(rainFrom(8.5), now: at(7), settings: NotificationSettings(morningBriefing: false, rain: true)).first

        XCTAssertEqual(alert?.body, "Rain on the way in London. Misty's staying in.")
    }

    func testRainSoonerThanAnHourAlertsRightAway() {
        let alert = plan(rainFrom(7.5), now: at(7), settings: NotificationSettings(morningBriefing: false, rain: true)).first

        XCTAssertEqual(alert?.date, at(7).addingTimeInterval(60))
    }

    func testNoRainAlertAtNightOrWithItsSwitchOff() {
        // Rain at 6:30 AM: the alert would go before 7 AM.
        XCTAssertTrue(plan(rainFrom(6.5), now: at(5), settings: NotificationSettings(morningBriefing: false, rain: true)).isEmpty)
        XCTAssertTrue(plan(rainFrom(8.5), now: at(7), settings: NotificationSettings(morningBriefing: false)).isEmpty)
    }

    func testRainAlreadyAlertedAboutIsNotAlertedAgain() {
        let settings = NotificationSettings(morningBriefing: false, rain: true)
        let gone = RainAlertRecord(rainStart: dayStart + 8 * hour + 1800, fireDate: at(6.9))
        XCTAssertTrue(plan(rainFrom(8.5), now: at(7), settings: settings, lastRainAlert: gone).isEmpty)

        // Still waiting to go off: it's queued again (replacing itself).
        let pending = RainAlertRecord(rainStart: dayStart + 8 * hour + 1800, fireDate: at(7.5))
        XCTAssertEqual(plan(rainFrom(8.5), now: at(7), settings: settings, lastRainAlert: pending).count, 1)
    }
}
