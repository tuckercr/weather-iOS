import XCTest
@testable import Cats_Dogs

@MainActor
final class WeatherScreenTests: XCTestCase {
    private let hour = 3600
    /// Mon 1 Jan 2024, 00:00 UTC; the readings are in UTC.
    private let dayStart = fixtureDayStart
    private var noon: Int { dayStart + 12 * hour }

    // MARK: - Loading, errors and old readings

    func testLoadingAndErrorsPassThrough() {
        guard case .loading = make(current: .loading) else { return XCTFail("expected loading") }
        guard case let .error(key, canRetry, lastUpdated) = make(current: .error(errorKey: "network", canRetry: true)) else {
            return XCTFail("expected error")
        }
        XCTAssertEqual(key, "network")
        XCTAssertTrue(canRetry)
        XCTAssertNil(lastUpdated)
    }

    func testAFreshReadingShowsWithNoBanner() {
        let state = weatherState(make(current: .success(reading(observedAt: noon))))
        XCTAssertFalse(state?.showingForecast ?? true)
        XCTAssertNil(state?.stale)
    }

    func testAnOldReadingWhileRefreshesFailShowsWithTheBanner() {
        let state = weatherState(make(current: .success(reading(observedAt: noon - hour)), staleErrorKey: "network"))
        XCTAssertEqual(state?.stale?.errorKey, "network")
        XCTAssertFalse(state?.showingForecast ?? true)
    }

    func testPastTheCutoffTheForecastHourStandsIn() {
        let forecast = [day(slots: (0 ..< 24).map { slot(dayStart + $0 * hour, temperature: 30) })]
        let state = weatherState(make(
            current: .success(reading(observedAt: noon - 5 * hour)),
            forecast: .success(forecast),
            staleErrorKey: "network"
        ))
        XCTAssertTrue(state?.showingForecast ?? false)
        XCTAssertEqual(state?.weather.temperature, 30)
        XCTAssertEqual(state?.stale?.reading.temperature, 20)
    }

    func testPastTheCutoffWithNoForecastHourIsTheErrorWithTheReadingsTime() {
        guard case let .error(key, canRetry, lastUpdated) = make(
            current: .success(reading(observedAt: noon - 5 * hour)),
            staleErrorKey: "network"
        ) else { return XCTFail("expected error") }
        XCTAssertEqual(key, "network")
        XCTAssertTrue(canRetry)
        XCTAssertNotNil(lastUpdated)
    }

    // MARK: - Hero caption

    func testTheHeroCaptionFollowsTheSkyAsMistysViewReadsIt() {
        // 1 Jan at noon: the daily pick is the second caption of the list.
        let fewClouds = weatherState(make(current: .success(reading(observedAt: noon, iconCode: "02d", conditionMain: "Clouds", cloudPercent: 20))))
        XCTAssertEqual(fewClouds?.mood, .cloudy)
        XCTAssertEqual(fewClouds?.heroCaption, "Sun in, sun out. Sunny is ready either way.")
        let overcast = weatherState(make(current: .success(reading(observedAt: noon, iconCode: "04d", conditionMain: "Clouds", cloudPercent: 95))))
        XCTAssertEqual(overcast?.mood, .cloudy)
        XCTAssertEqual(overcast?.heroCaption, "Nap weather, says Misty.")
    }

    // MARK: - Seasonal theme by the clock

    /// A theme on every day, so the fixture's 1 January has it.
    private var everyDayTheme: WeatherScreenConfig {
        var config = WeatherScreenConfig()
        config.seasonalThemes = [SeasonalTheme(
            id: "test",
            dates: .range(fromMonth: 1, fromDay: 1, throughMonth: 12, throughDay: 31),
            colors: SeasonalThemes.builtIn[0].colors,
            captions: SeasonalTheme.Captions(day: ["Theme day"], night: ["Theme night"]),
            decorations: [.witchHat, .jackOLantern]
        )]
        return config
    }

    func testARainyEveningOnTheDayGetsTheNightLook() {
        // 7 PM, after the fixture's 5 PM sunset, raining: the mood is rain, the theme's look night.
        // The reading is from 4 PM, so the clock, not its daytime icon, says it's dark.
        let evening = dayStart + 19 * hour
        let state = weatherState(make(
            current: .success(reading(observedAt: evening - 3 * hour + 1, iconCode: "10d", conditionMain: "Rain", cloudPercent: 90)),
            now: Date(timeIntervalSince1970: TimeInterval(evening)),
            config: everyDayTheme
        ))
        XCTAssertEqual(state?.mood, .rain)
        XCTAssertEqual(state?.darkNow, true)
        XCTAssertEqual(state?.heroCaption, "Theme night")
    }

