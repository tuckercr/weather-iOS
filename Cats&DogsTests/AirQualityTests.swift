import XCTest
@testable import Cats_Dogs

@MainActor
final class AirQualityTests: XCTestCase {
    private func us(_ index: Int) -> AirQuality {
        AirQuality(index: index, scale: .us, mainPollutant: nil)
    }

    private func european(_ index: Int) -> AirQuality {
        AirQuality(index: index, scale: .european, mainPollutant: nil)
    }

    func testUSBandsChangeAboveEachBreakpoint() {
        XCTAssertEqual([0, 50, 51, 100, 101, 150, 151, 200, 201, 300, 301, 500].map { us($0).band },
                       [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
        XCTAssertEqual(us(42).bandName, "Good")
        XCTAssertEqual(us(128).bandName, "Poor for some")
        XCTAssertEqual(us(400).bandName, "Hazardous")
    }

    func testEuropeanBandsChangeEveryTwenty() {
        XCTAssertEqual([0, 20, 21, 40, 41, 60, 61, 80, 81, 100, 101].map { european($0).band },
                       [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5])
        XCTAssertEqual(european(50).bandName, "Moderate")
        XCTAssertEqual(european(120).bandName, "Extremely poor")
    }

    func testBarPositionSplitsTheBarIntoSixEqualBands() {
        XCTAssertEqual(us(0).barPosition, 0, accuracy: 0.001)
        XCTAssertEqual(us(25).barPosition, 1.0 / 12, accuracy: 0.001)
        XCTAssertEqual(us(100).barPosition, 2.0 / 6, accuracy: 0.001)
        XCTAssertEqual(european(30).barPosition, 1.5 / 6, accuracy: 0.001)
        XCTAssertEqual(us(900).barPosition, 1, "Off the scale stays on the bar")
    }

    func testLinesSpeakOfWalksWithADogAndOfPeopleWithout() {
        XCTAssertEqual(us(42).line(hasDog: true), "Good air for a long walk")
        XCTAssertEqual(us(128).line(hasDog: true), "Short walks for older and flat-faced dogs")
        XCTAssertEqual(us(172).line(hasDog: true), "Potty breaks only today")
        XCTAssertEqual(us(42).line(hasDog: false), "Fresh air all round")
        XCTAssertEqual(us(400).line(hasDog: false), "Stay indoors")
    }

    func testEuropeanCitiesUseTheEuropeanScale() {
        XCTAssertEqual(AirQuality.Scale.forTimeZone("Europe/London"), .european)
        XCTAssertEqual(AirQuality.Scale.forTimeZone("America/New_York"), .us)
        XCTAssertEqual(AirQuality.Scale.forTimeZone(nil), .us)
    }

    func testParsesEachHoursIndexAndNamesTheBiggestPollutantForTheCitysScale() throws {
        let json = """
        {"timezone":"Europe/London","hourly":{"time":[100,3700],"us_aqi":[67,40],"us_aqi_pm2_5":[67,40],
        "european_aqi":[50,90],"european_aqi_pm2_5":[45,90],"european_aqi_nitrogen_dioxide":[50,10]}}
        """
        let response = try JSONDecoder().decode(AirQualityHourlyResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.byHour, [
            100: AirQuality(index: 50, scale: .european, mainPollutant: .nitrogenDioxide),
            3700: AirQuality(index: 90, scale: .european, mainPollutant: .fineParticles),
        ])
        XCTAssertEqual(response.byHour[100]?.pollutantLine, "Mostly nitrogen dioxide")
    }

    func testATieGoesToTheFirstListedPollutant() throws {
        let json = """
        {"timezone":"America/New_York","hourly":{"time":[100],"us_aqi":[46],"us_aqi_pm2_5":[46],"us_aqi_ozone":[46]}}
        """
        let response = try JSONDecoder().decode(AirQualityHourlyResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.byHour[100]?.mainPollutant, .fineParticles)
    }

    func testADustStormIsDustNotSmoke() throws {
        // Riyadh on 11-07: PM2.5's index off the top of the scale and none for PM10, but six times as
        // much PM10 as PM2.5 by mass.
        let json = """
        {"timezone":"Asia/Riyadh","hourly":{"time":[100,3700],"us_aqi":[504,500],"us_aqi_pm2_5":[504,500],
        "us_aqi_pm10":[null,500],"pm2_5":[517.8,null],"pm10":[3173.9,null]}}
        """
        let response = try JSONDecoder().decode(AirQualityHourlyResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.byHour[100]?.mainPollutant, .coarseParticles)
        // Both indices topped out: a tie goes to coarse particles.
        XCTAssertEqual(response.byHour[3700]?.mainPollutant, .coarseParticles)
    }

    func testSmokeAndCityAirStayFineParticles() {
        XCTAssertFalse(AirQuality.isDusty(pm25: 117, pm10: 127)) // Lahore's smoke
        XCTAssertFalse(AirQuality.isDusty(pm25: 98, pm10: 204)) // New Delhi
        XCTAssertTrue(AirQuality.isDusty(pm25: 128, pm10: 561)) // Kuwait City's dust
        XCTAssertFalse(AirQuality.isDusty(pm25: 5, pm10: 30)) // too little to call
        XCTAssertFalse(AirQuality.isDusty(pm25: nil, pm10: 300))
    }

    func testAnHourWithoutAnIndexHasNoReading() throws {
        let json = #"{"timezone":"America/New_York","hourly":{"time":[100,3700],"us_aqi":[null,30]}}"#
        let response = try JSONDecoder().decode(AirQualityHourlyResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.byHour, [3700: AirQuality(index: 30, scale: .us, mainPollutant: nil)])
    }
}
