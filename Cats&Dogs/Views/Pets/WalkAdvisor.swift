import Foundation

enum WalkRating: Equatable {
    case great, okay, poor, pawsHot, tooCold, badAir
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
/// city's next day, since the label alone ("7 AM") doesn't say which morning. `pavementBand` is what
/// `pavementNow` means for paws (the Today tile's band), so the caption can say whether the pavement
/// is the problem. `outlook` is set only when now is a great time.
struct WalkAdvice: Equatable {
    let rating: WalkRating
    let bestTimeLabel: String?
    var pavementNow: Double? = nil
    var bestTimeIsTomorrow = false
    var pavementBand: TodayDetails.PavementBand? = nil
    var outlook: WalkOutlook? = nil
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
    /// `precipitatingNow` is the current observation. The hourly forecast can say the hour in
    /// progress is dry while it's raining, so when it's raining now, now is never the walk time.
    /// `sunsetEpoch` is today's sunset, for the "gets dark" line.
    static func advice(
        currentFeelsLikeC: Double,
        upcoming: [HourlySlot],
        now: Date = Date(),
        timeZone: TimeZone = .current,
        thresholds: PetWeatherThresholds = .standard,
        precipitatingNow: Bool = false,
        sunsetEpoch: Int? = nil
    ) -> WalkAdvice? {
        let horizon = Int(now.timeIntervalSince1970) + lookaheadSeconds
        let slots = upcoming.prefix(lookaheadSlots).filter { ($0.epochSeconds ?? 0) <= horizon }
        guard let first = slots.first else { return nil }
        let nowWalkable = !precipitatingNow && isWalkable(first, thresholds)
        let firstGood = (precipitatingNow ? Array(slots.dropFirst()) : slots).first { isWalkable($0, thresholds) }
        let pawsHotNow = (pavementC(first) ?? 0) >= thresholds.hotPavementC
        let rating: WalkRating = if currentFeelsLikeC >= thresholds.petHotC || pawsHotNow {
            .pawsHot
        } else if hasBadAir(first, thresholds) {
            .badAir
        } else if currentFeelsLikeC <= thresholds.petColdC {
            .tooCold
        } else if nowWalkable {
            .great
        } else if firstGood != nil {
            .okay
        } else {
            .poor
        }
        let bestSlot = rating == .great ? nil : firstGood
        return WalkAdvice(
            rating: rating,
            bestTimeLabel: bestSlot?.timeLabel,
            pavementNow: first.pavementTemperature,
            bestTimeIsTomorrow: bestSlot.map { isOnALaterDay($0, than: now, in: timeZone) } ?? false,
            pavementBand: pavementC(first).map {
                TodayDetails.pavementBand(
                    pavementC: $0,
                    groundWet: first.groundWet == true,
                    feelsLikeC: currentFeelsLikeC,
                    thresholds: thresholds
                )
            },
            outlook: rating == .great ? outlook(slots, sunsetEpoch: sunsetEpoch, now: now, thresholds) : nil
        )
    }

    /// For a walk now: when the good spell ends and why, if that's within a few hours. Otherwise air
    /// that's not quite bad, or sunset coming up.
    private static func outlook(
        _ slots: [HourlySlot],
        sunsetEpoch: Int?,
        now: Date,
        _ thresholds: PetWeatherThresholds
    ) -> WalkOutlook? {
        let nowEpoch = Int(now.timeIntervalSince1970)
        if let end = slots.dropFirst().first(where: { !isWalkable($0, thresholds) }),
           let epoch = end.epochSeconds, epoch <= nowEpoch + outlookSeconds,
           let change = change(at: end, thresholds) {
            return .until(time: end.timeLabel, change: change)
        }
        let band = slots.first?.airQuality?.band ?? 0
        if band >= 2, band < thresholds.badAirBand { return .moderateAir }
        if let sunsetEpoch, sunsetEpoch > nowEpoch, sunsetEpoch - nowEpoch <= darkSoonSeconds {
            return .darkIn(hours: Int((Double(sunsetEpoch - nowEpoch) / 3600).rounded()))
        }
        return nil
    }

