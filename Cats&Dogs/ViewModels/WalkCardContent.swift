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
        title = isDanger ? "Danger" : "Best Walk Time"
        headline = Self.headline(advice)
        caption = Self.caption(advice)
    }

    /// The sentence that carries the advice.
    static func headline(_ advice: WalkAdvice) -> String {
        if advice.rating == .danger { return "Hurricane force winds" }
        if advice.rating == .great { return "Now is a great time" }
        if let best = advice.bestTimeLabel {
            return advice.bestTimeIsTomorrow ? "Tomorrow around \(best)" : "Around \(best)"
        }
        return "Not a good day for walkies"
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
            case .dangerous: "Paw check: about \(pavement)° now. Dangerously hot."
            case .tooHot: "Paw check: about \(pavement)° now. Too hot for paws."
            case .warm: "Paw check: about \(pavement)° now. Getting hot."
            case .safe, .pavementOK, .freezing, .icy: nil
            }
        case .heat where level >= .pottyOnly: return "Too hot for paws."
        case .cold where level >= .pottyOnly: return "Too cold for paws."
        case let .air(_, pollutant) where level >= .pottyOnly:
            let air = WalkReason.airName(pollutant) ?? "Bad air"
            return level >= .stayIn ? "\(air). Stay in. Potty breaks only." : "\(air). Potty breaks only."
        case let .wind(force) where level >= .pottyOnly:
            if force >= WalkConditions.hurricaneForce { return "Stay inside, away from the windows." }
            if force >= WalkConditions.stormForce { return "Storm force winds. Keep pets inside." }
            return "Gale force winds. Potty breaks only."
        case .storms where level >= .stayIn: return "Thunderstorms. Keep pets inside."
        default: return nil
        }
    }

    /// After a walk now: when the good spell ends and why, sunset coming up, or so-so air.
    nonisolated static func outlookLine(_ outlook: WalkOutlook) -> String {
        switch outlook {
        case let .until(time, change): "Good until \(time), then \(changePhrase(change))."
        case .darkIn(0): "Getting dark soon."
        case .darkIn(1): "Gets dark in about an hour."
        case let .darkIn(hours): "Gets dark in about \(hours) hours."
        case .moderateAir: "Air's not great. Short walks for older and flat-faced dogs."
        }
    }

    private nonisolated static func changePhrase(_ change: WalkChange) -> String {
        switch change {
        case .storms: "storms"
        case .maybeStorms: "maybe storms"
        case .rain: "rain"
        case .maybeRain: "maybe rain"
        case .snow: "snow"
        case .maybeSnow: "maybe snow"
        case .wind: "very windy"
        case .heat: "too hot"
        case .hotPavement: "hot pavement"
        case .cold: "too cold"
        case .badAir: "bad air"
        }
    }
}
