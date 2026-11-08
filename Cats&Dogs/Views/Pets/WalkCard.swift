import SwiftUI

/// "Best walk time" card: when to take the dog out, as `WalkCardContent` words it. The paw icon is
/// tinted by the rating as a glance cue (deliberately not a chip, which read as a button).
struct WalkCard: View {
    let content: WalkCardContent
    @Environment(\.seasonalTheme) private var seasonalTheme
    @Environment(\.colorScheme) private var colorScheme
    /// Baloo 2 leaves about 6 points under its baseline, against 3 above the small title's
    /// capitals, so when the headline is the last line the text sits high beside the paw. Lowered
    /// by half the difference.
    @ScaledMetric(relativeTo: .headline) private var headlineLastOffset: CGFloat = 2

    /// The dark shade on the light theme's card and the pale one on the dark theme's, so the paw and
    /// the caption stay clear (at least 4.5:1) on either.
    private var tint: Color {
        let (light, dark): (UInt32, UInt32) = switch content.rating {
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
            Image(systemName: content.isDanger ? "exclamationmark.triangle.fill" : "pawprint.fill")
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                Text(content.headline)
                    .font(.brand(.headline))
                if let caption = content.caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
            }
            .offset(y: content.caption == nil ? headlineLastOffset : 0)
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
        WalkCard(content: WalkCardContent(advice: WalkAdvice(rating: .great, bestTimeLabel: nil)))
        WalkCard(content: WalkCardContent(advice: WalkAdvice(rating: .great, bestTimeLabel: nil, outlook: .until(time: "6 PM", change: .storms))))
        WalkCard(content: WalkCardContent(advice: WalkAdvice(rating: .okay, bestTimeLabel: "6 PM")))
        WalkCard(content: WalkCardContent(advice: WalkAdvice(
            rating: .pawsHot,
            bestTimeLabel: "7 PM",
            pavementNow: 55,
            now: WalkCheck([WalkFactor(reason: .pavement(.tooHot), level: .pottyOnly)])
        )))
        WalkCard(content: WalkCardContent(advice: WalkAdvice(
            rating: .badAir,
            bestTimeLabel: "6 PM",
            now: WalkCheck([WalkFactor(reason: .air(band: 3, pollutant: .fineParticles), level: .pottyOnly)])
        )))
        WalkCard(content: WalkCardContent(advice: WalkAdvice(
            rating: .danger,
            bestTimeLabel: nil,
            now: WalkCheck([WalkFactor(reason: .wind(force: 12), level: .danger)])
        )))
        WalkCard(content: WalkCardContent(advice: WalkAdvice(rating: .poor, bestTimeLabel: nil)))
        WalkCard(content: WalkCardContent(advice: WalkAdvice(rating: .tooCold, bestTimeLabel: "11 AM")))
    }
    .padding()
}
