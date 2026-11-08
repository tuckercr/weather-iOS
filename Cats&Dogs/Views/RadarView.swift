import SwiftUI


/// Radar precipitation legend, light (low intensity) to heavy (high intensity).
private let radarLegendColors: [Color] = [
    Color(red: 0x8C / 255, green: 0xD9 / 255, blue: 0xFF / 255),
    Color(red: 0x2E / 255, green: 0x9B / 255, blue: 0xE6 / 255),
    Color(red: 0x39 / 255, green: 0xC2 / 255, blue: 0x4A / 255),
    Color(red: 0xF4 / 255, green: 0xE0 / 255, blue: 0x4D / 255),
    Color(red: 0xF3 / 255, green: 0x9B / 255, blue: 0x2E / 255),
    Color(red: 0xE2 / 255, green: 0x4B / 255, blue: 0x4B / 255),
]

struct RadarCard: View {
    let location: SavedLocation?
    /// The city's time zone, so frame times read on its clock rather than the device's.
    var timeZone: TimeZone = .current

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Group {
                if let location, let latitude = location.latitude, let longitude = location.longitude {
                    RadarMapView(latitude: latitude, longitude: longitude, timeZone: timeZone)
                } else if location == nil {
                    placeholder("No location selected")
                } else {
                    placeholder("Radar unavailable\n(coordinates not available)")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 340)
            .background(Color.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if location?.latitude != nil, location?.longitude != nil {
                RadarCredits()
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// OpenStreetMap's licence requires visible attribution linking to its copyright page, and
/// RainViewer asks to be credited for its free radar data. Kept at caption2's default size whatever
/// the Dynamic Type setting, so the credit stays a small footnote under the map. Same as Android.
private struct RadarCredits: View {
    var body: some View {
        Text("[© OpenStreetMap contributors](https://www.openstreetmap.org/copyright) · Radar by [RainViewer](https://www.rainviewer.com)")
            .font(.caption2)
            .dynamicTypeSize(.large)
            .foregroundStyle(Color.secondaryText)
            .tint(Color.secondaryText)
            .multilineTextAlignment(.trailing)
    }
}

/// An OpenStreetMap base map with RainViewer's radar frames animated over it.
private struct RadarMapView: View {
    let latitude: Double
    let longitude: Double
    let timeZone: TimeZone

    @Environment(RadarViewModel.self) private var radar

    @Environment(\.scenePhase) private var scenePhase
    /// The tile playback last started on, so a new location starts playing again.
    @State private var playbackTile: RadarTile?
    @State private var frameIndex = 0
    @State private var playing = true

    private var tileInfo: RadarTile {
        RadarTile.from(latitude: latitude, longitude: longitude, zoom: RadarTiles.zoom)
    }

    private var timeline: RadarTimeline? { radar.timeline.successValue }
    private var frames: [RadarFrame] { timeline?.frames ?? [] }
    /// The most recent observed frame: "now".
    private var nowIndex: Int { frames.lastIndex { !$0.isForecast } ?? 0 }

    var body: some View {
        ZStack {
            RadarCanvas(
                tileInfo: tileInfo,
                baseMap: radar.baseMap,
                overlay: frames.indices.contains(frameIndex) ? radar.overlays[frames[frameIndex].path] : nil
            )

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    if frames.indices.contains(frameIndex) {
                        OverlayChip {
                            Text(frameLabel(frames[frameIndex], isNow: frameIndex == nowIndex))
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    Spacer()
                    RadarLegend()
                }
                Spacer()
                bottomBar
            }
            .padding(8)
        }
        // While the screen stays open, keep the frames current, but only while the radar is in view.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: RadarViewModel.recheckInterval)
                guard !Task.isCancelled else { return }
                radar.recheck()
            }
        }
        // The card starts below the fold on a phone, so watch whether any of it is inside the scroll
        // view's visible area. Not reset when the screen goes away: the re-check above stops with it,
        // and the geometry may not report again when the screen comes back.
        .onGeometryChange(for: Bool.self) { proxy in
            guard let visibleArea = proxy.bounds(of: .scrollView) else { return true }
            return CGRect(origin: .zero, size: proxy.size).intersects(visibleArea)
        } action: { visible in
            radar.setVisible(visible)
        }
        // Coming back after hours in the background: refresh before anyone reads an old "Now".
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { radar.load() }
        }
        // Opening the screen or switching city: fetch the frames if they're missing or stale,
        // wherever the radar is on screen.
        .task(id: tileInfo) {
            radar.load()
            await radar.loadBaseMap(for: tileInfo)
        }
        // Prefetch every frame's overlay once per location and timeline, keyed on those rather than
        // the current frame, so autoplay never cancels a load.
        .task(id: OverlayKey(tile: tileInfo, timeline: timeline)) {
            let tile = tileInfo
            if playbackTile != tile {
                playbackTile = tile
                playing = true
            }
            frameIndex = nowIndex
            await radar.loadOverlays(for: tile)
        }
        .task(id: PlaybackKey(playing: playing, frameCount: frames.count)) {
            guard playing, !frames.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: radar.frameInterval)
                guard !Task.isCancelled, !frames.isEmpty else { return }
                frameIndex = (frameIndex + 1) % frames.count
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch radar.timeline {
        case .success:
            HStack(spacing: 4) {
                Button {
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        // 44pt is Apple's minimum touch target; the icon itself is unchanged.
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(playing ? "Pause radar animation" : "Play radar animation")
                Slider(
                    value: Binding(
                        get: { Double(frameIndex) },
                        set: { value in
                            playing = false
                            frameIndex = min(max(Int(value.rounded()), 0), max(frames.count - 1, 0))
                        }
                    ),
                    in: 0 ... Double(max(frames.count - 1, 1)),
                    step: 1
                )
                .padding(.trailing, 8)
                // VoiceOver reads the frame's time rather than a bare percentage.
                .accessibilityLabel("Radar frame")
                .accessibilityValue(frames.indices.contains(frameIndex)
                    ? frameLabel(frames[frameIndex], isNow: frameIndex == nowIndex)
                    : "")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.brandSurface.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        case .error:
            OverlayChip {
                HStack(spacing: 8) {
                    Text("Radar unavailable")
                        .font(.caption)
                    Button("Retry") { radar.retry() }
                        .font(.caption)
                }
            }
        case .idle, .loading:
            OverlayChip {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading radar…")
                        .font(.caption)
                }
            }
        }
    }

    /// "Now · 7:50 AM" for the latest observed frame, "Forecast · …" for nowcast frames.
    private func frameLabel(_ frame: RadarFrame, isNow: Bool) -> String {
        let time = WeatherFormatting.epochTime(frame.timeEpochSeconds, timeZone: timeZone)
        if isNow { return "Now · \(time)" }
        if frame.isForecast { return "Forecast · \(time)" }
        return time
    }
}

private struct OverlayKey: Equatable {
    let tile: RadarTile
    let timeline: RadarTimeline?
}

private struct PlaybackKey: Equatable {
    let playing: Bool
    let frameCount: Int
}

private struct RadarCanvas: View {
    let tileInfo: RadarTile
    let baseMap: CGImage?
    let overlay: CGImage?

    var body: some View {
        Canvas { context, size in
            let bitmapTotal = CGFloat(3 * RadarTiles.pixelSize)
            let tileDisplay = max(size.width, size.height) / 2
            let scale = tileDisplay / CGFloat(RadarTiles.pixelSize)
            let locationX = (1 + tileInfo.subFractionX) * CGFloat(RadarTiles.pixelSize)
            let locationY = (1 + tileInfo.subFractionY) * CGFloat(RadarTiles.pixelSize)
            let rect = CGRect(
                x: size.width / 2 - locationX * scale,
                y: size.height / 2 - locationY * scale,
                width: bitmapTotal * scale,
                height: bitmapTotal * scale
            )
            if let baseMap {
                context.draw(Image(decorative: baseMap, scale: 1), in: rect)
            }
            if let overlay {
                context.opacity = 0.8
                context.draw(Image(decorative: overlay, scale: 1), in: rect)
            }
        }
    }
}

private struct OverlayChip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.brandSurface.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RadarLegend: View {
    var body: some View {
        VStack(spacing: 2) {
            LinearGradient(colors: radarLegendColors, startPoint: .leading, endPoint: .trailing)
                .frame(width: 96, height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                Text("Light")
                Spacer(minLength: 4)
                Text("Heavy")
            }
            .font(.caption2)
            .lineLimit(1)
            // At least the bar's width; wider when large Dynamic Type sizes need it.
            .frame(minWidth: 96)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.brandSurface.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
    }
}



#Preview {
    RadarCard(
        location: SavedLocation(label: "London", latitude: 51.5074, longitude: -0.1278)
    )
    .padding()
}
