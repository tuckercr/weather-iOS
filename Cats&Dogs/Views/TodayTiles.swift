import SwiftUI

/// Today's details as a grid of tiles: feels like, wind, humidity, pavement, UV and air quality in pairs (an odd
/// one out takes the full width), then daylight (with the UV index, when UV has no tile) and Misty's View (the
/// sky and how far she can see) across the full width. Which tiles show and what each says comes worked out in
/// `TodayTilesState`; this lays them out and colours them. Same layout as Android's `TodayTiles`.
struct TodayTiles: View {
    let state: TodayTilesState

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let gap: CGFloat = 8

    var body: some View {
        // Two tiles side by side leave too little room for accessibility text sizes, so those get one
        // per row.
        let perRow = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        VStack(spacing: Self.gap) {
            let tiles = state.small
            // An odd tile out (usually Air quality, when Paw check is showing) takes the full width
            // rather than leaving a gap beside it.
            let paired = tiles.count.isMultiple(of: perRow) ? tiles.count : tiles.count - 1
            EqualTileGrid(columns: perRow, spacing: Self.gap) {
                ForEach(0 ..< paired, id: \.self) { index in
                    tile(tiles[index])
                }
            }
            if paired < tiles.count {
                tile(tiles[paired])
            }
            if let daylight = state.daylight { self.daylight(daylight) }
            if let sky = state.sky { self.sky(sky) }
        }
    }

    @ViewBuilder
    private func tile(_ tile: TodayTile) -> some View {
        switch tile {
        case let .feelsLike(tile): feelsLike(tile)
        case let .wind(tile): wind(tile)
        case let .fluff(tile): fluff(tile)
        case let .pawCheck(tile): pavement(tile)
        case let .uv(tile): uv(tile)
        case let .air(tile): air(tile)
        }
    }

    // MARK: Tiles

