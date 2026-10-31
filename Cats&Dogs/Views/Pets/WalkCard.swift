import SwiftUI

/// "Best walk time" card: when to take the dog out. The sentence carries the advice; the paw icon is
/// tinted by the rating as a glance cue (deliberately not a chip, which read as a button), and a
/// short caption says why when it's too hot or too cold, naming the pavement only when that's the reason.
struct WalkCard: View {
    let advice: WalkAdvice
    @Environment(\.seasonalTheme) private var seasonalTheme
    @Environment(\.colorScheme) private var colorScheme

    private var detail: String {
        if advice.rating == .great { return "Now is a great time" }
        if let best = advice.bestTimeLabel {
            return advice.bestTimeIsTomorrow ? "Tomorrow around \(best)" : "Around \(best)"
        }
        return "Not a good day for walkies"
    }

    private var caption: String? {
        if let pavement = advice.pavementNow.map({ Int($0.rounded()) }) {
            switch (advice.rating, advice.pavementBand) {
            case (.pawsHot, .dangerous): return "Paw check: about \(pavement)°. Dangerously hot."
            case (.pawsHot, .tooHot): return "Paw check: about \(pavement)°. Too hot for paws."
            case (.okay, .warm): return "Paw check: about \(pavement)°. Getting hot."
            default: break
            }
        }
        // Hot or cold air, not the pavement.
        return switch advice.rating {
        case .pawsHot: "Too hot for paws."
        case .tooCold: "Too cold for paws."
        case .badAir: "Bad air. Potty breaks only."
        default: nil
        }
    }

    /// The dark shade on the light theme's card and the pale one on the dark theme's, so the paw and
    /// the caption stay clear (at least 4.5:1) on either.
    private var tint: Color {
        let (light, dark): (UInt32, UInt32) = switch advice.rating {
        case .great: (0x27500A, 0xC0DD97)
        case .okay: (0x633806, 0xFAC775)
        case .poor: (0x444441, 0xD3D1C7)
        case .pawsHot, .badAir: (0x791F1F, 0xF7C1C1)
        case .tooCold: (0x0C447C, 0xB5D4F4)
        }
        return Color(hex: colorScheme == .dark ? dark : light)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Best walk time")
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
        WalkCard(advice: WalkAdvice(rating: .okay, bestTimeLabel: "6 PM"))
        WalkCard(advice: WalkAdvice(rating: .pawsHot, bestTimeLabel: "7 PM", pavementNow: 55, pavementBand: .tooHot))
        WalkCard(advice: WalkAdvice(rating: .poor, bestTimeLabel: nil))
        WalkCard(advice: WalkAdvice(rating: .tooCold, bestTimeLabel: "11 AM"))
    }
    .padding()
}
