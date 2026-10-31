import SwiftUI
import UIKit

extension Color {
    /// A colour from a 0xRRGGBB literal, as the Android theme defines its palette.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// The filled accent button, in place of `.borderedProminent`, whose label is always white: only
    /// 2.0:1 on the dark theme's light blue. The label here uses OnAccent (Android's `onPrimary`).
    func accentButtonStyle() -> some View {
        buttonStyle(AccentButtonStyle())
    }
}

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.onAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, controlSize == .large ? 14 : 8)
            .background(Color.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// Shared brand styling, matching the Android app's theme (`ui/theme/Color.kt`, `Type.kt`).
/// Colours live in the asset catalog, each with Android's dark-scheme value:
/// - AccentColor: the brand blue (Android `primary`)
/// - BrandSurface: screen backgrounds (`background` / `surface`)
/// - SurfaceVariant: content cards such as Today, Hourly and Radar (`surfaceVariant`)
/// - PrimaryContainer: icon circles on the welcome and onboarding screens (`primaryContainer`)
/// - OnAccent: text on accent-filled buttons (`onPrimary`)
extension Font {
    /// Baloo 2, the rounded face that echoes the "Sunny & Misty" wordmark. Used for display and title
    /// text only; body copy stays on the system font. Scales with Dynamic Type via `style`; `size`
    /// overrides the style's default size.
    static func brand(_ style: Font.TextStyle, size: CGFloat? = nil, weight: BrandWeight = .semibold) -> Font {
        .custom(weight.postScriptName, size: size ?? BrandWeight.pointSize(for: style), relativeTo: style)
    }

    enum BrandWeight {
        case medium
        case semibold
        case bold

        var postScriptName: String {
            switch self {
            case .medium: "Baloo2-Medium"
            case .semibold: "Baloo2-SemiBold"
            case .bold: "Baloo2-Bold"
            }
        }

        /// Default (Large) Dynamic Type sizes, so Baloo 2 lines up with the system styles it replaces.
        static func pointSize(for style: Font.TextStyle) -> CGFloat {
            switch style {
            case .largeTitle: 34
            case .title: 28
            case .title2: 22
            case .title3: 20
            case .headline, .body: 17
            case .callout: 16
            case .subheadline: 15
            case .footnote: 13
            case .caption: 12
            case .caption2: 11
            default: 17
            }
        }
    }
}

enum BrandAppearance {
    /// Navigation bar titles use Baloo 2, like the Android top app bar.
    @MainActor
    static func apply() {
        let appearance = UINavigationBar.appearance()
        if let large = UIFont(name: Font.BrandWeight.bold.postScriptName, size: 34) {
            appearance.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        }
        if let inline = UIFont(name: Font.BrandWeight.semibold.postScriptName, size: 19) {
            appearance.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
        }
    }
}
