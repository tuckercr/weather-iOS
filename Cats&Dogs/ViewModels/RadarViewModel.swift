import CoreGraphics
import Foundation
import Observation

/// Holds the RainViewer radar timeline. The frame list is global (not per city), so one instance,
/// owned by `RootView` and handed down in the environment, holds it. `load()` fetches it the first time and again once it's stale, so an app that
/// sat in the background for hours doesn't replay old frames labelled "Now". While the screen stays
/// open, frames are only kept current while the radar is in view, so a radar scrolled out of sight
/// doesn't keep fetching frames nobody watches. It also holds the images for the city on screen:
/// the map behind the radar, RainViewer's coverage layer and each frame's overlay, loaded through
/// `RadarTileLoader`.
@MainActor
@Observable
final class RadarViewModel {
    /// Delay between animation frames, from Remote Config (default 850 ms), read when it's used so
    /// a value fetched after launch counts.
    var frameInterval: Duration { readFrameInterval() }

    /// RainViewer publishes a new frame every 10 minutes, and keeps only about two hours of them.
    nonisolated static let staleAfter: TimeInterval = 10 * 60
    /// How often the radar card checks for staleness while the screen is open.
    nonisolated static let recheckInterval: Duration = .seconds(60)

    private(set) var timeline: LoadingState<RadarTimeline> = .idle
    /// The OpenStreetMap tiles around the city on screen; nil until they load.
    private(set) var baseMap: CGImage?
    /// Each frame's stitched overlay by frame path, kept so replays are smooth.
    private(set) var overlays: [String: CGImage] = [:]
    /// RainViewer's coverage layer around the city on screen, opaque black where there's no radar;
    /// nil until it loads, and when it doesn't, so the card then looks as it did without it.
    private(set) var coverage: CGImage?
    /// The city on screen is outside RainViewer's radar coverage: the card says "No radar here".
    /// False until the coverage layer has loaded and says so.
    private(set) var noRadarHere = false

    private let readFrameInterval: () -> Duration
    private let fetchTimeline: @Sendable () async throws -> RadarTimeline
    private let loadBaseMap: @Sendable (RadarTile) async -> CGImage?
    private let loadOverlay: @Sendable (RadarTile, RadarTimeline, RadarFrame) async -> CGImage?
    private let loadCoverage: @Sendable (RadarTile, RadarTimeline) async -> CGImage?
    @ObservationIgnored private var baseMapTile: RadarTile?
    @ObservationIgnored private var coverageKey: CoverageKey?
    @ObservationIgnored private var overlaysTile: RadarTile?
    private let now: () -> Date
    private var loadedAt: Date?
    private var isRefreshing = false
    /// Whether any of the radar is inside the visible part of the screen.
    @ObservationIgnored private var isVisible = false

    init(
        frameInterval: Duration? = nil,
        fetchTimeline: (@Sendable () async throws -> RadarTimeline)? = nil,
        loadBaseMap: (@Sendable (RadarTile) async -> CGImage?)? = nil,
        loadOverlay: (@Sendable (RadarTile, RadarTimeline, RadarFrame) async -> CGImage?)? = nil,
        loadCoverage: (@Sendable (RadarTile, RadarTimeline) async -> CGImage?)? = nil,
        now: (() -> Date)? = nil
    ) {
        self.readFrameInterval = frameInterval.map { interval in { interval } }
            ?? { RemoteConfigRepository.shared.radarFrameInterval }
        self.fetchTimeline = fetchTimeline ?? { try await RadarRepository().timeline() }
        self.loadBaseMap = loadBaseMap ?? { await RadarTileLoader.baseMap(for: $0) }
        self.loadOverlay = loadOverlay ?? { await RadarTileLoader.overlay(for: $2, in: $1, tile: $0) }
        self.loadCoverage = loadCoverage ?? { await RadarTileLoader.coverage(in: $1, tile: $0) }
        self.now = now ?? { Date() }
    }

    /// Loads the map behind the radar for `tile`. A new tile clears the old map first.
    func loadBaseMap(for tile: RadarTile) async {
        if baseMapTile != tile { baseMap = nil }
        baseMapTile = tile
        let image = await loadBaseMap(tile)
        guard !Task.isCancelled, baseMapTile == tile else { return }
        baseMap = image
    }

    /// Loads RainViewer's coverage layer for `tile`, once per city (and tile host), and decides
    /// whether the city has radar. A new tile clears the old layer first. A failed load leaves no
    /// layer and no "No radar here", as before there was one, and the next call tries again.
    func loadCoverage(for tile: RadarTile) async {
        guard let timeline = timeline.successValue else { return }
        let key = CoverageKey(tile: tile, host: timeline.host)
        if coverageKey == key, coverage != nil { return }
        if coverageKey?.tile != tile {
            coverage = nil
            noRadarHere = false
        }
        coverageKey = key
        guard let image = await loadCoverage(tile, timeline),
              !Task.isCancelled, coverageKey == key else { return }
        coverage = image
        noRadarHere = !RadarCoverage.isCovered(image, at: tile)
    }

