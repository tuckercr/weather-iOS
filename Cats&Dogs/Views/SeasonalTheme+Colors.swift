import SwiftUI

/// The themes' colours, kept with the views: the themes themselves are domain data.
extension SeasonalTheme {
    func heroBackground(night: Bool) -> Color { (night ? colors.heroNight : colors.heroDay).color }

    func heroInk(night: Bool) -> Color { (night ? colors.inkNight : colors.inkDay).color }

    var cardBackground: Color { HexColor.adaptive(light: colors.cardLight, dark: colors.cardDark) }

    /// Nil leaves the tiles in the brand colour.
    var tileHeader: Color? {
        guard let light = colors.tileHeaderLight, let dark = colors.tileHeaderDark else { return nil }
        return HexColor.adaptive(light: light, dark: dark)
    }
}

extension HexColor {
    var color: Color { Color(hex: rgb) }

    static func adaptive(light: HexColor, dark: HexColor) -> Color {
        let lightColor = UIColor(light.color)
        let darkColor = UIColor(dark.color)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor })
    }
}

extension Color {
    /// A card's background, warmed by today's theme when there is one.
    static func card(_ theme: SeasonalTheme?) -> Color { theme?.cardBackground ?? .surfaceVariant }
}
