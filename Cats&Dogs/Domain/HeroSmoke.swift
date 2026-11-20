import Foundation

/// Smoke drawn over the hero, like fog: the pets keep the mood's look under it. Haze when smoke
/// (fine particles) makes the air bad enough for potty breaks only, falling ash at the worst band,
/// where the walk card says to stay in. OpenWeather's own "Smoke" and "Ash" conditions count too,
/// for cities without air quality. Same as Android's `HeroSmoke`.
enum HeroSmoke: Equatable {
    case haze
    case ash

    /// `walk` is the verdict on the hour under way; nil without a forecast.
    static func from(walk: WalkCheck?, conditionMain: String) -> HeroSmoke? {
        let smoke = walk?.factors.first { factor in
            if case .air(_, .fineParticles) = factor.reason { return true }
            return false
        }
        let condition = conditionMain.lowercased()
        if let smoke, smoke.level >= .stayIn { return .ash }
        if condition == "ash" { return .ash }
        if let smoke, smoke.level >= .pottyOnly { return .haze }
        if condition == "smoke" { return .haze }
        return nil
    }
}
