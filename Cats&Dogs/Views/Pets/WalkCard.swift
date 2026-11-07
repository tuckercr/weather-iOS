import SwiftUI

/// "Best walk time" card: when to take the dog out. The sentence carries the advice; the paw icon is
/// tinted by the rating as a glance cue (deliberately not a chip, which read as a button), and a
/// short caption gives `WalkCheck`'s reason when it's more than a wait: the pavement, heat or cold,
/// the air (by its pollutant), a gale or storms. Hurricane force wind turns it into a warning, which
/// shows even without a dog.
struct WalkCard: View {
    let advice: WalkAdvice
    @Environment(\.seasonalTheme) private var seasonalTheme
    @Environment(\.colorScheme) private var colorScheme
    /// Baloo 2 leaves about 6 points under its baseline, against 3 above the small title's
    /// capitals, so when the headline is the last line the text sits high beside the paw. Lowered
    /// by half the difference.
    @ScaledMetric(relativeTo: .headline) private var headlineLastOffset: CGFloat = 2

    private var isDanger: Bool { advice.rating == .danger }

    private var detail: String {
        if isDanger { return "Hurricane force winds" }
        if advice.rating == .great { return "Now is a great time" }
        if let best = advice.bestTimeLabel {
            return advice.bestTimeIsTomorrow ? "Tomorrow around \(best)" : "Around \(best)"
        }
        return "Not a good day for walkies"
    }

    private var caption: String? { Self.caption(advice) }

    /// With a dog, when Remote Config allows the card; a danger warning shows for everyone.
    static func isShown(_ advice: WalkAdvice, hasDog: Bool, cardEnabled: Bool) -> Bool {
        advice.rating == .danger || (hasDog && cardEnabled)
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

    /// The dark shade on the light theme's card and the pale one on the dark theme's, so the paw and
    /// the caption stay clear (at least 4.5:1) on either.
    private var tint: Color {
        let (light, dark): (UInt32, UInt32) = switch advice.rating {
        case .great: (0x27500A, 0xC0DD97)
        case .okay: (0x633806, 0xFAC775)
        case .poor: (0x444441, 0xD3D1C7)
        case .pawsHot, .badAir, .windy, .stormy, .danger: (0x791F1F, 0xF7C1C1)
        case .tooCold: (0x0C447C, 0xB5D4F4)
        }
        return Color(hex: colorScheme == .dark ? dark : light)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDanger ? "exclamationmark.triangle.fill" : "pawprint.fill")
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(isDanger ? "Danger" : "Best Walk Time")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                Text(detail)
                    .font(.brand(.headline))
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
            }
            .offset(y: caption == nil ? headlineLastOffset : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card(seasonalTheme), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 12) {
        WalkCard(advice: WalkAdvice(rating: .great, bestTimeLabel: nil))
        WalkCard(advice: WalkAdvice(rating: .great, bestTimeLabel: nil, outlook: .until(time: "6 PM", change: .storms)))
        WalkCard(advice: WalkAdvice(rating: .okay, bestTimeLabel: "6 PM"))
        WalkCard(advice: WalkAdvice(
            rating: .pawsHot,
            bestTimeLabel: "7 PM",
            pavementNow: 55,
            now: WalkCheck([WalkFactor(reason: .pavement(.tooHot), level: .pottyOnly)])
        ))
        WalkCard(advice: WalkAdvice(
            rating: .badAir,
            bestTimeLabel: "6 PM",
            now: WalkCheck([WalkFactor(reason: .air(band: 3, pollutant: .fineParticles), level: .pottyOnly)])
        ))
        WalkCard(advice: WalkAdvice(
            rating: .danger,
            bestTimeLabel: nil,
            now: WalkCheck([WalkFactor(reason: .wind(force: 12), level: .danger)])
        ))
        WalkCard(advice: WalkAdvice(rating: .poor, bestTimeLabel: nil))
        WalkCard(advice: WalkAdvice(rating: .tooCold, bestTimeLabel: "11 AM"))
    }
    .padding()
}
