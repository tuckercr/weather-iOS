import Foundation

/// The moon's phase in eight steps, worked out from the date alone, so it needs no API. Same
/// calculation as the Android `MoonPhase`.
enum MoonPhase: Int, CaseIterable {
    case new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent

    private static let synodicMonthDays = 29.530588853
    /// A known new moon: 6 January 2000, 18:14 UTC.
    private static let referenceNewMoon: TimeInterval = 947_182_440

    /// The phase at `date`: the moon's age in its 29.5-day cycle, rounded to the nearest eighth.
    init(at date: Date) {
        let days = (date.timeIntervalSince1970 - Self.referenceNewMoon) / 86_400
        let age = (days.truncatingRemainder(dividingBy: Self.synodicMonthDays) + Self.synodicMonthDays)
            .truncatingRemainder(dividingBy: Self.synodicMonthDays)
        self = MoonPhase(rawValue: Int(age / Self.synodicMonthDays * 8 + 0.5) % 8)!
    }

    /// The terminator angle to draw, 0 for new to 180 for full. Crescent and gibbous are drawn a
    /// quarter and three quarters lit rather than at their mid-phase 15% / 85%, which at icon size
    /// look like new and full.
    var drawAngleDegrees: Double { [0, 60, 90, 120, 180, 240, 270, 300][rawValue] }

    var isWaxing: Bool { (1 ... 3).contains(rawValue) }
    var isGibbous: Bool { self == .waxingGibbous || self == .waningGibbous }
    /// New and full look the same everywhere; the others are lit from the other side down south.
    var differsInSouth: Bool { self != .new && self != .full }

    /// The asset-name suffix, matching the Android drawables ("waxing_crescent").
    var assetSuffix: String {
        ["new", "waxing_crescent", "first_quarter", "waxing_gibbous", "full", "waning_gibbous", "last_quarter", "waning_crescent"][rawValue]
    }
}