    /// Why `slot` isn't walkable, as something worth saying. Nil for darkness and the end of the
    /// walking hours, which the sunset line covers.
    private static func change(at slot: HourlySlot, _ thresholds: PetWeatherThresholds) -> WalkChange? {
        guard isDaytime(slot, thresholds) else { return nil }
        if slot.precipitationChance >= thresholds.maxRainChance {
            let likely = slot.precipitationChance >= likelyRainChance
            return switch slot.iconCode.prefix(2) {
            case "11": likely ? .storms : .maybeStorms
            case "13": likely ? .snow : .maybeSnow
            default: likely ? .rain : .maybeRain
            }
        }
        if isTooWindy(slot, thresholds) { return .wind }
        if hasBadAir(slot, thresholds) { return .badAir }
        if (pavementC(slot) ?? 0) >= thresholds.warmPavementC { return .hotPavement }
        let feelsLikeC = slot.units.toCelsius(slot.feelsLike)
        if feelsLikeC > thresholds.comfortC.upperBound { return .heat }
        if feelsLikeC < thresholds.comfortC.lowerBound { return .cold }
        return nil
    }

    /// Compared as calendar days in the city's own time zone, not the device's.
    private static func isOnALaterDay(_ slot: HourlySlot, than now: Date, in timeZone: TimeZone) -> Bool {
        guard let epoch = slot.epochSeconds else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return !calendar.isDate(Date(timeIntervalSince1970: TimeInterval(epoch)), inSameDayAs: now)
    }

    /// Within the walking hours and in daylight. The walking hours alone are a fixed clock window, so
    /// on a winter morning 7 AM can be before sunrise; a night icon ("n", the same signal that puts
    /// the pets to sleep) rules it out.
    private static func isDaytime(_ slot: HourlySlot, _ thresholds: PetWeatherThresholds) -> Bool {
        (slot.localHour.map(thresholds.walkHours.contains) ?? true) && !slot.iconCode.hasSuffix("n")
    }

    private static func isTooWindy(_ slot: HourlySlot, _ thresholds: PetWeatherThresholds) -> Bool {
        TodayDetails.windForce(speed: slot.windSpeed, units: slot.units) >= thresholds.windyForce
    }

    private static func pavementC(_ slot: HourlySlot) -> Double? {
        slot.pavementTemperature.map(slot.units.toCelsius)
    }

    /// Air at the Remote Config band or worse (by default Unhealthy, the Air quality tile's "Potty
    /// breaks only today"). Unknown counts as clean.
    private static func hasBadAir(_ slot: HourlySlot, _ thresholds: PetWeatherThresholds) -> Bool {
        (slot.airQuality?.band ?? 0) >= thresholds.badAirBand
    }

    /// Bad air in a walking hour: an hour the walk advice would otherwise have weighed up.
    static func hasBadAirForWalking(_ slot: HourlySlot, _ thresholds: PetWeatherThresholds) -> Bool {
        isDaytime(slot, thresholds) && hasBadAir(slot, thresholds)
    }

    /// Feels-like rather than air temperature: humid heat and wind chill are what the dog feels.
    /// Pavement that's only getting hot already rules an hour out, so the suggested hour is a cooler one.
    static func isWalkable(_ slot: HourlySlot, _ thresholds: PetWeatherThresholds) -> Bool {
        isDaytime(slot, thresholds)
            && !hasBadAir(slot, thresholds)
            && !isTooWindy(slot, thresholds)
            && (pavementC(slot) ?? 0) < thresholds.warmPavementC
            && slot.precipitationChance < thresholds.maxRainChance
            && thresholds.comfortC.contains(slot.units.toCelsius(slot.feelsLike))
    }
}
