import Foundation

/// A single radar frame: a snapshot timestamp and the tile path that serves it.
struct RadarFrame: Equatable, Sendable {
    let timeEpochSeconds: Int
    let path: String
    /// True for nowcast (future) frames, false for observed past frames.
    let isForecast: Bool
}

/// An ordered radar animation timeline from RainViewer: observed past frames followed by
/// short-range nowcast frames, all sharing a single tile `host`.
struct RadarTimeline: Equatable, Sendable {
    /// Highest slippy-map zoom RainViewer serves radar tiles at; higher zooms return a
    /// "Zoom Level Not Supported" placeholder image. Callers request tiles at this zoom.
    nonisolated static let maxZoom = 7

    private nonisolated static let tileSize = 256
    // Color scheme 4 (Universal Blue), smooth=1 (interpolated), snow=1 (render snow distinctly).
    private nonisolated static let colorScheme = 4

    let host: String
    let frames: [RadarFrame]

    nonisolated func tileURL(for frame: RadarFrame, z: Int, x: Int, y: Int) -> String {
        "\(host)\(frame.path)/\(Self.tileSize)/\(z)/\(x)/\(y)/\(Self.colorScheme)/1_1.png"
    }

    /// RainViewer's coverage layer for a tile: transparent where it has radar, opaque black where it
    /// doesn't (much of Africa, central Asia and the oceans), whose radar tiles are just empty.
    nonisolated func coverageURL(z: Int, x: Int, y: Int) -> String {
        "\(host)/v2/coverage/0/\(Self.tileSize)/\(z)/\(x)/\(y)/0/0_0.png"
    }
}
