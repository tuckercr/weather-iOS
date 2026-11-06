import XCTest
@testable import Cats_Dogs

@MainActor
final class OpenMeteoCurrentTests: XCTestCase {
    func testMapsTheReading() throws {
        let weather = try XCTUnwrap(
            OpenMeteoCurrent.weather(from: openMeteoCurrentResponse(), units: .imperial, cityName: "Knoxville")
        )

        XCTAssertEqual(weather.cityName, "Knoxville")
        XCTAssertEqual(weather.temperature, 63.3)
        XCTAssertEqual(weather.feelsLike, 63.8)
        XCTAssertEqual(weather.conditionMain, "Clear")
        XCTAssertEqual(weather.description, "Clear sky")
        XCTAssertEqual(weather.iconCode, "01d")
        XCTAssertEqual(weather.humidityPercent, 62)
        XCTAssertEqual(weather.pressureHpa, 1015)
        XCTAssertEqual(weather.windSpeed, 1.1)
        XCTAssertEqual(weather.windDeg, 267)
        XCTAssertEqual(weather.visibilityMeters, 29_300)
        XCTAssertEqual(weather.cloudPercent, 5)
        XCTAssertEqual(weather.units, .imperial)
        XCTAssertEqual(weather.tempMax, 65.6)
        XCTAssertEqual(weather.tempMin, 48)
        XCTAssertEqual(weather.sunriseEpoch, fixtureDayStart + 18_000 + 7 * 3600)
        XCTAssertEqual(weather.sunsetEpoch, fixtureDayStart + 18_000 + 17 * 3600)
        XCTAssertEqual(weather.timezoneOffsetSeconds, -18_000)
        XCTAssertEqual(weather.observedAtEpoch, fixtureDayStart + 12 * 3600)
    }

    func testNightIcon() {
        let weather = OpenMeteoCurrent.weather(from: openMeteoCurrentResponse(isDay: 0), units: .metric, cityName: "")
        XCTAssertEqual(weather?.iconCode, "01n")
    }

    func testTodaysRangeHoldsTheReading() {
        let above = OpenMeteoCurrent.weather(from: openMeteoCurrentResponse(high: 60), units: .imperial, cityName: "")
        XCTAssertEqual(above?.tempMax, 63.3)
        let below = OpenMeteoCurrent.weather(from: openMeteoCurrentResponse(low: 64), units: .imperial, cityName: "")
        XCTAssertEqual(below?.tempMin, 63.3)
    }

    func testNoReadingWithoutATimeOrTemperature() {
        XCTAssertNil(OpenMeteoCurrent.weather(from: openMeteoCurrentResponse(temperature: nil), units: .metric, cityName: ""))
        XCTAssertNil(OpenMeteoCurrent.weather(from: openMeteoCurrentResponse(time: nil), units: .metric, cityName: ""))
    }

    func testDecodesOpenMeteosAnswer() throws {
        let json = """
        {"utc_offset_seconds":-18000,
         "current":{"time":1793986200,"interval":900,"temperature_2m":63.3,"apparent_temperature":63.8,
                    "relative_humidity_2m":62,"weather_code":0,"cloud_cover":5,"pressure_msl":1014.8,
                    "wind_speed_10m":1.1,"wind_direction_10m":267,"visibility":29300.0,"is_day":1},
         "daily":{"time":[1793941200],"sunrise":[1793966580],"sunset":[1794004500],
                  "temperature_2m_max":[65.6],"temperature_2m_min":[48.0]}}
        """
        let response = try JSONDecoder().decode(OpenMeteoCurrentResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.current.temperature, 63.3)
        XCTAssertEqual(response.current.visibility, 29_300)
        XCTAssertEqual(response.daily.temperatureMax, [65.6])
        XCTAssertEqual(response.daily.sunrise, [1_793_966_580])
    }
}
