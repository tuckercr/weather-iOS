import Foundation

/// The walk card's headline category: `WalkCheck`'s verdict on now, and whether there's a better
/// time. `windy` is a gale or worse, `stormy` thunderstorms now or likely, and `danger` hurricane
/// force wind, which the card shows as a warning even without a dog.
enum WalkRating: Equatable {
    case great, okay, poor, pawsHot, tooCold, badAir, windy, stormy, danger
}

/// What changes after a walk window that's open now, for the card's second line.
enum WalkOutlook: Equatable {
    /// Good until `time`, then `change`.
    case until(time: String, change: WalkChange)
    /// Sunset in about `hours` (0 is under half an hour).
    case darkIn(hours: Int)
    /// Air a band short of bad: fine for most dogs, not for older or flat-faced ones.
    case moderateAir
}

/// Why the walk window ends. The "maybe" kinds are a chance of rain at or above the walk limit but
/// under `WalkAdvisor.likelyRainChance`.
enum WalkChange: Equatable {
    case storms, maybeStorms, rain, maybeRain, snow, maybeSnow, wind, heat, hotPavement, cold, badAir
}

/// `bestTimeLabel` is nil when now is a good time, or when there is no good window soon.
/// `pavementNow` is the estimated pavement temperature for the current hour, in the forecast's
/// units, when the source provides it. `bestTimeIsTomorrow` is set when the best time falls on the
/// city's next day, since the label alone ("7 AM") doesn't say which morning. `outlook` is set only
/// when now is a great time. `now` is the verdict on the hour under way, which `rating` sums up and
/// whose reason the card's caption gives.
struct WalkAdvice: Equatable {
    let rating: WalkRating
    let bestTimeLabel: String?
    var pavementNow: Double? = nil
    var bestTimeIsTomorrow = false
    var outlook: WalkOutlook? = nil
    var now = WalkCheck([])
}

enum WalkAdvisor {
    private static let lookaheadSlots = 24 // a day of hourly slots
    /// 24 three-hourly OpenWeatherMap slots would reach three days out, so the advice is also capped
    /// by time: the best time is always today or tomorrow.
    private static let lookaheadSeconds = 24 * 3600
    /// A walk window is only described when it closes within this long; further out it isn't news.
    private static let outlookSeconds = 6 * 3600
    /// Sunset this close is worth a mention.
    private static let darkSoonSeconds = 3 * 3600
    /// A chance of rain at or above this is "rain"; from the walk limit up to it, "maybe rain".
    static let likelyRainChance = 60

    /// Whether the current conditions are rain, drizzle, snow or a thunderstorm (as `PetMood` reads them).
    static func isPrecipitating(conditionMain: String) -> Bool {
        ["thunderstorm", "snow", "rain", "drizzle"].contains(conditionMain.lowercased())
    }

    /// Works out when to walk the dog from the current feels-like temperature and the upcoming hourly slots
    /// (the first slot is the current or next forecast hour, so it stands in for "now"). Returns nil
    /// when there are no slots yet (forecast loading or failed), since there is nothing to advise on.
    ///
    /// `conditionNow` is the current observation's condition group ("Rain", "Thunderstorm"). The
    /// hourly forecast can say the hour in progress is dry while it's raining, so when it's raining
    /// now, now is never the walk time. `sunsetEpoch` is today's sunset, for the "gets dark" line.
    /// `darkNow` is the clock's word on darkness: the hour in progress keeps its daytime icon for the
    /// whole hour the sun sets in, so without it now could be "a great time" for up to an hour after
    /// dark.
    static func advice(
        currentFeelsLikeC: Double,
        upcoming: [HourlySlot],
        now: Date = Date(),
        timeZone: TimeZone = .current,
        thresholds: PetWeatherThresholds = .standard,
        conditionNow: String? = nil,
        sunsetEpoch: Int? = nil,
        darkNow: Bool = false
    ) -> WalkAdvice? {
        let horizon = Int(now.timeIntervalSince1970) + lookaheadSeconds
        let slots = upcoming.prefix(lookaheadSlots).filter { ($0.epochSeconds ?? 0) <= horizon }
        guard let first = slots.first else { return nil }
        let check = WalkConditions.check(
            first,
            thresholds: thresholds,
            feelsLikeC: currentFeelsLikeC,
            conditionNow: conditionNow,
            darkNow: darkNow
        )
        let firstGood = slots.dropFirst().first { isWalkable($0, thresholds) }
        let rating = rating(check, hasBetterTime: firstGood != nil)
        let bestSlot = rating == .great ? nil : firstGood
        return WalkAdvice(
            rating: rating,
            bestTimeLabel: bestSlot?.timeLabel,
            pavementNow: first.pavementTemperature,
            bestTimeIsTomorrow: bestSlot.map { isOnALaterDay($0, than: now, in: timeZone) } ?? false,
            outlook: rating == .great ? outlook(slots, check: check, sunsetEpoch: sunsetEpoch, now: now, thresholds) : nil,
            now: check
        )
    }

