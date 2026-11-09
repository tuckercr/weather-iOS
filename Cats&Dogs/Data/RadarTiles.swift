import CoreGraphics
import Foundation
import ImageIO

/// How the radar card's tiles are laid out and loaded.
enum RadarTiles {
    // RainViewer only serves radar tiles up to zoom 7; regional zoom suits precipitation radar.
    nonisolated static let zoom = RadarTimeline.maxZoom
    nonisolated static let pixelSize = 256
    /// Radar frames stitched at once; each one fetches 9 tiles.
    static let concurrentFrames = 4
    /// Waits before retrying the tiles that failed, so a network blip doesn't leave gaps for good.
    nonisolated static let retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
}

/// The map tile a location falls in at `zoom`, and where in it: the radar card centres on that
/// point within a 3 by 3 block of tiles.
struct RadarTile: Hashable, Sendable {
    let tileX: Int
    let tileY: Int
    let subFractionX: Double
    let subFractionY: Double

    static func from(latitude: Double, longitude: Double, zoom: Int) -> RadarTile {
        let n = pow(2.0, Double(zoom))
        let exactX = (longitude + 180.0) / 360.0 * n
        let latRad = latitude * .pi / 180.0
        let exactY = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n
        let tileX = Int(exactX)
        let tileY = Int(exactY)
        return RadarTile(
            tileX: tileX,
            tileY: tileY,
            subFractionX: exactX - Double(tileX),
            subFractionY: exactY - Double(tileY)
        )
    }
}

/// Loads the radar card's images: the OpenStreetMap tiles around a location and each radar frame's
/// tiles over them, and RainViewer's coverage layer, stitched into one image per 3 by 3 block. The data layer for `RadarViewModel`.
enum RadarTileLoader {
    /// The OpenStreetMap tiles around `tile`.
    nonisolated static func baseMap(for tile: RadarTile) async -> CGImage? {
        await stitchTiles(tileX: tile.tileX, tileY: tile.tileY) { x, y in
            "https://tile.openstreetmap.org/\(RadarTiles.zoom)/\(x)/\(y).png"
        }
    }

    /// `frame`'s radar tiles around `tile`.
    nonisolated static func overlay(for frame: RadarFrame, in timeline: RadarTimeline, tile: RadarTile) async -> CGImage? {
        await stitchTiles(tileX: tile.tileX, tileY: tile.tileY) { x, y in
            timeline.tileURL(for: frame, z: RadarTiles.zoom, x: x, y: y)
        }
    }

    /// RainViewer's coverage tiles around `tile`: opaque black where there's no radar.
    nonisolated static func coverage(in timeline: RadarTimeline, tile: RadarTile) async -> CGImage? {
        await stitchTiles(tileX: tile.tileX, tileY: tile.tileY) { x, y in
            timeline.coverageURL(z: RadarTiles.zoom, x: x, y: y)
        }
    }

    /// OpenStreetMap's tile policy asks for a User-Agent that names the app (not the CFNetwork
    /// default) and for tiles to be cached per their headers, so tiles get their own session with
    /// an identifying User-Agent and a disk cache big enough to hold them.
    private nonisolated static let session: URLSession = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": "SunnyAndMisty/\(version) (+https://sunnyandmisty.com)"]
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }()

    /// Loads the 3×3 block of tiles around (`tileX`, `tileY`) concurrently and stitches them together.
    /// Tiles that fail are retried, only those, after each of `RadarTiles.retryDelays`; after the
    /// last try a partial image is still better than none. Returns nil when nothing loaded or the
    /// task was cancelled, so a cancelled load never yields a half-drawn mosaic.
    private nonisolated static func stitchTiles(
        tileX: Int,
        tileY: Int,
        urlBuilder: @escaping @Sendable (Int, Int) -> String
    ) async -> CGImage? {
        // Tiles are numbered 0...8, row by row from the north-west corner. Columns wrap around the
        // antimeridian, so a city near 180° still gets real tiles on both sides.
        let columns = 1 << RadarTiles.zoom
        func column(_ slot: Int) -> Int { ((tileX + slot % 3 - 1) % columns + columns) % columns }
        var loaded: [Int: CGImage] = [:]
        let all = Array(0 ..< 9)
        for attempt in 0 ... RadarTiles.retryDelays.count {
            if attempt > 0 {
                try? await Task.sleep(for: RadarTiles.retryDelays[attempt - 1])
            }
            guard !Task.isCancelled else { return nil }
            let missing = all.filter { loaded[$0] == nil }
            let fetched = await withTaskGroup(of: (Int, CGImage?).self) { group in
                for slot in missing {
                    group.addTask {
                        (slot, await loadTile(from: urlBuilder(column(slot), tileY + slot / 3 - 1)))
                    }
                }
                var results: [(Int, CGImage?)] = []
                for await result in group { results.append(result) }
                return results
            }
            for case let (slot, image?) in fetched { loaded[slot] = image }
            if loaded.count == all.count { break }
        }
        guard !Task.isCancelled, !loaded.isEmpty else { return nil }

        let size = 3 * RadarTiles.pixelSize
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        for (slot, image) in loaded {
            // CGContext's origin is bottom-left, so the northern row (slot 0...2) goes at the top.
            context.draw(image, in: CGRect(
                x: (slot % 3) * RadarTiles.pixelSize,
                y: (2 - slot / 3) * RadarTiles.pixelSize,
                width: RadarTiles.pixelSize,
                height: RadarTiles.pixelSize
            ))
        }
        return context.makeImage()
    }

    private nonisolated static func loadTile(from urlString: String) async -> CGImage? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                return nil
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        } catch {
            return nil
        }
    }
}
