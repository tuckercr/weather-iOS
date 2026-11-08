import SwiftUI

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

    /// The hero card background. It keeps this light palette in dark mode too, so text on it
    /// always uses `ink`.
    var skyColor: Color {
        switch self {
        case .fair: Color(hex: 0xFCE7B4)
        case .sunny: Color(hex: 0xFAC775)
        case .cloudy: Color(hex: 0xB3DDF2)
        case .rain: Color(hex: 0x81C7EC)
        case .storm: Color(hex: 0x9FB3C8)
        case .snow: Color(hex: 0xE6F1FB)
        case .hot: Color(hex: 0xF5C4B3)
        case .cold: Color(hex: 0xCFE3F5)
        case .night: Color(hex: 0x3C4A78)
        }
    }

    var ink: Color {
        self == .night ? Color(hex: 0xF1EFE8) : Color(hex: 0x0C447C)
    }

    /// Captions in the pets' voice. One is picked per day so it varies without changing on refresh.
    /// Night has a set for each part of it, so a 3 AM caption doesn't suggest an evening stroll.
    /// Without a dog (Settings' Dog walking off), the captions leave out walks.
    func captions(nightPart: NightPart = .evening, hasDog: Bool = true) -> [String] {
        if !hasDog, let noDog = noDogCaptions(nightPart: nightPart) { return noDog }
        return switch self {
        case .fair: [
            Self.perfectWalkies,
            "Misty has claimed the sunniest windowsill.",
            "Sunshine and tail wags all round.",
        ]
        case .sunny: [
            "Sunglasses on. It's a warm one today.",
            "Warm out. Shady walks and plenty of water.",
            "Misty has claimed the sunniest windowsill.",
        ]
        case .cloudy: [
            Self.stillKeenForAWalk,
            "Nap weather, says Misty.",
            Self.stillTimeForAStroll,
        ]
        case .rain: [
            "Sunny wants puddles. Misty wants a towel.",
            "Grab a raincoat. Misty is NOT going out in this.",
            "Wet paws ahead. Keep a towel by the door.",
        ]
        case .storm: [
            "Thunder! Misty is under the bed. Keep pets inside.",
            "Stormy out there. Sofa cuddles today.",
        ]
        case .snow: [
            "Snow zoomies, then straight back to the blanket.",
            "Wipe those paws when you come in.",
        ]
        case .hot: [
            "Too hot for long walks. Plenty of water today.",
            "Fresh water bowls today. It is a scorcher.",
        ]
        case .cold: [
            "Brrr. Short walks and warm blankets.",
            "Coat weather for small dogs today.",
        ]
        case .night:
            switch nightPart {
            case .evening: [
                Self.oneLastStroll,
                Self.oneMoreLap,
            ]
            case .lateNight: [
                "Sunny and Misty are curled up asleep.",
                "Lights out. Misty has claimed the warm spot.",
            ]
            case .beforeDawn: [
                "Still dark out. Sunny is already waiting by the door.",
                "Too dark to get up, says Misty. She's pretending to be asleep.",
            ]
            }
        }
    }

    /// The captions above with the walks and paw care swapped for things Misty would do. Nil for
    /// storm and late night, which have no walks and keep their own.
    private func noDogCaptions(nightPart: NightPart) -> [String]? {
        switch self {
        case .fair: [
            "Lovely day out. Misty will supervise from the window.",
            "Misty has claimed the sunniest windowsill.",
            "Sunshine and tail wags all round.",
        ]
        case .sunny: [
            "Sunglasses on. It's a warm one today.",
            "Warm out. Misty has found the coolest spot in the house.",
            "Misty has claimed the sunniest windowsill.",
        ]
        case .cloudy: [
            "A bit grey. Misty says it's a blanket sort of day.",
            "Nap weather, says Misty.",
            "No sun, no problem. The birds are still out, says Misty.",
        ]
        case .rain: [
            "Rain on the window. Misty is watching every drop.",
            "Grab a raincoat. Misty is NOT going out in this.",
            "Wet out there. Misty has found the warmest lap in the house.",
        ]
        case .storm: nil
        case .snow: [
            "Snow zoomies, then straight back to the blanket.",
            "Misty is watching the snow from somewhere warm.",
        ]
        case .hot: [
            "Too hot to move, says Misty. She's found the cool tiles.",
            "Fresh water bowls today. It is a scorcher.",
        ]
        case .cold: [
            "Brrr. Warm blankets all round.",
            "Coat weather today. Misty is staying by the radiator.",
        ]
        case .night:
            switch nightPart {
            case .evening: [
                "Quiet night. Misty is doing her evening rounds.",
                "Evening zoomies, courtesy of Misty.",
            ]
            case .lateNight: nil
            case .beforeDawn: [
                "Still dark out. Misty wants breakfast anyway.",
                "Too dark to get up, says Misty. She's pretending to be asleep.",
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
    private static let perfectWalkies = "Perfect walkies weather! Off we go."
    private static let stillKeenForAWalk = "A bit grey, but Sunny is still keen for a walk."
    private static let stillTimeForAStroll = "No sun, no problem. Still time for a stroll."
    private static let oneLastStroll = "Quiet night. Time for one last stroll before bed?"
    private static let oneMoreLap = "Sunny thinks there's time for one more lap of the block."
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
                return ["Hurricane force winds! Everyone inside, away from the windows."]
            }
            if force >= WalkConditions.stormForce {
                return ["Storm force winds. Everyone stays in today.", "Misty is under the bed until this wind drops."]
            }
            return hasDog
                ? ["Gale force winds! Quick potty breaks, then back in.", "Blowy out there. Misty won't go near the door."]
                : ["Gale force winds! Misty won't go near the door.", "Blowy out there. Misty is staying put."]
        case let .air(_, pollutant):
            let air = WalkReason.airName(pollutant) ?? "Poor air"
            return hasDog
                ? ["\(air) today. Quick potty breaks, then back on the sofa.", "The air's not great. Sunny's big walk can wait."]
                : ["\(air) today. Misty's keeping the windows shut.", "The air's not great. Misty is happy indoors."]
        case .pavement:
            return ["Hot pavement! Sunny's sticking to the grass today.", "Too hot underfoot. Short trips on the grass."]
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
