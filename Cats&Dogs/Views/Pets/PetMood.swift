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
            "Perfect walkies weather! Off we go.",
            "Misty has claimed the sunniest windowsill.",
            "Sunshine and tail wags all round.",
        ]
        case .sunny: [
            "Sunglasses on. It's a warm one today.",
            "Warm out. Shady walks and plenty of water.",
            "Misty has claimed the sunniest windowsill.",
        ]
        case .cloudy: [
            "A bit grey, but Sunny is still keen for a walk.",
            "Nap weather, says Misty.",
            "No sun, no problem. Still time for a stroll.",
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
                "Quiet night. Time for one last stroll before bed?",
                "Sunny thinks there's time for one more lap of the block.",
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

    /// Today's caption, chosen by the city's own date and (at night) hour, not the device's.
    func caption(on date: Date = Date(), timeZone: TimeZone = .current, hasDog: Bool = true) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let options = captions(nightPart: NightPart(hour: calendar.component(.hour, from: date)), hasDog: hasDog)
        return options[dayOfYear % options.count]
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
