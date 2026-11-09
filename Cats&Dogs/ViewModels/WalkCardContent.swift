import Foundation

/// What the walk card says: the title, the sentence that carries the advice, and a short caption
/// with `WalkCheck`'s reason when it's more than a wait (the pavement, heat or cold, the air by its
/// pollutant, a gale or storms), or the outlook after a walk now. Built with the screen state;
/// `WalkCard` draws it. Same wording as Android's `walkDetail` and `walkCaption`.
struct WalkCardContent: Equatable {
    /// Picks the paw's tint.
    let rating: WalkRating
    /// Hurricane force wind: a warning, shown even without a dog.
    let isDanger: Bool
    let title: String
    let headline: String
    let caption: String?

    init(advice: WalkAdvice) {
        rating = advice.rating
        isDanger = advice.rating == .danger
        title = isDanger ? String(localized: "Danger", comment: "Walk card title") : String(localized: "Best Walk Time", comment: "Walk card title")
        headline = Self.headline(advice)
        caption = Self.caption(advice)
    }

    /// The sentence that carries the advice.
    static func headline(_ advice: WalkAdvice) -> String {
        if advice.rating == .danger { return String(localized: "Hurricane force winds", comment: "Walk card headline. The argument is a time of day.") }
        if advice.rating == .great { return String(localized: "Now is a great time", comment: "Walk card headline. The argument is a time of day.") }
        if let best = advice.bestTimeLabel {
            return advice.bestTimeIsTomorrow ? String(localized: "Tomorrow around \(best)", comment: "Walk card headline. The argument is a time of day.") : String(localized: "Around \(best)", comment: "Walk card headline. The argument is a time of day.")
        }
        return String(localized: "Not a good day for walkies", comment: "Walk card headline. The argument is a time of day.")
    }

    /// The outlook after a walk now; otherwise the reason now isn't the time, when it's worth more
    /// than a wait (or it's the pavement, which says how hot it is now).
    static func caption(_ advice: WalkAdvice) -> String? {
        if advice.rating == .great { return advice.outlook.map(outlookLine) }
        guard let reason = advice.now.reason else { return nil }
        let level = advice.now.level
        switch reason {
        case let .pavement(band):
            guard let pavement = advice.pavementNow.map({ Int($0.rounded()) }) else { return nil }
            return switch band {
            case .dangerous: String(localized: "Paw check: about \(pavement)° now. Dangerously hot.", comment: "Walk card caption. The argument is the pavement temperature.")
            case .tooHot: String(localized: "Paw check: about \(pavement)° now. Too hot for paws.", comment: "Walk card caption. The argument is the pavement temperature.")
            case .warm: String(localized: "Paw check: about \(pavement)° now. Getting hot.", comment: "Walk card caption. The argument is the pavement temperature.")
            case .safe, .pavementOK, .freezing, .icy: nil
            }
        case .heat where level >= .pottyOnly: return String(localized: "Too hot for paws.", comment: "Walk card caption: why now isn't the time for a walk")
        case .cold where level >= .pottyOnly: return String(localized: "Too cold for paws.", comment: "Walk card caption: why now isn't the time for a walk")
        case let .air(_, pollutant) where level >= .pottyOnly:
            let air = WalkReason.airName(pollutant) ?? String(localized: "Bad air", comment: "Walk card caption: why now isn't the time for a walk")
            return level >= .stayIn ? String(localized: "\(air). Stay in. Potty breaks only.", comment: "Walk card caption: why now isn't the time for a walk") : String(localized: "\(air). Potty breaks only.", comment: "Walk card caption: why now isn't the time for a walk")
        case let .wind(force) where level >= .pottyOnly:
            if force >= WalkConditions.hurricaneForce { return String(localized: "Stay inside, away from the windows.", comment: "Walk card caption: why now isn't the time for a walk") }
            if force >= WalkConditions.stormForce { return String(localized: "Storm force winds. Keep pets inside.", comment: "Walk card caption: why now isn't the time for a walk") }
            return String(localized: "Gale force winds. Potty breaks only.", comment: "Walk card caption: why now isn't the time for a walk")
        case .storms where level >= .stayIn: return String(localized: "Thunderstorms. Keep pets inside.", comment: "Walk card caption: why now isn't the time for a walk")
        default: return nil
        }
    }

    /// After a walk now: when the good spell ends and why, sunset coming up, or so-so air.
    nonisolated static func outlookLine(_ outlook: WalkOutlook) -> String {
        switch outlook {
        case let .until(time, change): goodUntil(time, then: change)
        case .darkIn(0): String(localized: "Getting dark soon.", comment: "Walk card caption after a walk now")
        case .darkIn(1): String(localized: "Gets dark in about an hour.", comment: "Walk card caption after a walk now")
        case let .darkIn(hours): String(localized: "Gets dark in about \(hours) hours.", comment: "Walk card caption after a walk now")
        case .moderateAir: String(localized: "Air's not great. Short walks for older and flat-faced dogs.", comment: "Walk card caption after a walk now")
        }
    }

    /// "Good until 6 PM, then storms.", a whole sentence for each change.
    private nonisolated static func goodUntil(_ time: String, then change: WalkChange) -> String {
        switch change {
        case .storms: String(localized: "Good until \(time), then storms.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        case .maybeStorms: String(localized: "Good until \(time), then maybe storms.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        case .rain: String(localized: "Good until \(time), then rain.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        case .maybeRain: String(localized: "Good until \(time), then maybe rain.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        case .snow: String(localized: "Good until \(time), then snow.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        case .maybeSnow: String(localized: "Good until \(time), then maybe snow.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        case .wind: String(localized: "Good until \(time), then very windy.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        case .heat: String(localized: "Good until \(time), then too hot.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        case .hotPavement: String(localized: "Good until \(time), then hot pavement.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        case .cold: String(localized: "Good until \(time), then too cold.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        case .badAir: String(localized: "Good until \(time), then bad air.", comment: "Walk card caption after a walk now: when the good spell ends and why. The argument is a time.")
        }
    }
}