    /// The feels-like temperature with its band ("Hot"), the band bar, and how far it is from the
    /// actual temperature.
    private func feelsLike(_ tile: FeelsLikeTile) -> some View {
        Tile(icon: "thermometer.medium", label: "Feels Like") {
            // The same size as the other tiles' values, as Air Quality has its band beside it.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TileValue(tile.value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(tile.band.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(feelsLikeTint(tile.band))
                    .lineLimit(1)
            }
            BandBar(bands: Self.feelsLikeBands(dark: colorScheme == .dark), position: tile.barPosition)
                .padding(.vertical, 2)
                .accessibilityHidden(true)
            TileNote(tile.note)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Cold to hot. The two blues are lighter on the dark theme, where the darker one barely shows.
    private static func feelsLikeBands(dark: Bool) -> [UInt32] {
        [dark ? 0x378ADD : 0x185FA5, dark ? 0x85B7EB : 0x378ADD, 0x4CAF50, 0xF08C2E, 0xD94141]
    }

    /// The walk card's shades: blue for cold and chilly, green for mild, amber for warm, red for hot.
    private func feelsLikeTint(_ band: TodayDetails.FeelsLikeBand) -> Color {
        let (light, dark): (UInt32, UInt32) = switch band {
        case .cold, .chilly: (0x0C447C, 0xB5D4F4)
        case .mild: (0x27500A, 0xC0DD97)
        case .warm: (0x633806, 0xFAC775)
        case .hot: (0x791F1F, 0xF7C1C1)
        }
        return Color(hex: colorScheme == .dark ? dark : light)
    }

    /// The speed beside a windsock whose droop shows the strength, with where the wind comes from
    /// and any gusts that stand out underneath.
    private func wind(_ tile: WindTile) -> some View {
        Tile(icon: "wind", label: "Wind") {
            HStack(alignment: .center, spacing: 8) {
                TileValue(tile.value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Windsock(droopDegrees: tile.droopDegrees)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
            TileNote(tile.note, spoken: tile.spokenNote)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Fluff Factor: the humidity with the dew point under it, beside Misty, whose fur fluffs up as
    /// the dew point rises, and her line about it.
    private func fluff(_ tile: FluffTile) -> some View {
        Tile(icon: "drop.fill", label: "Fluff Factor") {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    TileValue("\(tile.humidityPercent)%")
                        .accessibilityLabel("Humidity \(tile.humidityPercent)%")
                    if let dewPoint = tile.dewPoint {
                        Text(dewPoint)
                            .font(.footnote)
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                FluffyMisty(level: tile.level)
                    .frame(width: 48, height: 42)
                    .accessibilityHidden(true)
            }
            TileNote(tile.line)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func pavement(_ tile: PawCheckTile) -> some View {
        Tile(icon: "pawprint.fill", label: "Paw Check") {
            TileValue(tile.value)
            // The note says it in words.
            PawScale(step: tile.band.pawScaleStep)
                .accessibilityHidden(true)
            TileNote(tile.band.line, color: pavementTint(tile.band))
        }
    }

    /// Same shades as the walk card's ratings: dark text on the light theme, pale on the dark. Each
    /// band takes its paw's colour on the scale above it: blue for icy and below freezing, and green
    /// for fine underfoot as for safe, since the pavement is fine and it's the air the walk card is
    /// warning about.
    private func pavementTint(_ band: TodayDetails.PavementBand) -> Color {
        let (light, dark): (UInt32, UInt32) = switch band {
        case .safe, .pavementOK: (0x27500A, 0xC0DD97)
        case .warm: (0x633806, 0xFAC775)
        case .freezing, .icy: (0x0C447C, 0xB5D4F4)
        case .tooHot, .dangerous: (0x791F1F, 0xF7C1C1)
        }
        return Color(hex: colorScheme == .dark ? dark : light)
    }

    private func air(_ tile: AirTile) -> some View {
        Tile(icon: "aqi.medium", label: "Air Quality") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TileValue("\(tile.index)")
                Text(tile.bandName)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
            BandBar(bands: BandBar.airQuality, position: tile.barPosition)
                .padding(.vertical, 2)
                .accessibilityHidden(true)
            // The pollutant behind it is for VoiceOver only: another line would stretch every tile
            // in the grid, which all take the tallest one's height.
            TileNote(tile.line, color: airTint(tile.tone), spoken: tile.spokenLine)
        }
    }

    /// The walk card's shades again: green for good air, amber for so-so, red for bad.
    private func airTint(_ tone: AirTile.Tone) -> Color {
        let (light, dark): (UInt32, UInt32) = switch tone {
        case .bad: (0x791F1F, 0xF7C1C1)
        case .good: (0x27500A, 0xC0DD97)
        case .soSo: (0x633806, 0xFAC775)
        }
        return Color(hex: colorScheme == .dark ? dark : light)
    }

    private var petLineTint: Color {
        Color(hex: colorScheme == .dark ? 0xC0DD97 : 0x27500A)
    }

    private func uv(_ tile: UVTile) -> some View {
        Tile(icon: "sun.max.fill", label: "UV Index") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TileValue("\(tile.value)")
                Text(tile.level)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
            if !tile.line.isEmpty {
                TileNote(tile.line, color: tile.isPetLine ? petLineTint : .secondaryText)
            }
        }
    }

    private func daylight(_ tile: DaylightTile) -> some View {
        Tile(icon: "sun.horizon.fill", label: "Daylight", trailing: tile.uvNote) {
            SunArc(fraction: tile.fraction, isUp: tile.isUp)
                .frame(height: 44)
                .accessibilityHidden(true)
            let sunriseTime = TileNote(tile.sunrise).fixedSize()
            let sunsetTime = TileNote(tile.sunset).fixedSize()
            let summaryText = Text(tile.summary).font(.subheadline.weight(.medium))
            if dynamicTypeSize.isAccessibilitySize {
                // No room for all three on one line: the summary goes above the times.
                summaryText
                HStack {
                    sunriseTime
                    Spacer()
                    sunsetTime
                }
            } else {
                HStack(spacing: 8) {
                    sunriseTime
                    summaryText
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    sunsetTime
                }
            }
        }
    }

    private func sky(_ tile: SkyTile) -> some View {
        Tile(icon: "eye.fill", label: "Misty's View") {
            Text(tile.headline)
                .font(.brand(.headline))
            if let mistyLine = tile.mistyLine {
                TileNote(mistyLine, color: petLineTint)
            }
        }
    }
}

// MARK: - Building blocks

/// The small tiles in rows of `columns`. Side by side, every tile is as tall as the tallest, so the
/// grid reads as one block however much each tile holds; one per row, each keeps its own height.
private struct EqualTileGrid: Layout {
    let columns: Int
    let spacing: CGFloat

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private func heights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        let natural = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        guard columns > 1, let tallest = natural.max() else { return natural }
        return natural.map { _ in tallest }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rowHeights = rows(heights(subviews, width: columnWidth(width)))
        let height = rowHeights.reduce(0, +) + spacing * CGFloat(max(rowHeights.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = columnWidth(bounds.width)
        let tileHeights = heights(subviews, width: width)
        let rowHeights = rows(tileHeights)
        var y = bounds.minY
        for (row, rowHeight) in rowHeights.enumerated() {
            for column in 0 ..< columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (width + spacing), y: y),
                    proposal: ProposedViewSize(width: width, height: rowHeight)
                )
            }
            y += rowHeight + spacing
        }
    }

    /// Each row is as tall as its tallest tile.
    private func rows(_ tileHeights: [CGFloat]) -> [CGFloat] {
        stride(from: 0, to: tileHeights.count, by: columns).map { start in
            tileHeights[start ..< min(start + columns, tileHeights.count)].max() ?? 0
        }
    }
}

private struct Tile<Content: View>: View {
    let icon: String
    let label: LocalizedStringKey
    @Environment(\.seasonalTheme) private var seasonalTheme
    /// Extra detail at the right of the label row, such as the UV index on the Daylight tile.
    var trailing: String?
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(icon: String, label: LocalizedStringKey, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.label = label
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // At accessibility sizes the trailing detail goes under the label rather than squeezing it.
            let header = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 6))
            header {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                    Text(label)
                        .font(.subheadline.weight(.medium))
                }
                if let trailing {
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Text(TodayDetails.keepUnitsTogether(trailing))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                }
            }
            .foregroundStyle(seasonalTheme?.tileHeader ?? Color.accent)
            content
        }
        // Fills whatever height the grid gives it, so tiles side by side match.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.card(seasonalTheme), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// The Paw Check tile's five paws, icy to dangerous: the pavement's own full size and colour, the
/// rest small and faded. Same colours as Android's `PawScale`.
private struct PawScale: View {
    let step: Int
    @Environment(\.colorScheme) private var colorScheme

