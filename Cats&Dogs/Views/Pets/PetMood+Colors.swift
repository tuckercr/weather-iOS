import SwiftUI

/// The moods' colours, kept with the views: the moods themselves are domain rules.
extension PetMood {
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

    /// The hero card's colour: grey in fog by day, since the mood's own sky colour (a cold blue, a
    /// cloudy blue) says clear air. A foggy night keeps the night sky. Same as Android's
    /// `heroSkyColor`.
    func heroSkyColor(foggy: Bool) -> Color {
        foggy && self != .night ? Color(hex: 0xDDE3E7) : skyColor
    }

    var ink: Color {
        self == .night ? Color(hex: 0xF1EFE8) : Color(hex: 0x0C447C)
    }
}