    func testThreeInTheMorningOnTheDayHasTheNightColoursAndTheDayCaption() {
        let small = dayStart + 3 * hour
        let state = weatherState(make(
            current: .success(reading(observedAt: small, iconCode: "01n")),
            now: Date(timeIntervalSince1970: TimeInterval(small)),
            config: everyDayTheme
        ))
        XCTAssertEqual(state?.darkNow, true)
        XCTAssertEqual(state?.heroCaption, "Theme day")
    }

    func testNoonOnTheDayGetsTheDayLook() {
        let state = weatherState(make(current: .success(reading(observedAt: noon)), config: everyDayTheme))
        XCTAssertEqual(state?.darkNow, false)
        XCTAssertEqual(state?.heroCaption, "Theme day")
    }

    // MARK: - Today

    func testTodayGoesByTheCitysDateNotTheLabel() {
        // The label is stale, but the hours are today's.
        var today = day(slots: [slot(dayStart + 13 * hour, temperature: 20)])
        today = DayForecast(
            dateLabel: "Sun, Dec 31", conditionMain: today.conditionMain, description: today.description,
            iconCode: today.iconCode, temperature: today.temperature, feelsLike: today.feelsLike,
            tempMin: 5, tempMax: 25, units: .metric, hourlySlots: today.hourlySlots
        )
        let state = weatherState(make(current: .success(reading(observedAt: noon)), forecast: .success([today])))
        XCTAssertEqual(state?.today?.dateLabel, "Sun, Dec 31")
        XCTAssertEqual(state?.high, 25)
        XCTAssertEqual(state?.low, 5)
    }

    func testAfterMidnightYesterdayIsNotToday() {
        // A forecast cached yesterday: its first day has gone, so the week starts with it too.
        let yesterday = day(slots: [slot(dayStart - 10 * hour, temperature: 20)])
        let state = weatherState(make(current: .success(reading(observedAt: noon)), forecast: .success([yesterday])))
        XCTAssertNil(state?.today)
    }

    func testTheWeekLeavesOutToday() {
        let today = day(slots: [slot(dayStart + 13 * hour, temperature: 20)])
        let tomorrow = day(label: "Tue, Jan 2", slots: [slot(dayStart + 37 * hour, temperature: 20)])
        let state = weatherState(make(current: .success(reading(observedAt: noon)), forecast: .success([today, tomorrow])))
        guard case let .days(days) = state?.week else { return XCTFail("expected days") }
        XCTAssertEqual(days.map(\.dateLabel), ["Tue, Jan 2"])
    }

    func testTheWeekShowsLoadingAndErrorsAndCanBeSwitchedOff() {
        let current = LoadingState.success(reading(observedAt: noon))
        guard case .loading = weatherState(make(current: current, forecast: .loading))?.week else {
            return XCTFail("expected loading")
        }
        guard case .error(errorKey: "network", canRetry: false) = weatherState(make(
            current: current,
            forecast: .error(errorKey: "network", canRetry: false)
        ))?.week else { return XCTFail("expected error") }
        var config = WeatherScreenConfig()
        config.weekForecastEnabled = false
        XCTAssertNil(weatherState(make(current: current, forecast: .loading, config: config))?.week)
    }

    // MARK: - Hourly strip

    func testTheHourlyStripStartsAtTheHourInProgressAndCanBeSwitchedOff() {
        let forecast = [day(slots: (0 ..< 48).map { slot(dayStart + $0 * hour, temperature: Double($0)) })]
        let at = Date(timeIntervalSince1970: TimeInterval(noon + 30 * 60))
        let state = weatherState(make(current: .success(reading(observedAt: noon)), forecast: .success(forecast), now: at))
        let hours = state?.hourlyStrip.compactMap { item -> HourlySlot? in
            if case let .hour(slot) = item { return slot }
            return nil
        } ?? []
        XCTAssertEqual(hours.first?.epochSeconds, noon)
        XCTAssertEqual(hours.count, WeatherScreenState.hourlyStripCount)

        var config = WeatherScreenConfig()
        config.hourlyForecastEnabled = false
        let off = weatherState(make(current: .success(reading(observedAt: noon)), forecast: .success(forecast), now: at, config: config))
        XCTAssertEqual(off?.hourlyStrip.isEmpty, true)
    }

