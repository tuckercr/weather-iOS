import XCTest
@testable import Cats_Dogs

@MainActor
final class TodayDetailsTests: XCTestCase {
    func testVisibilityBands() {
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 10_000), .excellent)
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 9_999), .good)
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 5_000), .good)
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 4_999), .moderate)
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 1_000), .moderate)
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 999), .poor)
    }

    func testVisibilityAtThe10KmCapHasNoNumberSoItNeverReads6Point2Miles() {
        XCTAssertNil(TodayDetails.visibilityDistance(meters: 10_000, inMiles: true))
        XCTAssertNil(TodayDetails.visibilityDistance(meters: 10_000, inMiles: false))
    }

    func testVisibilityIsWholeMilesOrKilometresFrom1KmUp() {
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 6_500, inMiles: true), "4 mi")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 9_999, inMiles: true), "6 mi")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 1_000, inMiles: true), "1 mi")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 6_500, inMiles: false), "7 km")
    }

    func testUnder1KmVisibilityIsTenthsOfAMileOrMetresToTheNearest100() {
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 800, inMiles: true), "0.5 mi")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 20, inMiles: true), "0.1 mi")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 780, inMiles: false), "800 m")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 20, inMiles: false), "100 m")
    }

    func testObscuredSkiesAreNamedForWhatsInTheAirTheRestByCloudCover() {
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Fog", cloudPercent: 100, iconCode: "50d"), .fog)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Mist", cloudPercent: 100, iconCode: "50d"), .mist)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Smoke", cloudPercent: 0, iconCode: "50d"), .smoke)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Sand", cloudPercent: 0, iconCode: "50d"), .dust)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clear", cloudPercent: 0, iconCode: "01d"), .clear)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clouds", cloudPercent: 10, iconCode: "02d"), .clear)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clouds", cloudPercent: 50, iconCode: "03d"), .partlyCloudy)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clouds", cloudPercent: 84, iconCode: "04d"), .mostlyCloudy)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Rain", cloudPercent: 100, iconCode: "10d"), .overcast)
    }

    func testWithoutACloudCoverTheIconDecides() {
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clear", cloudPercent: nil, iconCode: "01n"), .clear)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clouds", cloudPercent: nil, iconCode: "02d"), .partlyCloudy)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clouds", cloudPercent: nil, iconCode: "03d"), .mostlyCloudy)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Rain", cloudPercent: nil, iconCode: "10d"), .overcast)
    }

    func testPavementBandsFollowTheWalkThresholds() {
        let t = PetWeatherThresholds.standard
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 57.2, groundWet: false, feelsLikeC: 20, thresholds: t), .dangerous)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 57.1, groundWet: false, feelsLikeC: 20, thresholds: t), .tooHot)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 52, groundWet: false, feelsLikeC: 20, thresholds: t), .tooHot)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 51.9, groundWet: false, feelsLikeC: 20, thresholds: t), .warm)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 45, groundWet: false, feelsLikeC: 20, thresholds: t), .warm)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 44.9, groundWet: false, feelsLikeC: 20, thresholds: t), .safe)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 0, groundWet: true, feelsLikeC: 0.1, thresholds: t), .safe)
    }

    func testPavementIsOnlySafeForPawsWhenTheAirIsToo() {
        let t = PetWeatherThresholds.standard
        // A muggy night: the pavement has cooled, but it feels 31C, past the pets' 30C limit.
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 29, groundWet: false, feelsLikeC: 31, thresholds: t), .pavementOK)
        // Just above freezing, but -4C in the wind.
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 2, groundWet: false, feelsLikeC: -4, thresholds: t), .pavementOK)
        // Too-hot pavement still says so, whatever the air.
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 53, groundWet: false, feelsLikeC: 31, thresholds: t), .tooHot)
    }

    func testBelowFreezingThePavementIsOnlyIcyAfterRainOrSnow() {
        let t = PetWeatherThresholds.standard
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: -0.1, groundWet: true, feelsLikeC: -3, thresholds: t), .icy)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: -0.1, groundWet: false, feelsLikeC: -3, thresholds: t), .freezing)
    }

    func testDewPoint() throws {
        XCTAssertEqual(try XCTUnwrap(TodayDetails.dewPointC(temperatureC: 8.3, humidityPercent: 86)), 6.0, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(TodayDetails.dewPointC(temperatureC: 20, humidityPercent: 100)), 20, accuracy: 0.01)
        XCTAssertNil(TodayDetails.dewPointC(temperatureC: 20, humidityPercent: 0))
    }

    func testWindForceUsesTheBeaufortScaleInEitherUnit() {
        XCTAssertEqual(TodayDetails.windForce(speed: 0.2, units: .metric), 0)
        XCTAssertEqual(TodayDetails.windForce(speed: 1, units: .imperial), 1)
        XCTAssertEqual(TodayDetails.windForce(speed: 1.5, units: .metric), 1)
        XCTAssertEqual(TodayDetails.windForce(speed: 1.6, units: .metric), 2)
        XCTAssertEqual(TodayDetails.windForce(speed: 10, units: .imperial), 3)
        XCTAssertEqual(TodayDetails.windForce(speed: 20, units: .metric), 8)
        XCTAssertEqual(TodayDetails.windForce(speed: 40, units: .metric), 12)
        XCTAssertEqual(TodayDetails.windForceNames[1], "Light wind")
        XCTAssertEqual(TodayDetails.windForceNames.count, 13)
    }

    func testDaylightBeforeSunriseDuringTheDayAndAfterSunset() {
        let sunrise = 1_000
        let sunset = 1_000 + 10 * 3600

        XCTAssertEqual(TodayDetails.daylight(now: sunrise - 600, sunrise: sunrise, sunset: sunset), .beforeSunrise(secondsUntil: 600))
        XCTAssertEqual(
            TodayDetails.daylight(now: sunset - 2 * 3600, sunrise: sunrise, sunset: sunset),
            .daytime(secondsLeft: 2 * 3600, fraction: 0.8)
        )
        XCTAssertEqual(TodayDetails.daylight(now: sunset, sunrise: sunrise, sunset: sunset), .afterSunset)
    }

    func testDurations() {
        XCTAssertEqual(TodayDetails.duration(seconds: 45 * 60), "45 min")
        XCTAssertEqual(TodayDetails.duration(seconds: 2 * 3600), "2 h")
        XCTAssertEqual(TodayDetails.duration(seconds: 2 * 3600 + 15 * 60 + 30), "2 h 15 min")
    }

    func testNumbersKeepTheirUnitsOnTheSameLine() {
        XCTAssertEqual(TodayDetails.keepUnitsTogether("Actual 56.3 °F"), "Actual 56.3\u{00A0}°F")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("3.4 mph"), "3.4\u{00A0}mph")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("5.0 m/s"), "5.0\u{00A0}m/s")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("Clear · Good visibility, 4 mi"), "Clear · Good visibility, 4\u{00A0}mi")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("800 m"), "800\u{00A0}m")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("6:45 PM"), "6:45\u{00A0}PM")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("7:53\u{202F}AM"), "7:53\u{00A0}AM")
        // Words after numbers are left alone.
        XCTAssertEqual(TodayDetails.keepUnitsTogether("2 h 15 min left"), "2 h 15 min left")
    }

    func testCompassPointsAreSpokenAsWords() {
        XCTAssertEqual(TodayDetails.spokenCompassPoint(0), "north")
        XCTAssertEqual(TodayDetails.spokenCompassPoint(315), "northwest")
        XCTAssertEqual(TodayDetails.spokenCompassPoint(359), "north")
    }

    private func today(low: Double, high: Double) -> DayForecast {
        DayForecast(
            dateLabel: "Fri, Oct 30", conditionMain: "Clear", description: "clear", iconCode: "01d",
            temperature: 18, feelsLike: 18, tempMin: low, tempMax: high, units: .metric, hourlySlots: []
        )
    }

    func testHighAndLowComeFromTodaysForecastNotTheCurrentReading() async {
        let current = await makeCurrentWeather(temperature: 18)

        let highLow = TodayDetails.highLow(current: current, today: today(low: 12, high: 23))

        XCTAssertEqual(highLow.high, 23)
        XCTAssertEqual(highLow.low, 12)
    }

    func testHighAndLowTakeInTheTemperatureNow() async {
        let current = await makeCurrentWeather(temperature: 25)

        let highLow = TodayDetails.highLow(current: current, today: today(low: 12, high: 23))

        XCTAssertEqual(highLow.high, 25)
        XCTAssertEqual(highLow.low, 12)
    }

    func testWithoutTodaysForecastTheCurrentReadingIsUsed() async {
        let current = await makeCurrentWeather(temperature: 18)

        let highLow = TodayDetails.highLow(current: current, today: nil)

        XCTAssertEqual(highLow.high, current.tempMax)
        XCTAssertEqual(highLow.low, current.tempMin)
    }
}
