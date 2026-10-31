import Foundation

enum WalkRating: Equatable {
    case great, okay, poor, pawsHot, tooCold, badAir
}

/// `bestTimeLabel` is nil when now is a good time, or when there is no good window soon.
/// `pavementNow` is the estimated pavement temperature for the current hour, in the forecast's
/// units, when the source provides it. `bestTimeIsTomorrow` is set when the best time falls on the
/// city's next day, since the label alone ("7 AM") doesn't say which morning. `pavementBand` is what
/// `pavementNow` means for paws (the Today tile's band), so the caption can say whether the pavement
/// is the problem.
struct WalkAdvice: Equatable {
    let rating: WalkRating
    let bestTimeLabel: String?
    var pavementNow: Double? = nil
    var bestTimeIsTomorrow = false
    var pavementBand: TodayDetails.PavementBand? = nil
}

enum WalkAdvisor {
    private static let lookaheadSlots = 24 // a day of hourly slots
    /// 24 three-hourly OpenWeatherMap slots would reach three days out, so the advice is also capped
    /// by time: the best time is always today or tomorrow.
    private static let lookaheadSeconds = 24 * 3600

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
    static func advice(
        currentFeelsLikeC: Double,
        upcoming: [HourlySlot],
        now: Date = Date(),
        timeZone: TimeZone = .current,
        thresholds: PetWeatherThresholds = .standard,
        precipitatingNow: Bool = false
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
            }
        )
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
            && (pavementC(slot) ?? 0) < thresholds.warmPavementC
            && slot.precipitationChance < thresholds.maxRainChance
            && thresholds.comfortC.contains(slot.units.toCelsius(slot.feelsLike))
    }
}