    /// Prefetches every frame's overlay for `tile` and the current timeline, frames nearest "now"
    /// first, a few at a time. A new tile starts from scratch; a refreshed timeline keeps the
    /// overlays it shares with the old one and drops the rest.
    func loadOverlays(for tile: RadarTile) async {
        guard let timeline = timeline.successValue else { return }
        if overlaysTile != tile {
            overlays = [:]
            overlaysTile = tile
        } else {
            let paths = Set(timeline.frames.map(\.path))
            overlays = overlays.filter { paths.contains($0.key) }
        }
        let now = timeline.frames.lastIndex { !$0.isForecast } ?? 0
        let order = timeline.frames.indices
            .sorted { abs($0 - now) < abs($1 - now) }
            .map { timeline.frames[$0] }
            .filter { overlays[$0.path] == nil }
        let load = loadOverlay
        await withTaskGroup(of: (path: String, image: CGImage?).self) { group in
            var pending = order.makeIterator()
            func startNext() {
                guard let frame = pending.next() else { return }
                group.addTask { (frame.path, await load(tile, timeline, frame)) }
            }
            for _ in 0 ..< RadarTiles.concurrentFrames { startNext() }
            for await result in group {
                guard !Task.isCancelled, overlaysTile == tile else { return }
                if let image = result.image { overlays[result.path] = image }
                startNext()
            }
        }
    }

    /// Fetches the timeline the first time, and refreshes it once it's stale. Safe to call often:
    /// it does nothing while a fetch is in flight or the timeline is fresh.
    func load() {
        switch timeline {
        case .loading:
            return
        case .success:
            guard !isRefreshing, let loadedAt, now().timeIntervalSince(loadedAt) >= Self.staleAfter else { return }
            refresh()
            return
        case .idle, .error:
            break
        }
        timeline = .loading
        Task {
            do {
                timeline = .success(try await fetchTimeline())
                loadedAt = now()
            } catch {
                timeline = .error(errorKey: "radar_unavailable", canRetry: true)
            }
        }
    }

    /// Called as the radar scrolls into and out of view. Coming into view refreshes stale frames
    /// straight away rather than waiting for the next re-check.
    func setVisible(_ visible: Bool) {
        let cameIntoView = visible && !isVisible
        isVisible = visible
        if cameIntoView { load() }
    }

    /// The timed re-check while the screen is open: refreshes stale frames, or retries a failed
    /// load, only while the radar is in view.
    func recheck() {
        if isVisible { load() }
    }

    /// Keeps the old frames on screen until the new ones arrive. A failed refresh keeps them too;
    /// the next resume or recheck tries again.
    private func refresh() {
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            guard let fresh = try? await fetchTimeline() else { return }
            timeline = .success(fresh)
            loadedAt = now()
        }
    }

    func retry() {
        timeline = .idle
        load()
    }

    // MARK: - Playback

    /// The frame on screen.
    private(set) var frameIndex = 0
    /// Playing through the frames; scrubbing pauses it.
    private(set) var playing = true
    /// The tile playback last started on, so a new location starts playing again.
    @ObservationIgnored private var playbackTile: RadarTile?

    var frames: [RadarFrame] { timeline.successValue?.frames ?? [] }

    /// The most recent observed frame: "now".
    var nowIndex: Int { frames.lastIndex { !$0.isForecast } ?? 0 }

    /// The overlay for the frame on screen, once it has loaded.
    var currentOverlay: CGImage? {
        frames.indices.contains(frameIndex) ? overlays[frames[frameIndex].path] : nil
    }

    /// "Now · 7:50 AM" for the latest observed frame, "Forecast · …" for nowcast frames, on the
    /// city's clock; nil before there are frames.
    func currentFrameLabel(timeZone: TimeZone) -> String? {
        guard frames.indices.contains(frameIndex) else { return nil }
        let frame = frames[frameIndex]
        let time = WeatherFormatting.epochTime(frame.timeEpochSeconds, timeZone: timeZone)
        if frameIndex == nowIndex { return String(localized: "Now · \(time)", comment: "Radar frame label. The argument is a time.") }
        if frame.isForecast { return String(localized: "Forecast · \(time)", comment: "Radar frame label. The argument is a time.") }
        return time
    }

    /// What the coverage layer was loaded for: a city, and the tile host from the timeline.
    struct CoverageKey: Hashable {
        let tile: RadarTile
        let host: String
    }

    /// The radar card shows `tile` (the city on screen): the frames if they're missing or stale,
    /// and the map behind them.
    func show(_ tile: RadarTile) async {
        load()
        await loadBaseMap(for: tile)
    }

    /// The frames for `tile` and the current timeline: playback starts again on "now" (and starts
    /// playing for a new location), and every frame's overlay is prefetched.
    func startPlayback(on tile: RadarTile) async {
        if playbackTile != tile {
            playbackTile = tile
            playing = true
        }
        frameIndex = nowIndex
        await loadOverlays(for: tile)
    }

    /// Steps through the frames while playing, until cancelled or paused.
    func play() async {
        guard playing, !frames.isEmpty else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: frameInterval)
            guard !Task.isCancelled, playing, !frames.isEmpty else { return }
            frameIndex = (frameIndex + 1) % frames.count
        }
    }

    func togglePlaying() {
        playing.toggle()
    }

    /// The slider: shows that frame, and pauses.
    func scrub(to index: Int) {
        playing = false
        frameIndex = min(max(index, 0), max(frames.count - 1, 0))
    }

    /// While the screen stays open, keeps the frames current, only while the radar is in view.
    /// Until cancelled.
    func keepCurrent() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.recheckInterval)
            guard !Task.isCancelled else { return }
            recheck()
        }
    }
}
