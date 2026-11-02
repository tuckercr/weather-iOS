import XCTest
@testable import Cats_Dogs

@MainActor
final class StaleWeatherTests: XCTestCase {
    // 2026-01-01T12:00:00Z, a Thursday.
    private let noon = 1_767_268_800
    private let hour = 3_600

    func testAReadingUpToThreeHoursOldStillCountsAsNow() {
        let reading = weather(observedAt: noon)

        XCTAssertFalse(StaleWeather.isTooOldToShowAsNow(reading, now: date(noon + 3 * hour)))
        XCTAssertTrue(StaleWeather.isTooOldToShowAsNow(reading, now: date(noon + 3 * hour + 1)))
    }

    func testAReadingOfUnknownAgeCountsAsNow() {
        XCTAssertFalse(StaleWeather.isTooOldToShowAsNow(weather(observedAt: nil), now: date(noon + 48 * hour)))
    }

    func testTheForecastHourInProgressStandsInForAnOldReading() throws {
        let forecast = [
            day(tempMin: 2, tempMax: 9, slots: [slot(noon, 5, icon: "04d"), slot(noon + hour, 7, icon: "10d")]),
        ]
        let old = weather(observedAt: noon - 20 * hour)

        let shown = try XCTUnwrap(StaleWeather.forecastAsCurrent(old, forecast: forecast, now: date(noon + hour + 600)))

        XCTAssertEqual(shown.temperature, 7)
        XCTAssertEqual(shown.iconCode, "10d")
        XCTAssertEqual(shown.conditionMain, "Rain")
        XCTAssertEqual(shown.tempMin, 2)
        XCTAssertEqual(shown.tempMax, 9)
        XCTAssertNil(shown.visibilityMeters, "Visibility isn't forecast")
        XCTAssertEqual(shown.cityName, "Austin")
        XCTAssertEqual(shown.observedAtEpoch, old.observedAtEpoch)
    }

    func testAThreeHourlyForecastCoversTheHoursInsideItsSlots() {
        let forecast = [day(slots: [slot(noon, 5), slot(noon + 3 * hour, 8)])]

        XCTAssertEqual(StaleWeather.forecastAsCurrent(weather(observedAt: noon), forecast: forecast, now: date(noon + 2 * hour))?.temperature, 5)
    }

    func testNoStandInOnceTheForecastHasRunOutOrBeforeItStarts() {
        let forecast = [day(slots: [slot(noon, 5), slot(noon + hour, 6)])]
        let reading = weather(observedAt: noon)

        XCTAssertNil(StaleWeather.forecastAsCurrent(reading, forecast: forecast, now: date(noon + 4 * hour + 1)))
        XCTAssertNil(StaleWeather.forecastAsCurrent(reading, forecast: forecast, now: date(noon - 1)))
        XCTAssertNil(StaleWeather.forecastAsCurrent(reading, forecast: [], now: date(noon)))
    }

    func testIconCodesMapToOpenWeatherConditionGroups() {
        XCTAssertEqual(StaleWeather.conditionMain(forIcon: "01n"), "Clear")
        XCTAssertEqual(StaleWeather.conditionMain(forIcon: "03d"), "Clouds")
        XCTAssertEqual(StaleWeather.conditionMain(forIcon: "09d"), "Rain")
        XCTAssertEqual(StaleWeather.conditionMain(forIcon: "11d"), "Thunderstorm")
        XCTAssertEqual(StaleWeather.conditionMain(forIcon: "13n"), "Snow")
        XCTAssertEqual(StaleWeather.conditionMain(forIcon: "50d"), "Mist")
    }

    func testReadingTimeSaysTodayYesterdayOrTheDayInTheCitysOwnDate() {
        let reading = weather(observedAt: noon)

        XCTAssertEqual(StaleWeather.readingTime(reading, now: date(noon + 2 * hour)), "12:00 PM")
        XCTAssertEqual(StaleWeather.readingTime(reading, now: date(noon + 24 * hour)), "yesterday at 12:00 PM")
        XCTAssertEqual(StaleWeather.readingTime(reading, now: date(noon + 72 * hour)), "Thu at 12:00 PM")
        // 21:00 on the 1st in Tokyo; by 09:30 on the 2nd there, it's yesterday.
        var tokyo = reading
        tokyo.timezoneOffsetSeconds = 9 * hour
        XCTAssertEqual(StaleWeather.readingTime(tokyo, now: date(noon + 12 * hour + 1_800)), "yesterday at 9:00 PM")
        XCTAssertNil(StaleWeather.readingTime(weather(observedAt: nil), now: date(noon)))
    }