    // MARK: - Walk and tiles

    func testTheWalkCardWaitsForTheForecast() {
        let loading = weatherState(make(current: .success(reading(observedAt: noon)), forecast: .loading))
        XCTAssertNil(loading?.walkAdvice)
        XCTAssertFalse(loading?.showsWalkCard ?? true)

        let forecast = [day(slots: (0 ..< 24).map { slot(dayStart + $0 * hour, temperature: 18) })]
        let loaded = weatherState(make(current: .success(reading(observedAt: noon)), forecast: .success(forecast)))
        XCTAssertNotNil(loaded?.walkAdvice)
    }

    func testThePavementTileNeedsADogAndAirQualityItsSwitch() {
        var hot = slot(noon, temperature: 35)
        hot.pavementTemperature = 55
        hot.airQuality = AirQuality(index: 30, scale: .european, mainPollutant: nil)
        let forecast = LoadingState.success([day(slots: [hot])])
        let current = LoadingState.success(reading(observedAt: noon))

        let withDog = weatherState(make(current: current, forecast: forecast))
        XCTAssertEqual(withDog?.tiles.pavementNow, 55)
        XCTAssertNotNil(withDog?.tiles.airQuality)

        XCTAssertNil(weatherState(make(current: current, forecast: forecast, hasDog: false))?.tiles.pavementNow)
        var config = WeatherScreenConfig()
        config.airQualityEnabled = false
        XCTAssertNil(weatherState(make(current: current, forecast: forecast, config: config))?.tiles.airQuality)
    }

    func testUVIsLeftOutAtNight() {
        var uv = slot(dayStart + 22 * hour, temperature: 10)
        uv.uvIndex = 3
        let night = reading(observedAt: dayStart + 22 * hour, iconCode: "01n")
        let state = weatherState(make(
            current: .success(night),
            forecast: .success([day(slots: [uv])]),
            now: Date(timeIntervalSince1970: TimeInterval(dayStart + 22 * hour))
        ))
        XCTAssertNil(state?.tiles.uvIndex)
    }

    // MARK: - Helpers

    private func make(
        current: LoadingState<CurrentWeather>,
        forecast: LoadingState<[DayForecast]> = .idle,
        staleErrorKey: String? = nil,
        now: Date? = nil,
        hasDog: Bool = true,
        config: WeatherScreenConfig? = nil
    ) -> WeatherScreen {
        WeatherScreen.make(
            current: current,
            forecast: forecast,
            staleErrorKey: staleErrorKey,
            now: now ?? Date(timeIntervalSince1970: TimeInterval(noon)),
            hasDog: hasDog,
            config: config ?? WeatherScreenConfig()
        )
    }

    private func weatherState(_ screen: WeatherScreen) -> WeatherScreenState? {
        if case let .weather(state) = screen { return state }
        XCTFail("expected weather, got \(screen)")
        return nil
    }

    private func reading(
        observedAt: Int,
        iconCode: String = "01d",
        conditionMain: String = "Clear",
        cloudPercent: Int = 10
    ) -> CurrentWeather {
        CurrentWeather(
            cityName: "Austin", conditionMain: conditionMain, description: "Clear sky", iconCode: iconCode,
            temperature: 20, feelsLike: 20, tempMin: 15, tempMax: 25, humidityPercent: 40, pressureHpa: 1013,
            windSpeed: 3, windDeg: 90, visibilityMeters: 10_000, cloudPercent: cloudPercent, units: .metric,
            sunriseEpoch: dayStart + 7 * hour, sunsetEpoch: dayStart + 17 * hour,
            timezoneOffsetSeconds: 0, observedAtEpoch: observedAt
        )
    }

    private func day(label: String = "Mon, Jan 1", slots: [HourlySlot]) -> DayForecast {
        DayForecast(
            dateLabel: label, conditionMain: "Clear", description: "clear", iconCode: "01d",
            temperature: 18, feelsLike: 18, tempMin: 10, tempMax: 22, units: .metric, hourlySlots: slots
        )
    }

    private func slot(_ epoch: Int, temperature: Double) -> HourlySlot {
        HourlySlot(
            timeLabel: String(epoch), iconCode: "01d", description: "clear", temperature: temperature,
            feelsLike: temperature, windSpeed: 2, windDeg: 0, humidity: 60, pressure: 1010, units: .metric,
            epochSeconds: epoch
        )
    }
}