    /// Blue, green, orange, red and maroon, like the Feels Like and Air Quality bars. The blue and
    /// the maroon are lighter on the dark theme, where the darker ones barely show.
    private var colors: [UInt32] {
        colorScheme == .dark
            ? [0x85B7EB, 0x4CAF50, 0xF08C2E, 0xD94141, 0xC25A68]
            : [0x378ADD, 0x4CAF50, 0xF08C2E, 0xD94141, 0x7A2230]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(colors.indices, id: \.self) { index in
                Image(systemName: "pawprint.fill")
                    .font(.system(size: index == step ? 20 : 13))
                    // A little stronger on the dark card, where faint colours turn muddy.
                    .foregroundStyle(Color(hex: colors[index]).opacity(index == step ? 1 : colorScheme == .dark ? 0.4 : 0.3))
            }
        }
    }
}

private struct TileValue: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(TodayDetails.keepUnitsTogether(text))
            .font(.title3.weight(.semibold))
    }
}

private struct TileNote: View {
    let text: String
    var color: Color = .secondaryText
    /// What VoiceOver says instead of `text`, when the text alone reads badly ("From the NW").
    var spoken: String?

    init(_ text: String, color: Color = .secondaryText, spoken: String? = nil) {
        self.text = text
        self.color = color
        self.spoken = spoken
    }

