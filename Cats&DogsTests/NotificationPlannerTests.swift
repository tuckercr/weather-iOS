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
        air: AirQuality.Pollutant? = nil,
        wind: Double = 2,
        storms: Bool = false
    ) -> HourlySlot {
        var slot = HourlySlot(
            timeLabel: hourOfDay < 12 ? "\(hourOfDay) AM" : hourOfDay == 12 ? "12 PM" : "\(hourOfDay - 12) PM",
            iconCode: storms ? "11d" : rain > 50 ? "10d" : "01d",
            description: storms ? "Thunderstorm" : rain > 50 ? "Light rain" : "Clear sky",
            temperature: temp,
            feelsLike: temp,
            windSpeed: wind,
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
        fetchedAt: Date? = nil,
        settings: NotificationSettings = NotificationSettings(),
        lastRainAlert: RainAlertRecord? = nil,
        walkNudgesGoneOff: [Date] = [],
        forecastFetchedAt: Date? = nil
    ) -> [PlannedNotification] {
        var weather = sampleWeather()
        weather.observedAtEpoch = fetchedAt.map { Int($0.timeIntervalSince1970) }
        return NotificationPlanner.plan(
            weather: weather,
            forecast: forecast,
            now: now ?? at(6),
            settings: settings,
            lastRainAlert: lastRainAlert,
            walkNudgesGoneOff: walkNudgesGoneOff,
            forecastFetchedAt: forecastFetchedAt,
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

    func testTheBriefingsHighAndLowTakeInTheHoursTemperatureAsTheHeroDoes() {
        // Colder at 8:30 than the day's forecast low, as the hero's would show it.
        let cold = plan([day(dry.map { slot($0, temp: $0 == 8 ? 7 : 15) })]).first { $0.identifier == "briefing_0" }

        XCTAssertEqual(cold?.title, "7° and clear in London")
        XCTAssertEqual(cold?.body, "High 18°, low 7°.")
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

    private func days(_ count: Int, rain: Int = 0) -> [DayForecast] {
        (0 ..< count).map { offset in day(dry.map { slot($0, day: offset, rain: rain) }) }
    }

    func testABriefingADayAfterTheFetchGivesOnlyTheDaysForecastAndAfter3DaysNoWeather() {
        // Fetched at 6:00 on day 0, with a forecast to day 4.
        let briefings = plan(days(5)).filter { $0.kind == .morningBriefing }

        XCTAssertEqual(briefings[0].title, "15° and clear in London")
        for later in briefings[1 ... 2] {
            XCTAssertEqual(later.title, "Today's forecast for London")
            XCTAssertEqual(later.body, "High 18°, low 10°.")
        }
        for later in briefings[3...] {
            XCTAssertEqual(later.title, NotificationPlanner.fallbackBriefing.title)
            XCTAssertEqual(later.body, NotificationPlanner.fallbackBriefing.body)
        }
    }

    func testTodaysForecastIsTheCitysDayNotTheDevicesForACityToTheWest() {
        // The device is on UTC; the city is 6 hours behind, so its days run 06:00 to 06:00 UTC and
        // the 8:30 briefing (02:30 there) falls on the city's day, not the one before it.
        var weather = sampleWeather(timeZoneOffset: -6 * hour)
        weather.observedAtEpoch = Int(at(6).timeIntervalSince1970)
        let cityDays = (0 ..< 3).map { offset in
            DayForecast(
                dateLabel: "Day \(offset)",
                conditionMain: "Clear",
                description: "clear sky",
                iconCode: "01d",
                temperature: 15,
                feelsLike: 15,
                tempMin: Double(offset * 10),
                tempMax: Double(offset * 10 + 5),
                units: .metric,
                hourlySlots: (0 ..< 24).map { slot($0 + 6, day: offset) },
                precipitationChance: 0
            )
        }
        let briefings = NotificationPlanner.plan(
            weather: weather, forecast: cityDays, now: at(6), settings: NotificationSettings(), calendar: calendar
        ).filter { $0.kind == .morningBriefing }

        // Day 1's 8:30 is past a day after the fetch, so it gives the city's day 1 high and low.
        XCTAssertEqual(briefings[1].title, "Today's forecast for London")
        XCTAssertEqual(briefings[1].body, "High 15°, low 10°.")
    }

    func testFreshnessCountsFromTheFetchNotFromThePlan() {
        // Replanned at 6:00 from a cache fetched at 6:00 the day before: 8:30 is past a day old.
        let first = plan(days(5), fetchedAt: at(-18)).first { $0.identifier == "briefing_0" }

        XCTAssertEqual(first?.title, "Today's forecast for London")
    }

    func testFreshnessCountsFromTheForecastsFetchNotTheReading() {
        // A fresh reading with a forecast left from 3 days ago (its fetch failed since): no weather.
        let stale = plan(days(5), now: at(6), fetchedAt: at(6), forecastFetchedAt: at(-66)).first { $0.identifier == "briefing_0" }
        XCTAssertEqual(stale?.title, NotificationPlanner.fallbackBriefing.title)

        // Refreshed at 8:32 after the briefing, with OpenWeather's reading from 8:24: tomorrow's
        // 8:30 is under a day after the fetch, so it still gives the hour's weather.
        let tomorrow = plan(days(5), now: at(8.55), fetchedAt: at(8.4), forecastFetchedAt: at(8.53))
            .first { $0.identifier == "briefing_0" }
        XCTAssertEqual(tomorrow?.date, at(32.5))
        XCTAssertEqual(tomorrow?.title, "15° and clear in London")
    }

    func testTheBriefingPictureIsTheForecastAt830NotTheWeatherWhenPlanned() {
        // The weather when planned is clear; 8:00 to 9:00 is forecast rain.
        let briefings = plan(days(2, rain: 90)).filter { $0.kind == .morningBriefing }

        XCTAssertEqual(briefings[0].mood, .rain)
        // Only the briefing that gives the hour's weather has a picture.
        XCTAssertNil(briefings[1].mood)
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
        XCTAssertEqual(
            body(dry.map { slot($0, air: .coarseParticles) }),
            "High 18°, low 10°. Dusty air today, so potty breaks only."
        )
    }

    private func briefingBody(_ slots: [HourlySlot], hasDog: Bool) -> String? {
        plan([day(slots)], settings: NotificationSettings(hasDog: hasDog)).first { $0.identifier == "briefing_0" }?.body
    }

    func testHurricaneForceWindAt830TakesTheWalksPlaceForEveryone() {
        // 35 m/s is Beaufort 12.
        let slots = dry.map { slot($0, wind: $0 == 8 ? 35 : 2) }
        for hasDog in [true, false] {
            XCTAssertEqual(
                briefingBody(slots, hasDog: hasDog),
                "High 18°, low 10°. Hurricane force winds. Stay inside, away from the windows."
            )
        }
    }

    func testHurricaneForceWindLaterTodayTakesTheWalksPlaceForEveryone() {
        // Storms earlier, smoke all day and a walk at 8: the hurricane is all it says.
        let slots = dry.map { slot($0, rain: $0 == 11 ? 80 : 0, air: .fineParticles, wind: $0 >= 14 ? 35 : 2, storms: $0 == 11) }
        for hasDog in [true, false] {
            XCTAssertEqual(
                briefingBody(slots, hasDog: hasDog),
                "High 18°, low 10°. Hurricane force winds from 2 PM. Get everyone inside before then."
            )
        }
        // Tomorrow's isn't today's news.
        XCTAssertEqual(
            briefingBody(dry.map { slot($0) } + [slot(14, day: 1, wind: 35)], hasDog: false),
            "High 18°, low 10°."
        )
    }

    func testLikelyStormsLaterTodayComeBeforeTheWalk() {
        let slots = dry.map { slot($0, rain: $0 >= 16 ? 70 : 0, storms: $0 >= 16) }
        XCTAssertEqual(
            plan([day(slots, rainChance: 70)], settings: NotificationSettings(hasDog: true)).first { $0.identifier == "briefing_0" }?.body,
            "High 18°, low 10°, 70% chance of rain. Storms from 4 PM. Sunny says now's a great time for a walk."
        )
        XCTAssertEqual(briefingBody(slots, hasDog: false), "High 18°, low 10°. Storms from 4 PM.")
        // Maybe storms aren't worth a line.
        XCTAssertEqual(briefingBody(dry.map { slot($0, rain: $0 >= 16 ? 40 : 0, storms: $0 >= 16) }, hasDog: false), "High 18°, low 10°.")
    }

    func testStormsInTheHourAt830AreLeftToTheTitle() {
        let slots = dry.map { slot($0, rain: $0 == 8 ? 80 : 0, storms: $0 == 8) }
        let briefing = plan([day(slots)], settings: NotificationSettings(hasDog: true)).first { $0.identifier == "briefing_0" }
        XCTAssertEqual(briefing?.title, "15° and thunderstorm in London")
        XCTAssertEqual(briefing?.body, "High 18°, low 10°. Sunny's picked 9 AM for a walk.")
        XCTAssertEqual(briefingBody(slots, hasDog: false), "High 18°, low 10°.")
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
        // Rain until 11:00, smoke from 14:00: the walk at 11:00 is told to keep it short.
        let walks = plan(
            [day(dry.map { slot($0, rain: $0 < 11 ? 90 : 0, air: $0 >= 14 ? .fineParticles : nil) })],
            settings: NotificationSettings(walkTime: true, hasDog: true)
        ).filter { $0.kind == .walkTime }

        XCTAssertEqual(walks.map(\.date), [at(11)])
        XCTAssertEqual(walks.first?.body, "15° and clear in London. Sunny's waiting by the door. Smoky air today, so a short one.")
    }

    func testHurricaneForceWindSoonAfterTheWalkIsInTheNudge() {
        // Rain until 11:00, hurricane force wind from 13:00: the walk at 11:00 is told to be back.
        let walks = plan(
            [day(dry.map { slot($0, rain: $0 < 11 ? 90 : 0, wind: $0 >= 13 ? 35 : 2) })],
            settings: NotificationSettings(walkTime: true, hasDog: true)
        ).filter { $0.kind == .walkTime }

        XCTAssertEqual(walks.map(\.date), [at(11)])
        XCTAssertEqual(walks.first?.title, "Time for a walk")
        XCTAssertEqual(walks.first?.body, "15° and clear in London. Sunny's waiting by the door. Hurricane force winds from 1 PM, so be back by then.")
    }

    func testStormsSoonAfterTheWalkReplaceTheBadAirSentence() {
        // Rain until 11:00, likely storms at 13:00 and smoke from 14:00: one sentence, the storms.
        let walks = plan(
            [day(dry.map { slot($0, rain: $0 < 11 ? 90 : $0 == 13 ? 70 : 0, air: $0 >= 14 ? .fineParticles : nil, storms: $0 == 13) })],
            settings: NotificationSettings(walkTime: true, hasDog: true)
        ).filter { $0.kind == .walkTime }

        XCTAssertEqual(walks.map(\.date), [at(11)])
        XCTAssertEqual(walks.first?.body, "15° and clear in London. Sunny's waiting by the door. Storms from 1 PM, so be back by then.")
    }

    private func walkWarning(after walkHour: Int, _ slots: [HourlySlot]) -> WalkWarning? {
        NotificationPlanner.walkNudgeWarning(after: at(Double(walkHour)), slots: slots, thresholds: .standard, calendar: calendar)
    }

    func testTheWalkNudgeWarnsOfHurricaneForceWindWithinThreeHours() {
        XCTAssertEqual(walkWarning(after: 11, dry.map { slot($0, wind: $0 >= 13 ? 35 : 2) }), .hurricane(from: "1 PM"))
        // Three hours after the walk hour starts still counts.
        XCTAssertEqual(walkWarning(after: 11, dry.map { slot($0, wind: $0 >= 14 ? 35 : 2) }), .hurricane(from: "2 PM"))
    }

    func testTheWalkNudgeWarnsOfLikelyStormsWithinThreeHours() {
        XCTAssertEqual(walkWarning(after: 11, dry.map { slot($0, rain: $0 == 13 ? 70 : 0, storms: $0 == 13) }), .storms(from: "1 PM"))
        // Maybe storms aren't worth it.
        XCTAssertNil(walkWarning(after: 11, dry.map { slot($0, rain: $0 == 13 ? 40 : 0, storms: $0 == 13) }))
    }

    func testHurricaneForceWindWinsOverEarlierStorms() {
        let slots = dry.map { slot($0, rain: $0 == 12 ? 70 : 0, wind: $0 >= 14 ? 35 : 2, storms: $0 == 12) }
        XCTAssertEqual(walkWarning(after: 11, slots), .hurricane(from: "2 PM"))
    }

    func testNothingMoreThanThreeHoursAfterTheWalk() {
        XCTAssertNil(walkWarning(after: 11, dry.map { slot($0, rain: $0 >= 15 ? 70 : 0, wind: $0 >= 15 ? 35 : 2, storms: $0 >= 15) }))
    }

    func testNothingOnTheNextDay() {
        // A walk at 22:00, a hurricane from midnight.
        let slots = (6 ... 23).map { slot($0) } + (0 ... 3).map { slot($0, day: 1, wind: 35) }
        XCTAssertNil(walkWarning(after: 22, slots))
        // The same day's last hour still counts.
        let lateHurricane = (6 ... 23).map { slot($0, wind: $0 == 23 ? 35 : 2) } + (0 ... 3).map { slot($0, day: 1) }
        XCTAssertEqual(walkWarning(after: 22, lateHurricane), .hurricane(from: "11 PM"))
    }

    func testHoursWithoutATimeDontCount() {
        var untimed = slot(12, wind: 35)
        untimed.epochSeconds = nil
        XCTAssertNil(walkWarning(after: 11, [slot(11), untimed, slot(13)]))
    }

    func testSmokeThatClearsBeforeTheWalkIsNotMentioned() {
        // Smoke until 11:00, as Android words it at the walk time: the hours from then on are clean.
        let walks = plan(
            [day(dry.map { slot($0, air: $0 < 11 ? .fineParticles : nil) })],
            settings: NotificationSettings(walkTime: true, hasDog: true)
        ).filter { $0.kind == .walkTime }

        XCTAssertEqual(walks.map(\.date), [at(11)])
        XCTAssertEqual(walks.first?.body, "15° and clear in London. Sunny's waiting by the door.")
    }

    func testWhenTheBriefingHourIsGoodTheBriefingSaysSoOrWithoutItTheNudgeGoesThen() {
        let good = [day(dry.map { slot($0) })]
        XCTAssertTrue(plan(good, settings: NotificationSettings(walkTime: true, hasDog: true)).filter { $0.kind == .walkTime }.isEmpty)

        let walks = plan(good, settings: NotificationSettings(morningBriefing: false, walkTime: true, hasDog: true))
        XCTAssertEqual(walks.map(\.date), [at(8.5)])
    }

    func testNoWalkNudgeOffAForecastMoreThanADayOld() {
        // A good hour at 11:00 on both days: tomorrow's is 29 hours after the 6:00 fetch.
        let twoDays = (0 ..< 2).map { offset in day(dry.map { slot($0, day: offset, rain: $0 < 11 ? 90 : 0) }) }
        let settings = NotificationSettings(walkTime: true, hasDog: true)

        XCTAssertEqual(plan(twoDays, settings: settings).filter { $0.kind == .walkTime }.map(\.date), [at(11)])
        // Planned at 21:00 from a fetch then, tomorrow's is 14 hours on.
        XCTAssertEqual(
            plan(twoDays, now: at(21), settings: settings).filter { $0.kind == .walkTime }.map(\.date),
            [at(35)]
        )
        // From a cache fetched the day before, neither.
        XCTAssertTrue(plan(twoDays, fetchedAt: at(-20), settings: settings).filter { $0.kind == .walkTime }.isEmpty)
    }

    func testAReplanLaterInTheMorningKeepsTodaysNudge() {
        // Opening the app after the 8:30 briefing replans: today's 11:00 nudge must survive it.
        let laterGood = [day(dry.map { slot($0, rain: $0 < 11 ? 90 : 0) })]
        let settings = NotificationSettings(walkTime: true, hasDog: true)

        for hour in [8.75, 9.5, 10.9] {
            XCTAssertEqual(plan(laterGood, now: at(hour), settings: settings).filter { $0.kind == .walkTime }.map(\.date), [at(11)])
        }
        // Once it has gone by, there's nothing left to queue today.
        XCTAssertTrue(plan(laterGood, now: at(11.5), settings: settings).filter { $0.kind == .walkTime }.isEmpty)
    }

    func testNoSecondNudgeOnADayOneHasAlreadyGoneOff() {
        // Fetched at noon, so the morning's hours are gone: rain until 15:00, then good. The 11:00
        // nudge already went off, so the afternoon's good hour doesn't get another.
        let afternoon = [day((12 ... 20).map { slot($0, rain: $0 < 15 ? 90 : 0) })]
        let settings = NotificationSettings(walkTime: true, hasDog: true)

        XCTAssertEqual(plan(afternoon, now: at(12.5), settings: settings).filter { $0.kind == .walkTime }.map(\.date), [at(15)])
        XCTAssertTrue(plan(afternoon, now: at(12.5), settings: settings, walkNudgesGoneOff: [at(11)])
            .filter { $0.kind == .walkTime }.isEmpty)
        // Yesterday's nudge doesn't count against today.
        XCTAssertEqual(
            plan(afternoon, now: at(12.5), settings: settings, walkNudgesGoneOff: [at(-13)]).filter { $0.kind == .walkTime }.map(\.date),
            [at(15)]
        )
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

    func testEachKindsStackSaysWhatItIsWithOneAndManyMore() {
        XCTAssertEqual(Set(WeatherNotificationScheduler.categories.map(\.identifier)), ["morning_briefing", "walk_time", "rain_alerts"])
        let bundle = Bundle(for: WeatherNotificationScheduler.self)
        func summary(_ kind: NotificationKind, _ count: Int) -> String {
            String(format: bundle.localizedString(forKey: WeatherNotificationScheduler.summaryFormat(kind), value: nil, table: nil), count)
        }
        XCTAssertEqual(summary(.morningBriefing, 1), "1 more briefing")
        XCTAssertEqual(summary(.morningBriefing, 3), "3 more briefings")
        XCTAssertEqual(summary(.walkTime, 1), "1 more walk reminder")
        XCTAssertEqual(summary(.rain, 2), "2 more rain alerts")
    }

    // MARK: - Pictures and records

    func testThePictureIsTheBriefingsMoodTheWalkOrTheUmbrella() {
        func planned(_ kind: NotificationKind, mood: PetMood? = nil, snow: Bool = false) -> PlannedNotification {
            PlannedNotification(identifier: "x", kind: kind, date: at(8), title: "", body: "", snow: snow, mood: mood)
        }
        XCTAssertEqual(planned(.morningBriefing, mood: .cloudy).pictureMood, .cloudy)
        XCTAssertNil(planned(.morningBriefing).pictureMood, "a briefing without the hour's weather has no picture")
        XCTAssertEqual(planned(.walkTime).pictureMood, .sunny)
        XCTAssertEqual(planned(.rain).pictureMood, .rain)
        XCTAssertEqual(planned(.rain, snow: true).pictureMood, .snow)
    }

    func testOnlyNudgesThatHaveGoneOffCountAsGoneOff() {
        XCTAssertEqual(NotificationPlanner.walkNudgesGoneOff(recorded: [at(-13), at(6), at(11)], now: at(7)), [at(-13), at(6)])
    }

    func testTheWalkRecordKeepsTodaysThatHaveGoneOffAndTheNewPlans() {
        let walks = [
            PlannedNotification(identifier: "walk_0", kind: .walkTime, date: at(15), title: "", body: ""),
            PlannedNotification(identifier: "briefing_0", kind: .morningBriefing, date: at(32.5), title: "", body: ""),
            PlannedNotification(identifier: "walk_1", kind: .walkTime, date: at(35), title: "", body: ""),
        ]
        XCTAssertEqual(
            NotificationPlanner.walkNudgeRecord(goneOff: [at(-13), at(11)], plan: walks, now: at(12), calendar: calendar),
            [at(11), at(15), at(35)]
        )
        XCTAssertTrue(NotificationPlanner.walkNudgeRecord(goneOff: [at(-13)], plan: [], now: at(12), calendar: calendar).isEmpty)
    }

    func testTheRainRecordIsTheAlertJustPlannedOrLeftAsItWas() {
        let alert = plan(rainFrom(8.5), now: at(7), settings: NotificationSettings(rain: true))
        XCTAssertEqual(NotificationPlanner.rainAlertRecord(plan: alert), RainAlertRecord(rainStart: dayStart + 8 * hour + 1800, fireDate: at(7.5)))
        XCTAssertNil(NotificationPlanner.rainAlertRecord(plan: plan([day(dry.map { slot($0) })])))
    }

    func testTheSouthernHemisphereIsBelowTheEquatorAndANameOnlyCityIsNorthern() {
        XCTAssertTrue(SavedLocation(label: "Sydney", latitude: -33.87, longitude: 151.21).isSouthernHemisphere)
        XCTAssertFalse(SavedLocation(label: "London", latitude: 51.5, longitude: -0.13).isSouthernHemisphere)
        XCTAssertFalse(SavedLocation(label: "Paris", latitude: nil, longitude: nil).isSouthernHemisphere)
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
