import Foundation

/// What the walk card says: the title, the sentence that carries the advice (a walk now, or the
/// best time's spell of good hours, "11 AM to 1 PM"), and a short caption: the next spell as a
/// second option ("Or 5 to 8 PM."), then `WalkCheck`'s reason when it's more than a wait (the
/// pavement, heat or cold, the air by its pollutant, a gale or storms) or else what clears by the
/// best time ("The rain's gone by then."), or the outlook after a walk now, and a warning about
/// hurricane force wind or storms on their way. Built with the screen state;
/// `WalkCard` draws it. Same wording as Android's `walkDetail` and `walkCaption`.
struct WalkCardContent: Equatable {
    /// Picks the paw's tint.
    let rating: WalkRating
    /// Hurricane force wind now or on its way: a warning, shown even without a dog.
    let isDanger: Bool
    let title: String
    let headline: String
    let caption: String?

    init(advice: WalkAdvice) {
        rating = advice.rating
        isDanger = advice.isDanger
        title = if isDanger {
            String(localized: "Danger", comment: "Walk card title")
        } else if Self.second(advice) != nil {
            String(localized: "Best Walk Times", comment: "Walk card title when it gives a second time")
        } else {
            String(localized: "Best Walk Time", comment: "Walk card title")
        }
        headline = Self.headline(advice)
        caption = Self.caption(advice)
    }

    /// The sentence that carries the advice.
    static func headline(_ advice: WalkAdvice) -> String {
        if advice.rating == .danger { return String(localized: "Hurricane force winds", comment: "Walk card headline. The argument is a time of day.") }
        if case let .hurricane(time) = advice.warning {
            return String(localized: "Hurricane force winds from \(time)", comment: "Walk card headline: hurricane force wind on its way. The argument is a time of day.")
        }
        if advice.rating == .great { return String(localized: "Now is a great time", comment: "Walk card headline. The argument is a time of day.") }
        if let best = advice.bestTimeLabel, let end = advice.bestTimeEndLabel {
            let range = hourRange(best, end)
            return advice.bestTimeIsTomorrow ? String(localized: "Tomorrow \(range)", comment: "Walk card headline: a spell of good walking hours tomorrow, such as \"7 to 10 AM\".") : range
        }
        if let best = advice.bestTimeLabel {
            return advice.bestTimeIsTomorrow ? String(localized: "Tomorrow around \(best)", comment: "Walk card headline. The argument is a time of day.") : String(localized: "Around \(best)", comment: "Walk card headline. The argument is a time of day.")
        }
        return String(localized: "Not a good day for walkies", comment: "Walk card headline. The argument is a time of day.")
    }

    /// The outlook after a walk now; otherwise the reason now isn't the time, when it's worth more
    /// than a wait (or it's the pavement, which says how hot it is now). Hurricane force wind on its
    /// way says to get inside instead, and storms on their way are added after, unless the outlook
    /// already says storms are coming.
    static func caption(_ advice: WalkAdvice) -> String? {
        if advice.rating != .danger, case .hurricane = advice.warning {
            return String(localized: "Get everyone inside before then.", comment: "Walk card caption under a warning of hurricane force wind later today")
        }
        // After a walk now the outlook comes first ("Good until 4 PM, then rain. Good again 6 to 8
        // PM."); after a later best time, the second option ("Or 5 to 8 PM. The rain's gone by then.").
        let parts = advice.rating == .great
            ? [nowCaption(advice), second(advice)].compactMap(\.self)
            : [second(advice), nowCaption(advice) ?? clearsLine(advice)].compactMap(\.self)
        let caption = parts.isEmpty ? nil : parts.joined(separator: " ")
        guard case let .storms(time) = advice.warning else { return caption }
        if case .until(_, .storms) = advice.outlook { return caption }
        if case .until(_, .maybeStorms) = advice.outlook { return caption }
        let storms = stormsFrom(time)
        return caption.map { "\($0) \(storms)" } ?? storms
    }

