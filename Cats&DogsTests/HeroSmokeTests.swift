import XCTest
@testable import Cats_Dogs

/// When the hero is drawn smoky. Same cases as Android's `HeroSmokeTest`.
final class HeroSmokeTests: XCTestCase {
    private func walk(_ factors: WalkFactor...) -> WalkCheck { WalkCheck(factors) }
    private func air(band: Int, _ pollutant: AirQuality.Pollutant?, _ level: WalkLevel) -> WalkFactor {
        WalkFactor(reason: .air(band: band, pollutant: pollutant), level: level)
    }

    func testHazeWhenSmokeMakesItPottyBreaksOnly() {
        XCTAssertEqual(HeroSmoke.from(walk: walk(air(band: 3, .fineParticles, .pottyOnly)), conditionMain: "Clear"), .haze)
        XCTAssertEqual(HeroSmoke.from(walk: walk(air(band: 4, .fineParticles, .pottyOnly)), conditionMain: "Clouds"), .haze)
    }

    func testAshAtTheWorstBand() {
        XCTAssertEqual(HeroSmoke.from(walk: walk(air(band: 5, .fineParticles, .stayIn)), conditionMain: "Clear"), .ash)
    }

    func testNotForAirThatsOnlyACaveatOrForOtherPollutants() {
        XCTAssertNil(HeroSmoke.from(walk: walk(air(band: 2, .fineParticles, .fine)), conditionMain: "Clear"))
        XCTAssertNil(HeroSmoke.from(walk: walk(air(band: 3, .coarseParticles, .pottyOnly)), conditionMain: "Clear"))
        XCTAssertNil(HeroSmoke.from(walk: walk(air(band: 5, .ozone, .stayIn)), conditionMain: "Clear"))
        XCTAssertNil(HeroSmoke.from(walk: walk(), conditionMain: "Clear"))
        XCTAssertNil(HeroSmoke.from(walk: nil, conditionMain: "Haze"))
    }

    func testFindsTheSmokeBehindAWorseReason() {
        let stormy = walk(
            WalkFactor(reason: .storms(likely: true), level: .stayIn),
            air(band: 3, .fineParticles, .pottyOnly)
        )
        XCTAssertEqual(HeroSmoke.from(walk: stormy, conditionMain: "Thunderstorm"), .haze)
    }

    func testOpenWeathersSmokeAndAshConditions() {
        XCTAssertEqual(HeroSmoke.from(walk: nil, conditionMain: "Smoke"), .haze)
        XCTAssertEqual(HeroSmoke.from(walk: nil, conditionMain: "Ash"), .ash)
        XCTAssertEqual(HeroSmoke.from(walk: walk(air(band: 5, .fineParticles, .stayIn)), conditionMain: "Smoke"), .ash)
    }
}
