import SwiftUI

/// Today's details as a grid of tiles: feels like, wind, humidity, pavement, UV and air quality in pairs (an odd
/// one out takes the full width), then daylight (with the UV index, when UV has no tile) and the sky across the
/// full width. Each tile has a plain fact under its number; only the pavement, UV, air and sky tiles speak for
/// the pets. Remote Config can hide any of them. Same layout as Android's `TodayTiles`.
struct TodayTiles: View {
    let weather: CurrentWeather
    /// True when `weather` is the cached forecast's current hour standing in for an old reading:
    /// there's no cloud cover or visibility to show.
    let showingForecast: Bool
    /// The hour in progress's pavement estimate, in `weather`'s units; nil when not forecast.
    let pavementNow: Double?
    /// Rain or snow lately, or snow lying: below freezing the pavement tile warns of ice.
    let groundWet: Bool
    /// Today's UV index, or nil after dark or when not forecast.
    let uvIndex: Double?
    /// Today's hour with the highest UV, for the UV tile's peak.
    var uvPeak: HourlySlot? = nil
    /// Nil until it's fetched, or when it can't be.
    let airQuality: AirQuality?
    /// Air quality speaks of walks with a dog, of people without one.
    let hasDog: Bool
    let now: Date
    let thresholds: PetWeatherThresholds
    let distanceInMiles: Bool
    var switches = TodayTileSwitches()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let gap: CGFloat = 8

    private var showsDaylight: Bool {
        switches.daylight && weather.sunriseEpoch != nil && weather.sunsetEpoch != nil
    }

    /// UV gets its own tile when switched on, or when there's no Daylight tile to carry it.
    private var showsUVTile: Bool { uvIndex != nil && (switches.uv || !showsDaylight) }

    private var smallTiles: [AnyView] {
        var tiles: [AnyView] = []
        if switches.feelsLike { tiles.append(AnyView(feelsLike)) }
        if switches.wind { tiles.append(AnyView(wind)) }
        if switches.humidity { tiles.append(AnyView(humidity)) }
        if switches.pawCheck, let pavementNow { tiles.append(AnyView(pavement(pavementNow))) }
        if showsUVTile, let uvIndex { tiles.append(AnyView(uv(uvIndex))) }
        if let airQuality { tiles.append(AnyView(air(airQuality))) }
        return tiles
    }

    var body: some View {
        // Two tiles side by side leave too little room for accessibility text sizes, so those get one
        // per row.
        let perRow = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        VStack(spacing: Self.gap) {
            let tiles = smallTiles
            // An odd tile out (usually Air quality, when Paw check is showing) takes the full width
            // rather than leaving a gap beside it.
            let paired = tiles.count.isMultiple(of: perRow) ? tiles.count : tiles.count - 1
            EqualTileGrid(columns: perRow, spacing: Self.gap) {
                ForEach(0 ..< paired, id: \.self) { index in
                    tiles[index]
                }
            }
            if paired < tiles.count {
                tiles[paired]
            }
            if showsDaylight, let sunrise = weather.sunriseEpoch, let sunset = weather.sunsetEpoch {
                daylight(sunrise: sunrise, sunset: sunset)
            }
            if switches.sky { sky }
        }
    }

    // MARK: Tiles

