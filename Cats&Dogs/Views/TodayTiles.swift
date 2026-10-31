import SwiftUI

/// Today's details as a grid of tiles: feels like, wind, humidity, pavement and air quality in pairs (an odd one
/// out takes the full width), then daylight (with the UV index) and the sky across the full width. Each tile has a plain fact under its number; only the
/// pavement and sky tiles speak for the pets. Same layout as Android's `TodayTiles`.
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
    /// Nil until it's fetched, or when it can't be.
    let airQuality: AirQuality?
    /// Air quality speaks of walks with a dog, of people without one.
    let hasDog: Bool
    let now: Date
    let thresholds: PetWeatherThresholds
    let distanceInMiles: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let gap: CGFloat = 8

    private var hasDaylight: Bool { weather.sunriseEpoch != nil && weather.sunsetEpoch != nil }

    private var smallTiles: [AnyView] {
        var tiles = [AnyView(feelsLike), AnyView(wind), AnyView(humidity)]
        if let pavementNow { tiles.append(AnyView(pavement(pavementNow))) }
        if let airQuality { tiles.append(AnyView(air(airQuality))) }
        // UV normally rides in the Daylight tile's header; only without sunrise and sunset does it
        // need a tile of its own.
        if let uvIndex, !hasDaylight { tiles.append(AnyView(uv(uvIndex))) }
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
            if let sunrise = weather.sunriseEpoch, let sunset = weather.sunsetEpoch {
                daylight(sunrise: sunrise, sunset: sunset)
            }
            sky
        }
    }

    // MARK: Tiles

    private var feelsLike: some View {
        Tile(icon: "thermometer.medium", label: "Feels like") {
            TileValue(WeatherFormatting.temperature(weather.feelsLike, units: weather.units))
            TileNote("Actual \(WeatherFormatting.temperature(weather.temperature, units: weather.units))")
        }
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

    private var humidity: some View {
        Tile(icon: "drop.fill", label: "Humidity") {
            TileValue("\(weather.humidityPercent)%")
            ProgressView(value: Double(weather.humidityPercent), total: 100)
                .tint(Color.accent)
                .padding(.vertical, 2)
                .accessibilityHidden(true)
            if let dewC = TodayDetails.dewPointC(
                temperatureC: weather.units.toCelsius(weather.temperature),
                humidityPercent: weather.humidityPercent
            ) {
                TileNote("Dew point \(WeatherFormatting.temperature(weather.units.fromCelsius(dewC), units: weather.units))")
            }
        }
    }

    private func pavement(_ pavement: Double) -> some View {
        let band = TodayDetails.pavementBand(
            pavementC: weather.units.toCelsius(pavement),
            groundWet: groundWet,
            feelsLikeC: weather.units.toCelsius(weather.feelsLike),
            thresholds: thresholds
        )
        return Tile(icon: "pawprint.fill", label: "Paw check") {
            // An estimate for dark asphalt in direct sun, so a whole number, and said to be one.
            TileValue("About \(Int(pavement.rounded())) \(weather.units == .metric ? "°C" : "°F")")
            TileNote(band.line, color: pavementTint(band))
        }
    }

    /// Same shades as the walk card's ratings: dark text on the light theme, pale on the dark.
    private func pavementTint(_ band: TodayDetails.PavementBand) -> Color {
        let (light, dark): (UInt32, UInt32) = switch band {
        case .safe: (0x27500A, 0xC0DD97)
        case .warm, .pavementOK, .freezing, .icy: (0x633806, 0xFAC775)
        case .tooHot, .dangerous: (0x791F1F, 0xF7C1C1)
        }
        return Color(hex: colorScheme == .dark ? dark : light)
    }

    private func air(_ air: AirQuality) -> some View {
        Tile(icon: "aqi.medium", label: "Air quality") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TileValue("\(air.index)")
                Text(air.bandName)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
            AirQualityBar(position: air.barPosition)
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
        Tile(icon: "sun.max.fill", label: "UV index") {
            TileValue("\(Int(uv.rounded()))")
            TileNote(WeatherFormatting.uvLevel(uv))
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
        let uvNote = uvIndex.map { "UV \(Int($0.rounded())) · \(WeatherFormatting.uvLevel($0))" }
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
            .foregroundStyle(Color.accent)
            content
        }
        // Fills whatever height the grid gives it, so tiles side by side match.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.surfaceVariant, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
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

/// The six air quality bands, good to worst, with a mark where the reading sits.
private struct AirQualityBar: View {
    /// 0 to 1 along the bar.
    let position: Double

    private static let bands: [UInt32] = [0x4CAF50, 0xE6C531, 0xF08C2E, 0xD94141, 0x8E4AA8, 0x7A2230]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Self.bands, id: \.self) { Color(hex: $0) }
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
