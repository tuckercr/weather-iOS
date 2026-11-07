import Foundation

/// How good a time it is to walk the dog, best first. Every screen that speaks about walks (the walk
/// card, the hero's caption, the Air Quality tile, the notifications) reads it from `WalkCheck`
/// rather than judging the weather itself, so they can't disagree. Same as Android's `WalkLevel`.
enum WalkLevel: Int, Comparable, CaseIterable {
    /// Nothing in the way.
    case great
    /// A walk, with a caveat: air that's fine for most dogs but not older or flat-faced ones.
    case fine
    /// Not now, but nothing dangerous: rain, a near gale, warm pavement, chilly or warm air, dark.
    case wait
    /// Out for the essentials and straight back: hot pavement, too hot or cold, bad air, a gale.
    case pottyOnly
    /// Keep pets inside: dangerously hot pavement, the worst air, thunderstorms, storm force wind.
    case stayIn
    /// A danger to everyone, dog or not: hurricane force wind.
    case danger

    static func < (lhs: WalkLevel, rhs: WalkLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Why a walk isn't great, with what a card needs to say so ("Smoky air", "Gale force winds"). The
/// order of the cases is the order reasons at the same level are given in: rain before warm
/// pavement, so a wet hour isn't put down to hot paws, and heat before air before cold, as the walk
/// card has always put them.
enum WalkReason: Equatable {
    /// Thunderstorms now, or a chance of them at or above the walk limit (`likely` from
    /// `WalkAdvisor.likelyRainChance`).
    case storms(likely: Bool)
    case rain(likely: Bool)
    case snow(likely: Bool)
    /// Beaufort force, 0 (calm) to 12 (hurricane force).
    case wind(force: Int)
    case pavement(TodayDetails.PavementBand)
    /// Feels-like above the comfort range.
    case heat
    /// The air quality band (0 good to 5 worst) and the pollutant behind it, when known.
    case air(band: Int, pollutant: AirQuality.Pollutant?)
    /// Feels-like below the comfort range.
    case cold
    /// Before sunrise, after sunset, or outside the walking hours.
    case dark

    fileprivate var order: Int {
        switch self {
        case .storms: 0
        case .rain: 1
        case .snow: 2
        case .wind: 3
        case .pavement: 4
        case .heat: 5
        case .air: 6
        case .cold: 7
        case .dark: 8
        }
    }

    /// What the pollutant behind bad air is called, for captions and notifications: "Smoky air"
    /// for fine particles, "Dusty air" for coarse ones, "High ozone". Nil for the rest, which each
    /// screen words in its own way.
    static func airName(_ pollutant: AirQuality.Pollutant?) -> String? {
        switch pollutant {
        case .fineParticles: "Smoky air"
        case .coarseParticles: "Dusty air"
        case .ozone: "High ozone"
        default: nil
        }
    }
}

struct WalkFactor: Equatable {
    let reason: WalkReason
    let level: WalkLevel
}

/// The verdict on one hour: each thing that keeps a walk from great, worst first.
struct WalkCheck: Equatable {
    let factors: [WalkFactor]

    init(_ factors: [WalkFactor]) {
        self.factors = factors.sorted {
            $0.level != $1.level ? $0.level > $1.level : $0.reason.order < $1.reason.order
        }
    }

    /// Great when nothing's in the way, otherwise the worst factor's level.
    var level: WalkLevel { factors.first?.level ?? .great }
    /// The worst factor's reason; nil when it's great.
    var reason: WalkReason? { factors.first?.reason }
    /// Fine or better: a walk now.
    var isWalkable: Bool { level <= .fine }

    /// The air factor, when the air keeps the walk from great.
    var air: WalkFactor? {
        factors.first { if case .air = $0.reason { true } else { false } }
    }

    /// The pavement factor, when the pavement keeps the walk from great.
    var pavement: WalkFactor? {
        factors.first { if case .pavement = $0.reason { true } else { false } }
    }
}

/// The walk rules: one small rule per factor, and the check that puts them together. The hourly
/// look-ahead (`WalkAdvisor`), the notifications and the tiles all use these.
enum WalkConditions {
    /// Gale force (Beaufort 8, about 39 mph or 62 km/h) and up: potty breaks only.
    static let galeForce = 8
    /// Storm force (Beaufort 10, about 55 mph or 89 km/h) and up: keep pets inside.
    static let stormForce = 10
    /// Hurricane force (Beaufort 12, 73 mph or 118 km/h and up): a danger to everyone.
    static let hurricaneForce = 12

    /// The verdict on `slot`. For the hour under way, the current reading stands in for the hour's
    /// forecast: `feelsLikeC` is its feels-like (what the dog feels now), `conditionNow` its condition
    /// group ("Rain", "Thunderstorm"), since the hour's forecast can say dry while it's raining,
    /// `windForceNow` and `gustForceNow` its wind and gusts (Beaufort), as the Wind tile shows them,
    /// and `darkNow` the clock's word on darkness, since the hour the sun sets in keeps its daytime
    /// icon.
    static func check(
        _ slot: HourlySlot,
        thresholds: PetWeatherThresholds,
        feelsLikeC: Double? = nil,
        conditionNow: String? = nil,
        windForceNow: Int? = nil,
        gustForceNow: Int? = nil,
        darkNow: Bool = false
    ) -> WalkCheck {
        WalkCheck(factors(
            slot,
            thresholds: thresholds,
            feelsLikeC: feelsLikeC,
            conditionNow: conditionNow,
            windForceNow: windForceNow,
            gustForceNow: gustForceNow,
            darkNow: darkNow
        ))
    }

    /// Fine or better, without sorting the factors: the hourly look-ahead and the notifications ask
    /// this of every hour.
    static func isWalkable(_ slot: HourlySlot, _ thresholds: PetWeatherThresholds) -> Bool {
        factors(slot, thresholds: thresholds).allSatisfy { $0.level <= .fine }
    }

    /// The factors `check` sorts. Hurricane force gusts count as hurricane force wind, since they're
    /// what makes a storm dangerous; otherwise gusts are left to the Wind tile.
    private static func factors(
        _ slot: HourlySlot,
        thresholds: PetWeatherThresholds,
        feelsLikeC: Double? = nil,
        conditionNow: String? = nil,
        windForceNow: Int? = nil,
        gustForceNow: Int? = nil,
        darkNow: Bool = false
    ) -> [WalkFactor] {
        let feelsLikeC = feelsLikeC ?? slot.units.toCelsius(slot.feelsLike)
        var factors: [WalkFactor] = []
        func add(_ reason: WalkReason, _ level: WalkLevel?) {
            if let level, level > .great { factors.append(WalkFactor(reason: reason, level: level)) }
        }
        if darkNow || !isWalkingTime(slot, thresholds) { add(.dark, .wait) }
        if let (reason, level) = precipitation(slot, conditionNow: conditionNow, thresholds) { add(reason, level) }
        var force = windForceNow ?? TodayDetails.windForce(speed: slot.windSpeed, units: slot.units)
        if (gustForceNow ?? 0) >= hurricaneForce { force = max(force, hurricaneForce) }
        add(.wind(force: force), windLevel(force: force, thresholds))
        // Air quality switched off in Remote Config leaves the air out, even from a forecast cached
        // before it went off.
        if thresholds.airQualityEnabled, let air = slot.airQuality {
            add(.air(band: air.band, pollutant: air.mainPollutant), airLevel(band: air.band, thresholds))
        }
        if let pavement = slot.pavementTemperature {
            let band = TodayDetails.pavementBand(
                pavementC: slot.units.toCelsius(pavement),
                groundWet: slot.groundWet == true,
                feelsLikeC: feelsLikeC,
                thresholds: thresholds
            )
            add(.pavement(band), pavementLevel(band))
        }
        if feelsLikeC >= thresholds.petHotC {
            add(.heat, .pottyOnly)
        } else if feelsLikeC > thresholds.comfortC.upperBound {
            add(.heat, .wait)
        } else if feelsLikeC <= thresholds.petColdC {
            add(.cold, .pottyOnly)
        } else if feelsLikeC < thresholds.comfortC.lowerBound {
            add(.cold, .wait)
        }
        return factors
    }

    /// The Remote Config band (by default 3, US "Unhealthy" and Europe's "Poor") and up is potty
    /// breaks only, and the worst band (5) keeps pets inside. From 2 up to the band below it is a
    /// walk with a caveat for older and flat-faced dogs. 0 and 1 are nothing to mention.
    static func airLevel(band: Int, _ thresholds: PetWeatherThresholds) -> WalkLevel {
        if band >= 5 { return .stayIn }
        if band >= thresholds.badAirBand { return .pottyOnly }
        if band >= 2 { return .fine }
        return .great
    }

    /// Too windy for a walk from `windyForce` (a near gale), then the Beaufort scale's own steps.
    static func windLevel(force: Int, _ thresholds: PetWeatherThresholds) -> WalkLevel {
        if force >= hurricaneForce { return .danger }
        if force >= stormForce { return .stayIn }
        if force >= galeForce { return .pottyOnly }
        if force >= thresholds.windyForce { return .wait }
        return .great
    }

    static func pavementLevel(_ band: TodayDetails.PavementBand) -> WalkLevel {
        switch band {
        case .dangerous: .stayIn
        case .tooHot: .pottyOnly
        case .warm: .wait
        case .safe, .pavementOK, .freezing, .icy: .great
        }
    }

    /// Rain, snow or storms now (`conditionNow`), or a chance of them at or above the walk limit,
    /// whichever is worse: drizzle now under an hour of likely thunderstorms is storms. Storms that
    /// are happening or likely keep pets inside; the rest is a wait for a dry spell.
    private static func precipitation(
        _ slot: HourlySlot,
        conditionNow: String?,
        _ thresholds: PetWeatherThresholds
    ) -> (WalkReason, WalkLevel)? {
        let now: (WalkReason, WalkLevel)? = switch conditionNow?.lowercased() {
        case "thunderstorm": (.storms(likely: true), .stayIn)
        case "snow": (.snow(likely: true), .wait)
        case "rain", "drizzle": (.rain(likely: true), .wait)
        default: nil
        }
        var forecast: (WalkReason, WalkLevel)?
        if slot.precipitationChance >= thresholds.maxRainChance {
            let likely = slot.precipitationChance >= WalkAdvisor.likelyRainChance
            forecast = switch slot.iconCode.prefix(2) {
            case "11": (.storms(likely: likely), likely ? .stayIn : .wait)
            case "13": (.snow(likely: likely), .wait)
            default: (.rain(likely: likely), .wait)
            }
        }
        guard let now else { return forecast }
        guard let forecast, forecast.1 > now.1 else { return now }
        return forecast
    }

    /// Within the walking hours and in daylight. The walking hours alone are a fixed clock window, so
    /// on a winter morning 7 AM can be before sunrise; a night icon ("n", the same signal that puts
    /// the pets to sleep) rules it out.
    static func isWalkingTime(_ slot: HourlySlot, _ thresholds: PetWeatherThresholds) -> Bool {
        (slot.localHour.map(thresholds.walkHours.contains) ?? true) && !slot.iconCode.hasSuffix("n")
    }
}
