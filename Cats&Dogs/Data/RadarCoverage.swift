import CoreGraphics

/// Whether RainViewer has radar where the city is. Outside its coverage its radar tiles come back
/// as ordinary empty images, which would read as "no rain", so the radar card reads its coverage
/// layer instead: each pixel is transparent where there is radar and opaque black where there
/// isn't. Same rules as Android's `RadarCoverage`.
enum RadarCoverage {
    /// How strongly the coverage layer dims the map where there's no radar.
    nonisolated static let dimming = 0.35

    /// A coverage pixel with this alpha has radar: only a fully transparent one does.
    nonisolated static func isCovered(alpha: UInt8) -> Bool {
        alpha == 0
    }

    /// Where the city falls in a stitched 3 by 3 block (the point the card centres on), in pixels
    /// from the top-left corner.
    nonisolated static func cityPixel(for tile: RadarTile) -> (x: Int, y: Int) {
        let size = 3 * RadarTiles.pixelSize
        func pixel(_ fraction: Double) -> Int {
            min(max(Int((1 + fraction) * Double(RadarTiles.pixelSize)), 0), size - 1)
        }
        return (pixel(tile.subFractionX), pixel(tile.subFractionY))
    }

    /// The alpha of one pixel, counted from the top-left corner; nil outside the image.
    nonisolated static func alpha(in image: CGImage, x: Int, y: Int) -> UInt8? {
        guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? rgba[3] : nil
    }

    /// Whether the stitched coverage image has radar at the city's position. A pixel that can't be
    /// read counts as covered, so a doubt never shows "No radar here".
    nonisolated static func isCovered(_ coverage: CGImage, at tile: RadarTile) -> Bool {
        let pixel = cityPixel(for: tile)
        guard let alpha = alpha(in: coverage, x: pixel.x, y: pixel.y) else { return true }
        return isCovered(alpha: alpha)
    }
}
