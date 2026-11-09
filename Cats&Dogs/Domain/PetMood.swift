import Foundation

/// How Sunny (the dog) and Misty (the cat) react on the home screen, derived from the current conditions.
enum PetMood: CaseIterable {
    /// `fair` is a clear day that's chilly or mild, `sunny` a clear day that's warm (sunglasses on).
    case fair, sunny, cloudy, rain, storm, snow, hot, cold, night

    /// Precipitation and storms win over temperature, temperature extremes win over time of day,
    /// and an OpenWeatherMap icon ending in "n" means night. Hot and cold go by the feels-like
    /// temperature, since humid heat and wind chill are what pets feel, and a clear day is warm by
    /// the Feels Like tile's bands (above the walk comfort range). Same rules as Android's
    /// `PetMood.forConditions`.
    /// The pets' mood for `weather` at `now`: day or night by the clock, so a reading cached before
    /// sunset doesn't show the daytime pets. What the hero shows.
    static func forReading(_ weather: CurrentWeather, at now: Date, thresholds: PetWeatherThresholds) -> PetMood {
        forConditions(
            conditionMain: weather.conditionMain,
            iconCode: StaleWeather.iconCode(weather, at: now),
            feelsLikeC: weather.units.toCelsius(weather.feelsLike),
            thresholds: thresholds
        )
    }

    /// The pets' mood in the forecast hour `slot`, for a briefing planned ahead for it.
    static func forHour(_ slot: HourlySlot, thresholds: PetWeatherThresholds) -> PetMood {
        forConditions(
            conditionMain: StaleWeather.conditionMain(forIcon: slot.iconCode),
            iconCode: slot.iconCode,
            feelsLikeC: slot.units.toCelsius(slot.feelsLike),
            thresholds: thresholds
        )
    }

    static func forConditions(
        conditionMain: String,
        iconCode: String,
        feelsLikeC: Double,
        thresholds: PetWeatherThresholds = .standard
    ) -> PetMood {
        switch conditionMain.lowercased() {
        case "thunderstorm": return .storm
        case "snow": return .snow
        case "rain", "drizzle": return .rain
        default:
            if feelsLikeC >= thresholds.petHotC { return .hot }
            if feelsLikeC <= thresholds.petColdC { return .cold }
            if iconCode.hasSuffix("n") { return .night }
            if conditionMain.caseInsensitiveCompare("clear") == .orderedSame {
                let band = TodayDetails.feelsLikeBand(feelsLikeC: feelsLikeC, thresholds: thresholds)
                return band == .warm ? .sunny : .fair
            }
            return .cloudy
        }
    }

