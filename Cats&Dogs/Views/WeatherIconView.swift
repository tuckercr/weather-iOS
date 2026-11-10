import SwiftUI

/// A weather condition icon, bundled with the app and drawn in the pet scene's style. Every shape
/// has the pets' navy outline, so the white clouds hold up on the light cards, and the fills carry
/// them on the dark ones. Night icons show the moon's phase at `date` (when nil, the screen's clock,
/// or the device's outside the weather screen), lit from the left in the southern hemisphere.
struct WeatherIconView: View {
    let iconCode: String
    let size: CGFloat
    /// What VoiceOver reads, e.g. "Light rain". Nil where text beside the icon already says it.
    var description: String? = nil
    var date: Date? = nil
    @Environment(\.southernHemisphere) private var southernHemisphere
    @Environment(\.screenNow) private var screenNow

    var body: some View {
        if let description {
            image.accessibilityLabel(description)
        } else {
            // Unlabelled, VoiceOver would read the asset name ("wx 01d").
            image.accessibilityHidden(true)
        }
    }

    private var image: some View {
        Image(Self.assetName(for: iconCode, phase: MoonPhase(at: date ?? screenNow ?? Date()), southernHemisphere: southernHemisphere))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    /// Maps an OpenWeatherMap icon code ("01d", "10n"…; Open-Meteo's WMO codes are mapped onto the
    /// same set) to its asset. Only clear, few clouds and rain look different at night, where they
    /// show the moon at `phase`.
    static func assetName(for iconCode: String, phase: MoonPhase = .full, southernHemisphere: Bool = false) -> String {
        let night = iconCode.hasSuffix("n")
        func moon(_ code: String) -> String {
            "wx_\(code)_\(phase.assetSuffix)" + (southernHemisphere && phase.differsInSouth ? "_s" : "")
        }
        switch iconCode.prefix(2) {
        case "01": return night ? moon("01n") : "wx_01d"
        case "02": return night ? moon("02n") : "wx_02d"
        case "03": return "wx_03d"
        case "04": return "wx_04d"
        case "09": return "wx_09d"
        case "10": return night ? moon("10n") : "wx_10d"
        case "11": return "wx_11d"
        case "13": return "wx_13d"
        case "50": return "wx_50d"
        default: return "wx_03d"
        }
    }
}