    var body: some View {
        Text(TodayDetails.keepUnitsTogether(text))
            .font(.subheadline)
            .foregroundStyle(color)
            .accessibilityLabel(spoken ?? TodayDetails.keepUnitsTogether(text))
    }
}

/// Bands of equal width, such as the air quality bands from good to worst, with a mark where the
/// reading sits.
private struct BandBar: View {
    let bands: [UInt32]
    /// 0 to 1 along the bar.
    let position: Double

    /// The six air quality bands, good to worst.
    static let airQuality: [UInt32] = [0x4CAF50, 0xE6C531, 0xF08C2E, 0xD94141, 0x8E4AA8, 0x7A2230]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(bands.indices, id: \.self) { Color(hex: bands[$0]) }
                }
                .frame(height: 6)
                .clipShape(Capsule())
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 4, height: 12)
                    .offset(x: min(max(proxy.size.width * position - 2, 0), proxy.size.width - 4))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
    }
}

/// A windsock on its pole, side on: limp when calm, flying straight out in a strong breeze. Five
/// stripes, orange and white, narrowing to the tail. Same drawing as Android's `Windsock`.
private struct Windsock: View {
    /// Below the horizontal, from `TodayDetails.windsockDroopDegrees`.
    let droopDegrees: Double
    @Environment(\.colorScheme) private var colorScheme

    private static let orange = Color(hex: 0xF08C2E)
    private static let seam = Color(hex: 0xB3621C)

