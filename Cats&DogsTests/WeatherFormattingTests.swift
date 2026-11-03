import XCTest
@testable import Cats_Dogs

@MainActor
final class WeatherFormattingTests: XCTestCase {
    /// 2023-11-14 22:13:20 UTC
    private let epoch = 1_700_000_000

    func testEpochTimeIsFormattedInTheGivenTimeZone() {
        let utc = WeatherFormatting.epochTime(epoch, timeZone: TimeZone(secondsFromGMT: 0)!)
        let tokyo = WeatherFormatting.epochTime(epoch, timeZone: TimeZone(secondsFromGMT: 9 * 3600)!)

        XCTAssertTrue(utc.hasPrefix("10:13"), utc)
        XCTAssertTrue(tokyo.hasPrefix("7:13"), tokyo)
    }

    func testCurrentWeatherUsesTheCitysOffsetFromTheApi() async {
        let api = ScriptedWeatherAPI()
        api.onCurrent = { _ in
            var response = weatherResponse(name: "Tokyo")
            response.timezone = 9 * 3600
            return response
        }

        let weather = try? await api.repository.fetchCurrentWeather(
            units: .metric, locationLabel: "Tokyo", cityQuery: "Tokyo", latitude: nil, longitude: nil
        ).get()

        XCTAssertEqual(weather?.timezoneOffsetSeconds, 32_400)
        XCTAssertEqual(weather?.timeZone.secondsFromGMT(), 32_400)
    }

    func testWeatherCachedBeforeTheOffsetExistedFallsBackToTheDeviceTimeZone() async {
        let weather = await makeCurrentWeather()

        XCTAssertNil(weather.timezoneOffsetSeconds)
        XCTAssertEqual(weather.timeZone, .current)
    }

    func testTimezoneIsDecodedFromTheApiPayload() throws {
        let json = """
        {"name":"Tokyo","weather":[{"main":"Clear","description":"clear sky","icon":"01d"}],
         "main":{"temp":20,"feels_like":19,"temp_min":18,"temp_max":22,"humidity":50,"pressure":1012},
         "wind":{"speed":2.0},"timezone":32400}
        """
        let response = try JSONDecoder().decode(CurrentWeatherResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.timezone, 32_400)
    }

    func testUVIndexUsesTheWHOCategories() {
        XCTAssertEqual(WeatherFormatting.uvLevel(0.4), "Low")
        XCTAssertEqual(WeatherFormatting.uvLevel(2.4), "Low")
        XCTAssertEqual(WeatherFormatting.uvLevel(4.6), "Moderate")
        XCTAssertEqual(WeatherFormatting.uvLevel(6), "High")
        XCTAssertEqual(WeatherFormatting.uvLevel(9), "Very high")
        XCTAssertEqual(WeatherFormatting.uvLevel(11.2), "Extreme")
    }

    func testCalmWindIsAPlainZeroWithNoDirection() {
        XCTAssertEqual(WeatherFormatting.wind(0, units: .imperial), "0 mph")
        XCTAssertEqual(WeatherFormatting.wind(0.04, units: .metric), "0 m/s")
        // 0.4 mph rounds to 0, so it's calm too.
        XCTAssertEqual(WeatherFormatting.wind(0.4, units: .imperial), "0 mph")
        XCTAssertTrue(WeatherFormatting.isCalm(0.4, units: .imperial))
        XCTAssertFalse(WeatherFormatting.isCalm(0.5, units: .imperial))
        XCTAssertEqual(WeatherFormatting.wind(0.5, units: .imperial), "1 mph")
    }

    func testWindIsWholeMphAndWholeMetresPerSecondFrom10() {
        XCTAssertEqual(WeatherFormatting.wind(12.6, units: .imperial), "13 mph")
        XCTAssertEqual(WeatherFormatting.wind(3.44, units: .metric), "3.4 m/s")
        XCTAssertEqual(WeatherFormatting.wind(9.96, units: .metric), "10 m/s")
        XCTAssertEqual(WeatherFormatting.wind(12.4, units: .metric), "12 m/s")
    }