    private func date(_ epoch: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(epoch)) }

    func testADayReadingCachedBeforeSunsetShowsNightAfterIt() {
        let reading = weather(observedAt: noon, sunrise: noon - 5 * hour, sunset: noon + 5 * hour)

        XCTAssertEqual(StaleWeather.iconCode(reading, at: date(noon + 4 * hour)), "01d")
        XCTAssertEqual(StaleWeather.iconCode(reading, at: date(noon + 7 * hour)), "01n")
    }

    func testANightReadingFromTheEveningBeforeShowsDayAfterSunrise() {
        // Taken at 22:00 the day before, with that day's sunrise and sunset.
        let reading = weather(observedAt: noon - 14 * hour, iconCode: "04n", sunrise: noon - 29 * hour, sunset: noon - 19 * hour)

        XCTAssertEqual(StaleWeather.iconCode(reading, at: date(noon - 6 * hour)), "04n")
        XCTAssertEqual(StaleWeather.iconCode(reading, at: date(noon)), "04d")
    }

    func testARecentReadingKeepsOpenWeathersIcon() {
        let reading = weather(observedAt: noon + 5 * hour - 600, sunrise: noon - 5 * hour, sunset: noon + 5 * hour)

        XCTAssertEqual(StaleWeather.iconCode(reading, at: date(noon + 5 * hour + 600)), "01d")
    }

    func testWithoutSunTimesTheIconStands() {
        XCTAssertEqual(StaleWeather.iconCode(weather(observedAt: noon), at: date(noon + 9 * hour)), "01d")
    }

    func testDayAndNightGoByTheCitysOwnClock() {
        // UTC+10: sunrise 06:00 and sunset 18:00 local are 20:00 the day before and 08:00 UTC.
        let reading = weather(observedAt: noon - 7 * hour, sunrise: noon - 16 * hour, sunset: noon - 4 * hour, offset: 10 * 3600)

        XCTAssertEqual(StaleWeather.iconCode(reading, at: date(noon - 2 * hour)), "01n")
    }

    private func weather(
        observedAt: Int?,
        iconCode: String = "01d",
        sunrise: Int? = nil,
        sunset: Int? = nil,
        offset: Int = 0
    ) -> CurrentWeather {
        CurrentWeather(
            cityName: "Austin",
            conditionMain: "Clear",
            description: "Clear sky",
            iconCode: iconCode,
            temperature: 20,
            feelsLike: 20,
            tempMin: 15,
            tempMax: 25,
            humidityPercent: 40,
            pressureHpa: 1013,
            windSpeed: 3,
            windDeg: 90,
            visibilityMeters: 10_000,
            cloudPercent: 10,
            units: .metric,
            sunriseEpoch: sunrise,
            sunsetEpoch: sunset,
            timezoneOffsetSeconds: offset,
            observedAtEpoch: observedAt
        )
    }

    private func day(tempMin: Double = 0, tempMax: Double = 10, slots: [HourlySlot]) -> DayForecast {
        DayForecast(
            dateLabel: "Thu, Jan 1",
            conditionMain: "Clouds",
            description: "cloudy",
            iconCode: "03d",
            temperature: 5,
            feelsLike: 5,
            tempMin: tempMin,
            tempMax: tempMax,
            units: .metric,
            hourlySlots: slots
        )
    }

    private func slot(_ epoch: Int, _ temperature: Double, icon: String = "01d") -> HourlySlot {
        HourlySlot(
            timeLabel: String(epoch),
            iconCode: icon,
            description: "forecast",
            temperature: temperature,
            feelsLike: temperature,
            windSpeed: 2,
            windDeg: 0,
            humidity: 60,
            pressure: 1010,
            units: .metric,
            epochSeconds: epoch
        )
    }

    // MARK: - Today's sun

    /// Midnight UTC; these readings are in UTC.
    private let dayStart = fixtureDayStart

    func testSunTimesFromAnEarlierDayMoveOntoToday() {
        // Cached yesterday evening with yesterday's sun (07:00 and 16:30, UTC), shown at 10:00 today.
        let day = 86_400
        let reading = weather(observedAt: dayStart - 3 * 3600, iconCode: "01n", sunrise: dayStart - day + 7 * 3600,
                              sunset: dayStart - day + 16 * 3600 + 1800)
        let moved = StaleWeather.withSunTimesToday(reading, at: date(dayStart + 10 * 3600))

        XCTAssertEqual(moved.sunriseEpoch, dayStart + 7 * 3600)
        XCTAssertEqual(moved.sunsetEpoch, dayStart + 16 * 3600 + 1800)
        XCTAssertFalse(StaleWeather.isDark(moved, at: date(dayStart + 10 * 3600)))
        // Left as it was, yesterday's sunset would say it's dark at 10 AM.
        XCTAssertTrue(StaleWeather.isDark(reading, at: date(dayStart + 10 * 3600)))
    }

    func testTodaysOrTomorrowsSunTimesAreLeftAlone() {
        let today = weather(observedAt: dayStart + 9 * 3600, sunrise: dayStart + 7 * 3600, sunset: dayStart + 16 * 3600)
        XCTAssertEqual(StaleWeather.withSunTimesToday(today, at: date(dayStart + 21 * 3600)), today)
        let tomorrows = weather(observedAt: dayStart + 21 * 3600, sunrise: dayStart + 86_400 + 7 * 3600,
                                sunset: dayStart + 86_400 + 16 * 3600)
        XCTAssertEqual(StaleWeather.withSunTimesToday(tomorrows, at: date(dayStart + 21 * 3600)), tomorrows)
    }

    func testItsDarkBeforeSunriseAndFromSunsetByTheClock() {
        let reading = weather(observedAt: dayStart + 9 * 3600, sunrise: dayStart + 7 * 3600, sunset: dayStart + 16 * 3600)
        XCTAssertTrue(StaleWeather.isDark(reading, at: date(dayStart + 6 * 3600)))
        XCTAssertFalse(StaleWeather.isDark(reading, at: date(dayStart + 12 * 3600)))
        XCTAssertTrue(StaleWeather.isDark(reading, at: date(dayStart + 16 * 3600 + 300)))
        // Without sun times it's left to the forecast.
        XCTAssertFalse(StaleWeather.isDark(weather(observedAt: dayStart), at: date(dayStart + 23 * 3600)))
    }
}