    /// Potty breaks only or worse says why; otherwise it's a walk now, a later walk, or no walk today.
    static func rating(_ check: WalkCheck, hasBetterTime: Bool) -> WalkRating {
        if check.level == .danger { return .danger }
        if check.level >= .pottyOnly, let reason = check.reason {
            switch reason {
            case .pavement, .heat: return .pawsHot
            case .air: return .badAir
            case .cold: return .tooCold
            case .wind: return .windy
            case .storms: return .stormy
            case .rain, .snow, .dark: break
            }
        }
        if check.isWalkable { return .great }
        return hasBetterTime ? .okay : .poor
    }

    /// For a walk now: when the good spell ends and why, if that's within a few hours. Otherwise air
    /// that's not quite bad, or sunset coming up.
    private static func outlook(
        _ slots: [HourlySlot],
        check: WalkCheck,
        sunsetEpoch: Int?,
        now: Date,
        _ thresholds: PetWeatherThresholds
    ) -> WalkOutlook? {
        let nowEpoch = Int(now.timeIntervalSince1970)
        if let end = slots.dropFirst().first(where: { !isWalkable($0, thresholds) }),
           let epoch = end.epochSeconds, epoch <= nowEpoch + outlookSeconds,
           let change = change(WalkConditions.check(end, thresholds: thresholds)) {
            return .until(time: end.timeLabel, change: change)
        }
        if check.air?.level == .fine { return .moderateAir }
        if let sunsetEpoch, sunsetEpoch > nowEpoch, sunsetEpoch - nowEpoch <= darkSoonSeconds {
            return .darkIn(hours: Int((Double(sunsetEpoch - nowEpoch) / 3600).rounded()))
        }
        return nil
    }

    /// Why an hour that isn't walkable isn't, as something worth saying. Nil after dark and outside
    /// the walking hours, which the sunset line covers.
    private static func change(_ check: WalkCheck) -> WalkChange? {
        guard !check.factors.contains(where: { $0.reason == .dark }), let reason = check.reason else { return nil }
        return switch reason {
        case let .storms(likely): likely ? .storms : .maybeStorms
        case let .rain(likely): likely ? .rain : .maybeRain
        case let .snow(likely): likely ? .snow : .maybeSnow
        case .wind: .wind
        case .pavement: .hotPavement
        case .heat: .heat
        case .air: .badAir
        case .cold: .cold
        case .dark: nil
        }
    }

    /// Compared as calendar days in the city's own time zone, not the device's.
    private static func isOnALaterDay(_ slot: HourlySlot, than now: Date, in timeZone: TimeZone) -> Bool {
        guard let epoch = slot.epochSeconds else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return !calendar.isDate(Date(timeIntervalSince1970: TimeInterval(epoch)), inSameDayAs: now)
    }

    /// Bad air (potty breaks only or worse, by default from Unhealthy) in a walking hour: an hour the
    /// walk advice would otherwise have weighed up. Unknown air counts as clean.
    static func hasBadAirForWalking(_ slot: HourlySlot, _ thresholds: PetWeatherThresholds) -> Bool {
        guard WalkConditions.isWalkingTime(slot, thresholds), let band = slot.airQuality?.band else { return false }
        return WalkConditions.airLevel(band: band, thresholds) >= .pottyOnly
    }

    /// `WalkCheck`'s verdict on the hour: fine or better. Feels-like rather than air temperature,
    /// since humid heat and wind chill are what the dog feels, and pavement that's only getting hot
    /// already rules an hour out, so the suggested hour is a cooler one.
    static func isWalkable(_ slot: HourlySlot, _ thresholds: PetWeatherThresholds) -> Bool {
        WalkConditions.check(slot, thresholds: thresholds).isWalkable
    }
}