    func testRainChanceUnder10PercentIsHiddenAndTheRestRoundsToTheNearest10() {
        XCTAssertNil(WeatherFormatting.rainChance(0))
        XCTAssertNil(WeatherFormatting.rainChance(9))
        XCTAssertEqual(WeatherFormatting.rainChance(10), 10)
        XCTAssertEqual(WeatherFormatting.rainChance(14), 10)
        XCTAssertEqual(WeatherFormatting.rainChance(37), 40)
        XCTAssertEqual(WeatherFormatting.rainChance(45), 50)
        XCTAssertEqual(WeatherFormatting.rainChance(96), 100)
    }

        func testTemperaturesAreWholeDegrees() {
        XCTAssertEqual(WeatherFormatting.temperature(56.3, units: .imperial), "56 °F")
        XCTAssertEqual(WeatherFormatting.temperature(56.5, units: .imperial), "57 °F")
        XCTAssertEqual(WeatherFormatting.temperature(-3.6, units: .metric), "-4 °C")
    }

    func testTemperaturesShowTheUnitWhenSwitchedOn() {
        XCTAssertEqual(WeatherFormatting.temperature(88.6, units: .imperial, showsUnit: true), "89 °F")
        XCTAssertEqual(WeatherFormatting.temperature(31.4, units: .metric, showsUnit: true), "31 °C")
        XCTAssertEqual(WeatherFormatting.temperature(-3.4, units: .metric, showsUnit: true), "-3 °C")
        XCTAssertEqual(WeatherFormatting.temperature(-3.6, units: .imperial, showsUnit: true), "-4 °F")
    }

    func testTemperaturesSwitchedOffKeepTheNumberAndDegreeSignButNotTheUnit() {
        XCTAssertEqual(WeatherFormatting.temperature(88.6, units: .imperial, showsUnit: false), "89°")
        XCTAssertEqual(WeatherFormatting.temperature(31.4, units: .metric, showsUnit: false), "31°")
        XCTAssertEqual(WeatherFormatting.temperature(-3.4, units: .metric, showsUnit: false), "-3°")
        XCTAssertEqual(WeatherFormatting.temperature(-3.6, units: .imperial, showsUnit: false), "-4°")
        // Rounding is unchanged: halves round away from zero, and nothing reads as "-0°".
        XCTAssertEqual(WeatherFormatting.temperature(56.3, units: .imperial, showsUnit: false), "56°")
        XCTAssertEqual(WeatherFormatting.temperature(56.5, units: .imperial, showsUnit: false), "57°")
        XCTAssertEqual(WeatherFormatting.temperature(-0.4, units: .metric, showsUnit: false), "0°")
    }

    func testTemperaturesShowTheUnitByDefault() {
        // Remote Config's default, which is all there is without Firebase.
        XCTAssertEqual(
            WeatherFormatting.temperature(88.6, units: .imperial),
            WeatherFormatting.temperature(88.6, units: .imperial, showsUnit: true)
        )
        XCTAssertEqual(WeatherFormatting.temperature(-3.6, units: .metric), "-4 °C")
    }

    func testDistanceUnitsFollowTheChoiceOrTheMeasurementSystem() {
        let us = Locale(identifier: "en_US"), uk = Locale(identifier: "en_GB"), france = Locale(identifier: "fr_FR")
        XCTAssertTrue(WeatherFormatting.usesMiles(override: .system, locale: us))
        XCTAssertTrue(WeatherFormatting.usesMiles(override: .system, locale: uk))
        XCTAssertFalse(WeatherFormatting.usesMiles(override: .system, locale: france))
        XCTAssertFalse(WeatherFormatting.usesMiles(override: .metric, locale: us))
        XCTAssertTrue(WeatherFormatting.usesMiles(override: .imperial, locale: france))
    }
}