    var body: some View {
        Canvas { context, size in
            // Low enough that the mouth clears the top when it flies straight out.
            let pivot = CGPoint(x: 3, y: 7)
            var pole = Path()
            pole.move(to: CGPoint(x: pivot.x, y: 1.5))
            pole.addLine(to: CGPoint(x: pivot.x, y: size.height - 1.5))
            let poleColor = Color(hex: colorScheme == .dark ? 0xB4B2A9 : 0x5F5E5A)
            context.stroke(pole, with: .color(poleColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            // Drawn flying straight out to the right of the pivot, then turned down by the droop.
            var sock = context
            sock.translateBy(x: pivot.x, y: pivot.y)
            sock.rotate(by: .degrees(droopDegrees))
            let length = min(size.width - pivot.x - 2, size.height - pivot.y - 2)
            let mouth = length * 0.17
            let tail = length * 0.08
            let stripes = 5
            for stripe in 0 ..< stripes {
                let x0 = length * Double(stripe) / Double(stripes)
                let x1 = length * Double(stripe + 1) / Double(stripes)
                let h0 = mouth + (tail - mouth) * Double(stripe) / Double(stripes)
                let h1 = mouth + (tail - mouth) * Double(stripe + 1) / Double(stripes)
                var band = Path()
                band.move(to: CGPoint(x: x0, y: -h0))
                band.addLine(to: CGPoint(x: x1, y: -h1))
                band.addLine(to: CGPoint(x: x1, y: h1))
                band.addLine(to: CGPoint(x: x0, y: h0))
                band.closeSubpath()
                sock.fill(band, with: .color(stripe.isMultiple(of: 2) ? Self.orange : .white))
                sock.stroke(band, with: .color(Self.seam), lineWidth: 0.6)
            }
        }
    }
}

/// Misty's head, as in the hero, with her fur sleek in dry air and fluffing up as it gets muggy: a
/// ring of tufts round her head grows with each `FluffLevel`, and dry air gives her static sparks.
/// Drawn on a 60 x 52 grid. Same drawing as Android's `FluffyMisty`.
private struct FluffyMisty: View {
    let level: TodayDetails.FluffLevel
    @Environment(\.colorScheme) private var colorScheme

    /// How far the tufts reach past her head, by level.
    private static let tuftReach: [CGFloat] = [0, 0, 1.4, 2.6, 4]

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 60, size.height / 52)
            let origin = CGPoint(x: (size.width - 60 * scale) / 2, y: (size.height - 52 * scale) / 2)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
            }
            func poly(_ color: Color, _ points: [(CGFloat, CGFloat)]) {
                var path = Path()
                path.addLines(points.map { point($0.0, $0.1) })
                path.closeSubpath()
                context.fill(path, with: .color(color))
            }
            func oval(_ color: Color, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
                let rect = CGRect(x: origin.x + (cx - rx) * scale, y: origin.y + (cy - ry) * scale, width: rx * 2 * scale, height: ry * 2 * scale)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
            // Lighter on the dark card, where her usual grey sinks into it.
            let fur = Color(hex: colorScheme == .dark ? 0x8C8B85 : 0x5F5E5A)
            let reach = Self.tuftReach[level.rawValue]
            if reach > 0 {
                let tufts = 18
                poly(fur, (0 ..< tufts).map { index in
                    let angle = Double(index) / Double(tufts) * 2 * .pi - .pi / 2
                    let radius = 17 + (index.isMultiple(of: 2) ? 0 : reach)
                    return (30 + radius * CGFloat(cos(angle)), 31 + radius * CGFloat(sin(angle)))
                })
            }
            poly(fur, [(15, 22), (18, 6), (27, 17)])
            poly(fur, [(33, 17), (42, 6), (45, 22)])
            poly(Color(hex: 0xED93B1), [(18, 19), (19.5, 11), (24, 17)])
            poly(Color(hex: 0xED93B1), [(36, 17), (40.5, 11), (42, 19)])
            oval(fur, 30, 31, 16, 16)
            poly(Color(hex: 0xF1EFE8), [(28.5, 17), (31.5, 17), (34, 33), (26, 33)])
            oval(Color(hex: 0xF1EFE8), 26, 36, 6, 5)
            oval(Color(hex: 0xF1EFE8), 34, 36, 6, 5)
            oval(Color(hex: 0x10324A), 24.5, 28, 2, 2)
            oval(Color(hex: 0x10324A), 35.5, 28, 2, 2)
            poly(Color(hex: 0xE8849A), [(28.2, 32), (31.8, 32), (30, 34.3)])
            if level == .dry {
                // Static sparks either side.
                var sparks = Path()
                sparks.addLines([point(5, 12), point(9, 15), point(6, 17), point(10, 21)])
                sparks.addLines([point(55, 12), point(51, 15), point(54, 17), point(50, 21)])
                context.stroke(sparks, with: .color(Color(hex: 0xEF9F27)), style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// The sun's path from sunrise (left) to sunset (right), solid up to now, with the sun on it.
private struct SunArc: View {
    let fraction: Double
    let isUp: Bool

    private static let sun = Color(hex: 0xEF9F27)

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 6
            let start = CGPoint(x: inset, y: size.height - 2)
            let end = CGPoint(x: size.width - inset, y: size.height - 2)
            // The control point sits above the frame so the curve's peak reaches near the top.
            let control = CGPoint(x: size.width / 2, y: -size.height + 8)
            var track = Path()
            track.move(to: start)
            track.addQuadCurve(to: end, control: control)
            context.stroke(track, with: .color(Color.accent.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))

            let t = min(max(fraction, 0), 1)
            // de Casteljau: the part of the curve from sunrise to t is itself a quadratic.
            let partControl = lerp(start, control, t)
            let nowPoint = lerp(partControl, lerp(control, end, t), t)
            var done = Path()
            done.move(to: start)
            done.addQuadCurve(to: nowPoint, control: partControl)
            let sun = isUp ? Self.sun : Self.sun.opacity(0.45)
            context.stroke(done, with: .color(sun), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: nowPoint.x - 6, y: nowPoint.y - 6, width: 12, height: 12)), with: .color(sun))
        }
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