    /// Captions in the pets' voice. One is picked per day so it varies without changing on refresh.
    /// Night has a set for each part of it, so a 3 AM caption doesn't suggest an evening stroll.
    /// Without a dog (Settings' Dog walking off), the captions leave out walks.
    func captions(nightPart: NightPart = .evening, hasDog: Bool = true) -> [String] {
        if !hasDog, let noDog = noDogCaptions(nightPart: nightPart) { return noDog }
        return switch self {
        case .fair: [
            Self.perfectWalkies,
            String(localized: "Misty has claimed the sunniest windowsill.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Sunshine and tail wags all round.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .sunny: [
            String(localized: "Sunglasses on. It's a warm one today.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Warm out. Shady walks and plenty of water.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Misty has claimed the sunniest windowsill.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .cloudy: [
            Self.stillKeenForAWalk,
            String(localized: "Nap weather, says Misty.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            Self.stillTimeForAStroll,
        ]
        case .rain: [
            String(localized: "Sunny wants puddles. Misty wants a towel.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Grab a raincoat. Misty is NOT going out in this.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Wet paws ahead. Keep a towel by the door.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .storm: [
            String(localized: "Thunder! Misty is under the bed. Keep pets inside.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Stormy out there. Sofa cuddles today.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .snow: [
            String(localized: "Snow zoomies, then straight back to the blanket.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Wipe those paws when you come in.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .hot: [
            String(localized: "Too hot for long walks. Plenty of water today.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Fresh water bowls today. It is a scorcher.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .cold: [
            String(localized: "Brrr. Short walks and warm blankets.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Coat weather for small dogs today.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .night:
            switch nightPart {
            case .evening: [
                Self.oneLastStroll,
                Self.oneMoreLap,
            ]
            case .lateNight: [
                String(localized: "Sunny and Misty are curled up asleep.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
                String(localized: "Lights out. Misty has claimed the warm spot.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            ]
            case .beforeDawn: [
                String(localized: "Still dark out. Sunny is already waiting by the door.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
                String(localized: "Too dark to get up, says Misty. She's pretending to be asleep.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            ]
            }
        }
    }

    /// The captions above with the walks and paw care swapped for things Misty would do. Nil for
    /// storm and late night, which have no walks and keep their own.
    private func noDogCaptions(nightPart: NightPart) -> [String]? {
        switch self {
        case .fair: [
            String(localized: "Lovely day out. Misty will supervise from the window.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Misty has claimed the sunniest windowsill.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Sunshine and tail wags all round.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .sunny: [
            String(localized: "Sunglasses on. It's a warm one today.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Warm out. Misty has found the coolest spot in the house.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Misty has claimed the sunniest windowsill.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .cloudy: [
            String(localized: "A bit grey. Misty says it's a blanket sort of day.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Nap weather, says Misty.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "No sun, no problem. The birds are still out, says Misty.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .rain: [
            String(localized: "Rain on the window. Misty is watching every drop.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Grab a raincoat. Misty is NOT going out in this.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Wet out there. Misty has found the warmest lap in the house.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .storm: nil
        case .snow: [
            String(localized: "Snow zoomies, then straight back to the blanket.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Misty is watching the snow from somewhere warm.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .hot: [
            String(localized: "Too hot to move, says Misty. She's found the cool tiles.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Fresh water bowls today. It is a scorcher.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .cold: [
            String(localized: "Brrr. Warm blankets all round.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            String(localized: "Coat weather today. Misty is staying by the radiator.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
        ]
        case .night:
            switch nightPart {
            case .evening: [
                String(localized: "Quiet night. Misty is doing her evening rounds.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
                String(localized: "Evening zoomies, courtesy of Misty.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            ]
            case .lateNight: nil
            case .beforeDawn: [
                String(localized: "Still dark out. Misty wants breakfast anyway.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
                String(localized: "Too dark to get up, says Misty. She's pretending to be asleep.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat."),
            ]
            }
        }
    }

    /// Today's caption, chosen by the city's own date and (at night) hour, not the device's. When
    /// `walk` says now isn't the time for a walk (for anything but the dark, which the night
    /// captions allow for), the captions that suggest one are left out, and if that leaves none,
    /// the captions without a dog stand in.
    func caption(
        on date: Date = Date(),
        timeZone: TimeZone = .current,
        hasDog: Bool = true,
        walk: WalkCheck? = nil
    ) -> String {
        let calendar = Self.calendar(timeZone)
        let nightPart = NightPart(hour: calendar.component(.hour, from: date))
        var options = captions(nightPart: nightPart, hasDog: hasDog)
        if let walk, walk.factors.contains(where: { $0.reason != .dark && $0.level >= .wait }) {
            let quiet = options.filter { !Self.walkSuggestions.contains($0) }
            options = quiet.isEmpty ? noDogCaptions(nightPart: nightPart) ?? options : quiet
        }
        return Self.pick(options, on: date, calendar)
    }

    /// The captions that suggest a walk now, which `caption` leaves out when now isn't the time.
    /// Each is written once, here, and `captions` uses the same constant.
    private static let perfectWalkies = String(localized: "Perfect walkies weather! Off we go.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat. It suggests a walk now.")
    private static let stillKeenForAWalk = String(localized: "A bit grey, but Sunny is still keen for a walk.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat. It suggests a walk now.")
    private static let stillTimeForAStroll = String(localized: "No sun, no problem. Still time for a stroll.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat. It suggests a walk now.")
    private static let oneLastStroll = String(localized: "Quiet night. Time for one last stroll before bed?", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat. It suggests a walk now.")
    private static let oneMoreLap = String(localized: "Sunny thinks there's time for one more lap of the block.", comment: "Hero caption in the pets' voice. Sunny is the dog, Misty the cat. It suggests a walk now.")
    static let walkSuggestions: Set<String> = [
        perfectWalkies, stillKeenForAWalk, stillTimeForAStroll, oneLastStroll, oneMoreLap,
    ]

    /// The hero's caption: the walk's reason when it's one the scene can't show, then a seasonal
    /// theme's caption on its day, otherwise the weather's, leaving out walks when now isn't the time.
    static func heroCaption(
        walk: WalkCheck?,
        hasDog: Bool,
        themeCaption: String?,
        mood: PetMood,
        on date: Date,
        timeZone: TimeZone
    ) -> String {
        walk.flatMap { walkCaption($0, hasDog: hasDog, on: date, timeZone: timeZone) }
            ?? themeCaption
            ?? mood.caption(on: date, timeZone: timeZone, hasDog: hasDog, walk: walk)
    }

    /// When `walk` rules out more than a wait for a reason the scene can't show (the air, the
    /// pavement, a gale or worse), the caption gives the reason instead of the weather: "Smoky air
    /// today. Quick potty breaks, then back on the sofa." Nil otherwise. It takes the place of a
    /// seasonal theme's caption too. Without a dog the check has no pavement in it.
    static func walkCaption(
        _ walk: WalkCheck,
        hasDog: Bool,
        on date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String? {
        walkCaptions(walk, hasDog: hasDog).map { pick($0, on: date, calendar(timeZone)) }
    }

    static func walkCaptions(_ walk: WalkCheck, hasDog: Bool) -> [String]? {
        guard let worst = walk.factors.first, worst.level >= .pottyOnly else { return nil }
        switch worst.reason {
        case let .wind(force):
            if force >= WalkConditions.hurricaneForce {
                return [String(localized: "Hurricane force winds! Everyone inside, away from the windows.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat.")]
            }
            if force >= WalkConditions.stormForce {
                return [String(localized: "Storm force winds. Everyone stays in today.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat."), String(localized: "Misty is under the bed until this wind drops.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat.")]
            }
            return hasDog
                ? [String(localized: "Gale force winds! Quick potty breaks, then back in.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat."), String(localized: "Blowy out there. Misty won't go near the door.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat.")]
                : [String(localized: "Gale force winds! Misty won't go near the door.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat."), String(localized: "Blowy out there. Misty is staying put.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat.")]
        case let .air(_, pollutant):
            let air = WalkReason.airName(pollutant) ?? String(localized: "Poor air", comment: "Bad air of no particular kind, at the start of a sentence (Poor air today.)")
            return hasDog
                ? [String(localized: "\(air) today. Quick potty breaks, then back on the sofa.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat."), String(localized: "The air's not great. Sunny's big walk can wait.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat.")]
                : [String(localized: "\(air) today. Misty's keeping the windows shut.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat."), String(localized: "The air's not great. Misty is happy indoors.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat.")]
        case .pavement:
            return [String(localized: "Hot pavement! Sunny's sticking to the grass today.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat."), String(localized: "Too hot underfoot. Short trips on the grass.", comment: "Hero caption in the pets' voice when the wind, air or pavement rules out a walk. Sunny is the dog, Misty the cat.")]
        default:
            return nil
        }
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// One per day, so the caption varies without changing on refresh.
    private static func pick(_ options: [String], on date: Date, _ calendar: Calendar) -> String {
        options[(calendar.ordinality(of: .day, in: .year, for: date) ?? 1) % options.count]
    }
}

/// The part of the night it is, by the city's local hour. The night scene runs from sunset to
/// sunrise, so any night hour before noon is before dawn and any after noon is evening.
enum NightPart: Equatable {
    case evening, lateNight, beforeDawn

    init(hour: Int) {
        switch hour {
        case 23, 0 ..< 5: self = .lateNight
        case 5 ..< 12: self = .beforeDawn
        default: self = .evening
        }
    }
}