    /// The feels-like temperature with its band ("Hot"), the band bar, and how far it is from the
    /// actual temperature.
    private var feelsLike: some View {
        let feelsLikeC = weather.units.toCelsius(weather.feelsLike)
        let band = TodayDetails.feelsLikeBand(feelsLikeC: feelsLikeC, thresholds: thresholds)
        return Tile(icon: "thermometer.medium", label: "Feels Like") {
            // The same size as the other tiles' values, as Air Quality has its band beside it.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TileValue(WeatherFormatting.temperature(weather.feelsLike, units: weather.units))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(band.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(feelsLikeTint(band))
                    .lineLimit(1)
            }
            BandBar(
                bands: Self.feelsLikeBands(dark: colorScheme == .dark),
                position: TodayDetails.feelsLikeBarPosition(feelsLikeC: feelsLikeC, thresholds: thresholds)
            )
            .padding(.vertical, 2)
            .accessibilityHidden(true)
            TileNote(TodayDetails.feelsLikeGap(feelsLike: weather.feelsLike, temperature: weather.temperature))
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

    private var wind: some View {
        let force = TodayDetails.windForce(speed: weather.windSpeed, units: weather.units)
        let calm = force == 0 || WeatherFormatting.isCalm(weather.windSpeed, units: weather.units)
        return Tile(icon: "wind", label: "Wind") {
            HStack(spacing: 10) {
                WindCompass(fromDegrees: calm ? nil : weather.windDeg)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                TileValue(WeatherFormatting.wind(weather.windSpeed, units: weather.units))
            }
            // The arrow shows the direction, so the note is just the wind's name; VoiceOver, which
            // can't see the arrow, hears the direction too.
            TileNote(
                calm ? "Calm" : TodayDetails.windForceNames[force],
                spoken: calm
                    ? nil
                    : "From the \(TodayDetails.spokenCompassPoint(weather.windDeg)), \(TodayDetails.windForceNames[force])"
            )
        }
    }

    /// Fluff Factor: the humidity with the dew point under it, beside Misty, whose fur fluffs up as
    /// the dew point rises, and her line about it.
    private var humidity: some View {
        let dewC = TodayDetails.dewPointC(
            temperatureC: weather.units.toCelsius(weather.temperature),
            humidityPercent: weather.humidityPercent
        )
        let level = TodayDetails.fluffLevel(dewPointC: dewC, humidityPercent: weather.humidityPercent)
        return Tile(icon: "drop.fill", label: "Fluff Factor") {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    TileValue("\(weather.humidityPercent)%")
                        .accessibilityLabel("Humidity \(weather.humidityPercent)%")
                    if let dewC {
                        Text("Dew point \(WeatherFormatting.temperature(weather.units.fromCelsius(dewC), units: weather.units, showsUnit: false))")
                            .font(.footnote)
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                FluffyMisty(level: level)
                    .frame(width: 48, height: 42)
                    .accessibilityHidden(true)
            }
            TileNote(TodayDetails.fluffLine(level, hasDog: hasDog))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func pavement(_ pavement: Double) -> some View {
        let band = TodayDetails.pavementBand(
            pavementC: weather.units.toCelsius(pavement),
            groundWet: groundWet,
            feelsLikeC: weather.units.toCelsius(weather.feelsLike),
            thresholds: thresholds
        )
        return Tile(icon: "pawprint.fill", label: "Paw Check") {
            // An estimate for dark asphalt in direct sun, so a whole number, and said to be one.
            TileValue("About \(WeatherFormatting.temperature(pavement, units: weather.units))")
            // The note says it in words.
            PawScale(step: band.pawScaleStep)
                .accessibilityHidden(true)
            TileNote(band.line, color: pavementTint(band))
        }
    }

    /// Same shades as the walk card's ratings: dark text on the light theme, pale on the dark. Blue
    /// for icy and below freezing, as on the paw scale.
    private func pavementTint(_ band: TodayDetails.PavementBand) -> Color {
        let (light, dark): (UInt32, UInt32) = switch band {
        case .safe: (0x27500A, 0xC0DD97)
        case .warm, .pavementOK: (0x633806, 0xFAC775)
        case .freezing, .icy: (0x0C447C, 0xB5D4F4)
        case .tooHot, .dangerous: (0x791F1F, 0xF7C1C1)
        }
        return Color(hex: colorScheme == .dark ? dark : light)
    }

    private func air(_ air: AirQuality) -> some View {
        Tile(icon: "aqi.medium", label: "Air Quality") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TileValue("\(air.index)")
                Text(air.bandName)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
            BandBar(bands: BandBar.airQuality, position: air.barPosition)
                .padding(.vertical, 2)
                .accessibilityHidden(true)
            // The pollutant behind it is for VoiceOver only: another line would stretch every tile
            // in the grid, which all take the tallest one's height.
            TileNote(
                air.line(hasDog: hasDog),
                color: airTint(band: air.band),
                spoken: [air.pollutantLine, air.line(hasDog: hasDog)].compactMap(\.self).joined(separator: ". ")
            )
        }
    }

    /// The walk card's shades again: green for good air, amber for so-so, red from unhealthy up.
    private func airTint(band: Int) -> Color {
        let (light, dark): (UInt32, UInt32) = switch band {
        case 0: (0x27500A, 0xC0DD97)
        case 1, 2: (0x633806, 0xFAC775)
        default: (0x791F1F, 0xF7C1C1)
        }
        return Color(hex: colorScheme == .dark ? dark : light)
    }

    private var petLineTint: Color {
        Color(hex: colorScheme == .dark ? 0xC0DD97 : 0x27500A)
    }

    private func uv(_ uv: Double) -> some View {
        let line = TodayDetails.uvLine(peak: uvPeak, now: now, hasDog: hasDog)
        return Tile(icon: "sun.max.fill", label: "UV Index") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TileValue("\(Int(uv.rounded()))")
                Text(WeatherFormatting.uvLevel(uv))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
            if !line.text.isEmpty {
                TileNote(line.text, color: line.isPetLine ? petLineTint : .secondaryText)
            }
        }
    }

    private func daylight(sunrise: Int, sunset: Int) -> some View {
        let state = TodayDetails.daylight(now: Int(now.timeIntervalSince1970), sunrise: sunrise, sunset: sunset)
        let fraction: Double
        let summary: String
        switch state {
        case .beforeSunrise(let secondsUntil):
            fraction = 0
            summary = "Sunrise in \(TodayDetails.duration(seconds: secondsUntil))"
        case .daytime(let secondsLeft, let dayFraction):
            fraction = dayFraction
            summary = "\(TodayDetails.duration(seconds: secondsLeft)) left"
        case .afterSunset:
            fraction = 1
            summary = "The sun has set"
        }
        let isUp = if case .daytime = state { true } else { false }
        let uvNote = showsUVTile ? nil : uvIndex.map { "UV \(Int($0.rounded())) · \(WeatherFormatting.uvLevel($0))" }
        return Tile(icon: "sun.horizon.fill", label: "Daylight", trailing: uvNote) {
            SunArc(fraction: fraction, isUp: isUp)
                .frame(height: 44)
                .accessibilityHidden(true)
            let sunriseTime = TileNote(WeatherFormatting.epochTime(sunrise, timeZone: weather.timeZone)).fixedSize()
            let sunsetTime = TileNote(WeatherFormatting.epochTime(sunset, timeZone: weather.timeZone)).fixedSize()
            let summaryText = Text(summary).font(.subheadline.weight(.medium))
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

    private var sky: some View {
        let sky = TodayDetails.skyCondition(
            conditionMain: weather.conditionMain,
            cloudPercent: showingForecast ? nil : weather.cloudPercent,
            iconCode: weather.iconCode
        )
        let visibility = showingForecast ? nil : weather.visibilityMeters
        let band = visibility.map { TodayDetails.visibilityBand(meters: $0) }
        let headline: String = if let visibility, let band {
            if let distance = TodayDetails.visibilityDistance(meters: visibility, inMiles: distanceInMiles) {
                "\(sky.rawValue) · \(band.name), \(distance)"
            } else {
                "\(sky.rawValue) · \(band.name)"
            }
        } else {
            sky.rawValue
        }
        return Tile(icon: "eye.fill", label: "Sky") {
            Text(TodayDetails.keepUnitsTogether(headline))
                .font(.brand(.headline))
            if let band {
                TileNote(band.mistyLine, color: petLineTint)
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
    let label: String
    @Environment(\.seasonalTheme) private var seasonalTheme
    /// Extra detail at the right of the label row, such as the UV index on the Daylight tile.
    var trailing: String?
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(icon: String, label: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
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

/// A compass dial with N at the top and an arrow pointing the way the wind blows, as Apple and Google
/// Weather draw it: a wind from the NW points SE. No arrow when it's calm.
private struct WindCompass: View {
    let fromDegrees: Int?

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1
            let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(ring, with: .color(Color.accent.opacity(0.35)), lineWidth: 1.5)
            context.draw(
                Text("N").font(.system(size: 8, weight: .medium)).foregroundStyle(Color.accent),
                at: CGPoint(x: center.x, y: center.y - radius + 6)
            )
            guard let fromDegrees else { return }
            // Drawn pointing north, then turned to point downwind (from + 180°).
            var arrowContext = context
            arrowContext.translateBy(x: center.x, y: center.y)
            arrowContext.rotate(by: .degrees(Double(fromDegrees) + 180))
            let reach = radius * 0.5
            var shaft = Path()
            shaft.move(to: CGPoint(x: 0, y: reach))
            shaft.addLine(to: CGPoint(x: 0, y: -reach))
            arrowContext.stroke(shaft, with: .color(.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            let head = radius * 0.32
            var tip = Path()
            tip.move(to: CGPoint(x: 0, y: -reach - 2))
            tip.addLine(to: CGPoint(x: -head * 0.7, y: -reach + head * 0.6))
            tip.addLine(to: CGPoint(x: head * 0.7, y: -reach + head * 0.6))
            tip.closeSubpath()
            arrowContext.fill(tip, with: .color(.accent))
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
