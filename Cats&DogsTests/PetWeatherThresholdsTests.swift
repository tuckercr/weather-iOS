import XCTest
@testable import Cats_Dogs

@MainActor
final class PetWeatherThresholdsTests: XCTestCase {
    func testNoValuesGivesTheStandardThresholds() {
        XCTAssertEqual(PetWeatherThresholds.validated(), .standard)
        XCTAssertEqual(PetWeatherThresholds.standard.hotPavementC, 46)
        XCTAssertEqual(PetWeatherThresholds.standard.maxRainChance, 30)
        XCTAssertEqual(PetWeatherThresholds.standard.comfortC, 3 ... 27)
        XCTAssertEqual(PetWeatherThresholds.standard.walkHours, 7 ... 20)
        XCTAssertEqual(PetWeatherThresholds.standard.petHotC, 30)
        XCTAssertEqual(PetWeatherThresholds.standard.petColdC, 0)
    }

    func testInRangeValuesAreUsed() {
        let thresholds = PetWeatherThresholds.validated(
            hotPavementC: 48,
            maxRainChance: 50,
            comfortMinC: 0,
            comfortMaxC: 30,
            walkHoursStart: 6,
            walkHoursEnd: 21,
            petHotC: 32,
            petColdC: -2
        )

        XCTAssertEqual(thresholds.hotPavementC, 48)
        XCTAssertEqual(thresholds.maxRainChance, 50)
        XCTAssertEqual(thresholds.comfortC, 0 ... 30)
        XCTAssertEqual(thresholds.walkHours, 6 ... 21)
        XCTAssertEqual(thresholds.petHotC, 32)
        XCTAssertEqual(thresholds.petColdC, -2)
    }

    func testOutOfRangeValuesFallBackOneByOne() {
        let thresholds = PetWeatherThresholds.validated(
            hotPavementC: 90,
            maxRainChance: 101,
            comfortMinC: -30,
            comfortMaxC: 50,
            walkHoursStart: -1,
            walkHoursEnd: 24,
            petHotC: 60,
            petColdC: 15
        )

        XCTAssertEqual(thresholds, .standard)
    }

    func testInvertedPairsFallBackAsAPair() {
        let thresholds = PetWeatherThresholds.validated(
            comfortMinC: 20,
            comfortMaxC: 18,
            walkHoursStart: 21,
            walkHoursEnd: 8
        )

        XCTAssertEqual(thresholds.comfortC, PetWeatherThresholds.standard.comfortC)
        XCTAssertEqual(thresholds.walkHours, PetWeatherThresholds.standard.walkHours)
    }

    /// The hot and cold ranges don't overlap, so the pet pair can't end up inverted; its closest
    /// legal values are kept.
    func testThePetPairAtItsClosestIsKept() {
        let thresholds = PetWeatherThresholds.validated(petHotC: 20, petColdC: 10)

        XCTAssertEqual(thresholds.petHotC, 20)
        XCTAssertEqual(thresholds.petColdC, 10)
    }

    func testPavementTileThresholdsDefaultTo40And0AndUseInRangeValues() {
        XCTAssertEqual(PetWeatherThresholds.standard.warmPavementC, 40)
        XCTAssertEqual(PetWeatherThresholds.standard.icyPavementC, 0)

        let thresholds = PetWeatherThresholds.validated(warmPavementC: 40, icyPavementC: -5)

        XCTAssertEqual(thresholds.warmPavementC, 40)
        XCTAssertEqual(thresholds.icyPavementC, -5)
        XCTAssertEqual(PetWeatherThresholds.validated(warmPavementC: 80, icyPavementC: 20), .standard)
    }

    func testAWarmPavementThresholdAtOrAboveTheHotOneMovesBelowItLeavingTheHotOneAlone() {
        // walk_hot_pavement_c = 40 is valid; the standard warm threshold of 40 would never show.
        let thresholds = PetWeatherThresholds.validated(hotPavementC: 40)

        XCTAssertEqual(thresholds.hotPavementC, 40)
        XCTAssertEqual(thresholds.warmPavementC, 33)
    }

    func testDangerousPavementDefaultsTo135FAndUsesInRangeValues() {
        XCTAssertEqual(PetWeatherThresholds.standard.dangerousPavementC, 57.2)
        XCTAssertEqual(PetWeatherThresholds.validated(dangerousPavementC: 60).dangerousPavementC, 60)
        XCTAssertEqual(PetWeatherThresholds.validated(dangerousPavementC: 90).dangerousPavementC, 57.2)
    }

    func testADangerousPavementThresholdAtOrBelowTheHotOneMovesAboveItLeavingTheHotOneAlone() {
        // walk_hot_pavement_c = 60 is valid; the standard dangerous threshold of 57.2 would never show.
        let thresholds = PetWeatherThresholds.validated(hotPavementC: 60)

        XCTAssertEqual(thresholds.hotPavementC, 60)
        XCTAssertEqual(thresholds.dangerousPavementC, 65)
    }
}
