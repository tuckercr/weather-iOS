import XCTest
@testable import Cats_Dogs

/// Which Today tiles show and what they say. Same cases as Android's `TodayTilesStateTest`.
@MainActor
final class TodayTilesStateTests: XCTestCase {
    private let noon = fixtureDayStart + 12 * 3600

    func testTheSmallTilesGoInOrderAndPawCheckNeedsAPavementValue() {
        let withPavement = tiles(pavementNow: 40, air: AirQuality(index: 20, scale: .european, mainPollutant: nil))
        XCTAssertEqual(withPavement.small.map(Self.name), ["feelsLike", "wind", "fluff", "pawCheck", "air"])

        XCTAssertEqual(tiles(pavementNow: nil).small.map(Self.name), ["feelsLike", "wind", "fluff"])
    }

    func testUVHasItsOwnTileWhenSwitchedOnOrWhenDaylightCannotCarryIt() {
        // Off by default: Daylight carries it.
        let carried = tiles(uvIndex: 6)
        XCTAssertFalse(carried.small.map(Self.name).contains("uv"))
        XCTAssertEqual(carried.daylight?.uvNote, "UV 6 · High")

        var switches = TodayTileSwitches()
        switches.uv = true
        let ownTile = tiles(uvIndex: 6, switches: switches)
        XCTAssertTrue(ownTile.small.map(Self.name).contains("uv"))
        XCTAssertNil(ownTile.daylight?.uvNote)

        // No sun times, so no Daylight tile: UV gets its own.
        let noDaylight = tiles(uvIndex: 6, sunTimes: false)
        XCTAssertNil(noDaylight.daylight)
        XCTAssertTrue(noDaylight.small.map(Self.name).contains("uv"))
    }

    func testDaylightSaysWhatIsLeftOfTheDay() {
        let daylight = tiles().daylight
        XCTAssertEqual(daylight?.isUp, true)
        XCTAssertEqual(daylight?.summary, "5 h left")
        XCTAssertEqual(daylight?.fraction ?? 0, 0.5, accuracy: 0.01)
    }

    func testBadAirReadsBadByTheWalkRulesWithADogAndByBandWithout() {
        // Unhealthy on the US index: potty breaks only for a dog, and band 3 without one.
        let unhealthy = AirQuality(index: 160, scale: .us, mainPollutant: .fineParticles)
        XCTAssertEqual(airTile(tiles(air: unhealthy, hasDog: true))?.tone, .bad)
        XCTAssertEqual(airTile(tiles(air: unhealthy, hasDog: false))?.tone, .bad)
        let good = AirQuality(index: 20, scale: .us, mainPollutant: nil)
        XCTAssertEqual(airTile(tiles(air: good))?.tone, .good)
    }

    func testMistysViewLeavesOutVisibilityForAForecastHour() {
        XCTAssertTrue(tiles().sky?.headline.contains("·") == true)
        XCTAssertEqual(tiles(showingForecast: true).sky?.headline, "Clear")
    }

    func testMistysViewHasNightLinesAfterSunsetAndDayLinesBeforeIt() {
        // Sunset is at 5 PM; 10% cloud is a clear sky, with excellent visibility.
        XCTAssertEqual(tiles(at: noon).sky?.mistyLine, "Misty can see the whole street")
        XCTAssertEqual(tiles(at: noon + 5 * 3600 - 60).sky?.mistyLine, "Misty can see the whole street")
        XCTAssertEqual(tiles(at: noon + 5 * 3600).sky?.mistyLine, "Misty can see the stars")
        XCTAssertEqual(tiles(at: noon + 11 * 3600).sky?.mistyLine, "Misty can see the stars")
        // Before sunrise is dark too.
        XCTAssertEqual(tiles(at: noon - 6 * 3600).sky?.mistyLine, "Misty can see the stars")
        XCTAssertEqual(tiles(at: noon + 6 * 3600, cloudPercent: 50).sky?.mistyLine, "Misty can spot a few stars")
        XCTAssertEqual(tiles(at: noon + 6 * 3600, visibility: 800).sky?.mistyLine, "Misty can't see past the garden")
        // The headline doesn't change at night.
        XCTAssertEqual(tiles(at: noon + 6 * 3600).sky?.headline, tiles(at: noon).sky?.headline)
        // Without sun times it's never dark, and a forecast hour has no visibility, so no line.
        XCTAssertEqual(tiles(sunTimes: false, at: noon + 6 * 3600).sky?.mistyLine, "Misty can see the whole street")
        XCTAssertNil(tiles(showingForecast: true, at: noon + 6 * 3600).sky?.mistyLine)
    }

    // MARK: - Helpers

    private func tiles(
        pavementNow: Double? = nil,
        uvIndex: Double? = nil,
        air: AirQuality? = nil,
        hasDog: Bool = true,
        sunTimes: Bool = true,
        showingForecast: Bool = false,
        switches: TodayTileSwitches = TodayTileSwitches(),
        at time: Int? = nil,
        cloudPercent: Int = 10,
        visibility: Int = 10_000
    ) -> TodayTilesState {
        let sample = sampleWeather()
        var weather = CurrentWeather(
            cityName: sample.cityName,
            conditionMain: sample.conditionMain,
            description: sample.description,
            iconCode: sample.iconCode,
            temperature: sample.temperature,
            feelsLike: sample.feelsLike,
            tempMin: sample.tempMin,
            tempMax: sample.tempMax,
            humidityPercent: sample.humidityPercent,
            pressureHpa: sample.pressureHpa,
            windSpeed: sample.windSpeed,
            windDeg: sample.windDeg,
            visibilityMeters: visibility,
            cloudPercent: cloudPercent,
            units: sample.units,
            sunriseEpoch: nil,
            sunsetEpoch: nil,
            timezoneOffsetSeconds: sample.timezoneOffsetSeconds
        )
        weather.sunriseEpoch = sunTimes ? noon - 5 * 3600 : nil
        weather.sunsetEpoch = sunTimes ? noon + 5 * 3600 : nil
        return TodayTilesState(
            weather: weather,
            showingForecast: showingForecast,
            pavementNow: pavementNow,
            groundWet: false,
            uvIndex: uvIndex,
            uvPeak: nil,
            airQuality: air,
            hasDog: hasDog,
            now: Date(timeIntervalSince1970: TimeInterval(time ?? noon)),
            thresholds: .standard,
            distanceInMiles: false,
            switches: switches
        )
    }

    private func airTile(_ state: TodayTilesState) -> AirTile? {
        for tile in state.small { if case let .air(air) = tile { return air } }
        return nil
    }

    private static func name(_ tile: TodayTile) -> String {
        switch tile {
        case .feelsLike: "feelsLike"
        case .wind: "wind"
        case .fluff: "fluff"
        case .pawCheck: "pawCheck"
        case .uv: "uv"
        case .air: "air"
        }
    }
}