    /// "11 AM to 1 PM", or "5 to 8 PM" when both are in the same half of the day.
    nonisolated static func hourRange(_ start: String, _ end: String) -> String {
        let startParts = start.split(separator: " ", maxSplits: 1)
        let endParts = end.split(separator: " ", maxSplits: 1)
        let from = startParts.count == 2 && endParts.count == 2 && startParts[1] == endParts[1] ? String(startParts[0]) : start
        return String(localized: "\(from) to \(end)", comment: "Walk card: a spell of good walking hours, such as \"11 AM to 1 PM\" or \"5 to 8 PM\".")
    }

    /// The next spell of good walking hours, as a second option: "Or 5 to 8 PM." after a later best
    /// time, "Good again 5 to 8 PM." after a walk now whose spell ends within a few hours. Nil
    /// otherwise, and under a warning.
    static func second(_ advice: WalkAdvice) -> String? {
        guard !advice.isDanger, let window = advice.nextWindow else { return nil }
        let when = window.endLabel.map { hourRange(window.startLabel, $0) }
            ?? String(localized: "around \(window.startLabel)", comment: "Walk card: a second time for a walk when only its start is known. The argument is a time of day.")
        if advice.rating == .great {
            guard case .until = advice.outlook else { return nil }
            return window.isTomorrow
                ? String(localized: "Good again tomorrow \(when).", comment: "Walk card caption after a walk now: the next spell of good walking hours, such as \"7 to 10 AM\".")
                : String(localized: "Good again \(when).", comment: "Walk card caption after a walk now: the next spell of good walking hours, such as \"5 to 8 PM\".")
        }
        guard advice.bestTimeLabel != nil else { return nil }
        return window.isTomorrow && !advice.bestTimeIsTomorrow
            ? String(localized: "Or tomorrow \(when).", comment: "Walk card caption: a second spell of good walking hours, such as \"7 to 10 AM\".")
            : String(localized: "Or \(when).", comment: "Walk card caption: a second spell of good walking hours, such as \"5 to 8 PM\".")
    }

    /// Why the best time is better than now, when now is only a wait for a reason that clears: "The
    /// rain's gone by then." Nil after dark or outside the walking hours, and for a walk now.
    static func clearsLine(_ advice: WalkAdvice) -> String? {
        guard advice.rating != .great, advice.bestTimeLabel != nil, let reason = advice.now.reason else { return nil }
        return switch reason {
        case .rain: String(localized: "The rain's gone by then.", comment: "Walk card caption: why the best time is better than now")
        case .snow: String(localized: "The snow's gone by then.", comment: "Walk card caption: why the best time is better than now")
        case .storms: String(localized: "The storms have passed by then.", comment: "Walk card caption: why the best time is better than now")
        case .heat: String(localized: "Cooler by then.", comment: "Walk card caption: why the best time is better than now")
        case .cold: String(localized: "Warmer by then.", comment: "Walk card caption: why the best time is better than now")
        case .wind: String(localized: "Calmer by then.", comment: "Walk card caption: why the best time is better than now")
        case .pavement: String(localized: "Cooler paws by then.", comment: "Walk card caption: why the best time is better than now")
        case .air: String(localized: "Cleaner air by then.", comment: "Walk card caption: why the best time is better than now")
        case .dark: nil
        }
    }

    /// "Storms from 4 PM.", for the walk card and the morning briefing.
    nonisolated static func stormsFrom(_ time: String) -> String {
        String(localized: "Storms from \(time).", comment: "Walk card caption and morning briefing: likely thunderstorms later. The argument is a time of day.")
    }

    /// The caption about now: the outlook after a walk now, or why now isn't the time.
    private static func nowCaption(_ advice: WalkAdvice) -> String? {
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
        // The air's feels-like, not the ground: the Paw Check tile can say "Fine underfoot" at the same time.
        case .cold where level >= .pottyOnly: return String(localized: "Too cold for a long walk.", comment: "Walk card caption: why now isn't the time for a walk")
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
