import Foundation

/// What the pets wear and hold in the hero scene: the weather's props for `mood`, and a seasonal
/// theme's costumes on top. A costume only takes the place of what it covers: Misty's witch hat
/// replaces anything the weather puts on her head, Sunny's bandana anything round his neck, and the
/// other pet keeps theirs. After dark (by the clock) the costumes come off, whatever the weather.
/// Same rules as Android's `PetOutfit`.
enum PetAccessory: CaseIterable {
    /// Over both pets in the rain.
    case umbrella
    /// Sunny's, on a warm clear day.
    case sunglasses
    /// Round Sunny's neck in the snow or cold.
    case dogScarf
    /// Round Misty's neck in the snow or cold.
    case catScarf
    case witchHat
    case bandana

    fileprivate enum Place { case overhead, dogHead, dogNeck, catHead, catNeck }

    fileprivate var place: Place {
        switch self {
        case .umbrella: .overhead
        case .sunglasses: .dogHead
        case .dogScarf: .dogNeck
        case .catScarf: .catNeck
        case .witchHat: .catHead
        case .bandana: .dogNeck
        }
    }
}

enum PetOutfit {
    static func accessories(mood: PetMood, decorations: Set<SceneDecoration>, dark: Bool) -> Set<PetAccessory> {
        let weather: Set<PetAccessory> = switch mood {
        case .rain: [.umbrella]
        case .sunny: [.sunglasses]
        case .snow, .cold: [.dogScarf, .catScarf]
        default: []
        }
        var costumes: Set<PetAccessory> = []
        if !dark {
            if decorations.contains(.witchHat) { costumes.insert(.witchHat) }
            if decorations.contains(.bandana) { costumes.insert(.bandana) }
        }
        let covered = Set(costumes.map(\.place))
        return costumes.union(weather.filter { !covered.contains($0.place) })
    }
}
