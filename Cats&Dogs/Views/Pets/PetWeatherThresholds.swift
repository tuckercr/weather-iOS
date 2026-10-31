import Foundation

/// The judgement calls behind the pets' moods and the walk card, tunable from Remote Config. All
/// temperatures are Celsius whatever units the user picked.
struct PetWeatherThresholds: Equatable {
    /// Asphalt this hot burns paws in under a minute (about 125 F).
    var hotPavementC: Double
    /// A slot with this chance of rain or more isn't suggested for a walk.
    var maxRainChance: Int
    var comfortC: ClosedRange<Double>
    /// Nobody wants walk advice for 2 AM: only suggest slots in these local hours.
    var walkHours: ClosedRange<Int>
    var petHotC: Double
    var petColdC: Double
    /// Pavement at or above this (and below `hotPavementC`) is getting hot: keep walks short.
    var warmPavementC: Double = 45
    /// Pavement below this may be icy or salted.
    var icyPavementC: Double = 0
    /// Pavement at or above this (about 135 F) is dangerously hot: worse than `hotPavementC`.
    var dangerousPavementC: Double = 57.2
    /// Hours in this air quality band or worse aren't suggested for a walk: 3 is US "Unhealthy" and
    /// Europe's "Poor" (`AirQuality.band`, 0 to 5).
    var badAirBand: Int = 3

    static let standard = PetWeatherThresholds(
        hotPavementC: 52,
        maxRainChance: 30,
        comfortC: 3 ... 27,
        walkHours: 7 ... 20,
        petHotC: 30,
        petColdC: 0
    )

    static let hotPavementRangeC = 40.0 ... 70.0
    static let warmPavementRangeC = 30.0 ... 65.0
    static let icyPavementRangeC = -20.0 ... 10.0
    static let dangerousPavementRangeC = 45.0 ... 80.0
    /// How far below `hotPavementC` a warm threshold at or above it is moved.
    static let warmPavementGapC = 7.0
    /// How far above `hotPavementC` a dangerous threshold at or below it is moved.
    static let dangerousPavementGapC = 5.0
    static let maxRainChanceRange = 0 ... 100
    static let comfortMinRangeC = -20.0 ... 20.0
    static let comfortMaxRangeC = 15.0 ... 40.0
    static let walkHourRange = 0 ... 23
    static let petHotRangeC = 20.0 ... 45.0
    static let petColdRangeC = -20.0 ... 10.0
    /// 0 would rule out every hour, even in good air.
    static let badAirBandRange = 1 ... 5

    /// Builds thresholds from raw Remote Config values. A value that's missing or out of range falls
    /// back to the standard one, and a pair that ends up inverted falls back as a pair, so a console
    /// typo can never produce nonsense advice. A warm-pavement threshold at or above the hot one would
    /// never show, so it moves `warmPavementGapC` below it instead, and a dangerous one at or below it
    /// moves `dangerousPavementGapC` above it; the hot one drives the walk advice and is left alone.
    static func validated(
        hotPavementC: Double? = nil,
        warmPavementC: Double? = nil,
        icyPavementC: Double? = nil,
        dangerousPavementC: Double? = nil,
        maxRainChance: Int? = nil,
        comfortMinC: Double? = nil,
        comfortMaxC: Double? = nil,
        walkHoursStart: Int? = nil,
        walkHoursEnd: Int? = nil,
        petHotC: Double? = nil,
        petColdC: Double? = nil,
        badAirBand: Int? = nil
    ) -> PetWeatherThresholds {
        let standard = Self.standard
        let comfortMin = pick(comfortMinC, in: comfortMinRangeC, or: standard.comfortC.lowerBound)
        let comfortMax = pick(comfortMaxC, in: comfortMaxRangeC, or: standard.comfortC.upperBound)
        let hoursStart = pick(walkHoursStart, in: walkHourRange, or: standard.walkHours.lowerBound)
        let hoursEnd = pick(walkHoursEnd, in: walkHourRange, or: standard.walkHours.upperBound)
        let hot = pick(petHotC, in: petHotRangeC, or: standard.petHotC)
        let cold = pick(petColdC, in: petColdRangeC, or: standard.petColdC)
        let hotPavement = pick(hotPavementC, in: hotPavementRangeC, or: standard.hotPavementC)
        let warmPavement = pick(warmPavementC, in: warmPavementRangeC, or: standard.warmPavementC)
        let dangerousPavement = pick(dangerousPavementC, in: dangerousPavementRangeC, or: standard.dangerousPavementC)
        return PetWeatherThresholds(
            hotPavementC: hotPavement,
            maxRainChance: pick(maxRainChance, in: maxRainChanceRange, or: standard.maxRainChance),
            comfortC: comfortMin < comfortMax ? comfortMin ... comfortMax : standard.comfortC,
            walkHours: hoursStart < hoursEnd ? hoursStart ... hoursEnd : standard.walkHours,
            petHotC: cold < hot ? hot : standard.petHotC,
            petColdC: cold < hot ? cold : standard.petColdC,
            warmPavementC: warmPavement < hotPavement ? warmPavement : hotPavement - warmPavementGapC,
            icyPavementC: pick(icyPavementC, in: icyPavementRangeC, or: standard.icyPavementC),
            dangerousPavementC: dangerousPavement > hotPavement ? dangerousPavement : hotPavement + dangerousPavementGapC,
            badAirBand: pick(badAirBand, in: badAirBandRange, or: standard.badAirBand)
        )
    }

    private static func pick<Value: Comparable>(_ value: Value?, in range: ClosedRange<Value>, or fallback: Value) -> Value {
        guard let value, range.contains(value) else { return fallback }
        return value
    }
}
