import XCTest
@testable import Cats_Dogs

@MainActor
final class RadarTests: XCTestCase {
    func testParsesHostAndMergesPastThenNowcastInChronologicalOrder() throws {
        let body = """
        {
          "host": "https://tilecache.rainviewer.com",
          "radar": {
            "past": [
              { "time": 100, "path": "/v2/radar/100" },
              { "time": 200, "path": "/v2/radar/200" }
            ],
            "nowcast": [ { "time": 300, "path": "/v2/radar/nowcast_300" } ]
          }
        }
        """

        let timeline = try RadarRepository.parseTimeline(Data(body.utf8))

        XCTAssertEqual(timeline.host, "https://tilecache.rainviewer.com")
        XCTAssertEqual(timeline.frames.map(\.timeEpochSeconds), [100, 200, 300])
        // Past frames are observed; the nowcast frame is a forecast.
        XCTAssertEqual(timeline.frames.map(\.isForecast), [false, false, true])
    }

    /// RainViewer currently returns no nowcast frames at all; past frames alone must still work.
    func testAcceptsAPayloadWithNoNowcast() throws {
        let body = """
        { "host": "https://tilecache.rainviewer.com", "radar": { "past": [ { "time": 100, "path": "/a" } ] } }
        """

        XCTAssertEqual(try RadarRepository.parseTimeline(Data(body.utf8)).frames.count, 1)
    }

    func testBuildsARainViewerTileURLFromHostPathAndTileCoordinates() throws {
        let body = """
        { "host": "https://tilecache.rainviewer.com", "radar": { "past": [ { "time": 100, "path": "/v2/radar/100" } ], "nowcast": [] } }
        """
        let timeline = try RadarRepository.parseTimeline(Data(body.utf8))
        let zoom = RadarTimeline.maxZoom

        let url = timeline.tileURL(for: timeline.frames[0], z: zoom, x: 34, y: 50)

        XCTAssertEqual(url, "https://tilecache.rainviewer.com/v2/radar/100/256/\(zoom)/34/50/4/1_1.png")
    }

    func testThrowsWhenThereAreNoFrames() {
        let body = """
        { "host": "https://tilecache.rainviewer.com", "radar": { "past": [], "nowcast": [] } }
        """

        XCTAssertThrowsError(try RadarRepository.parseTimeline(Data(body.utf8))) { error in
            XCTAssertEqual(error as? RadarError, .empty)
        }
    }

    func testThrowsOnAMalformedPayload() {
        XCTAssertThrowsError(try RadarRepository.parseTimeline(Data("not json".utf8)))
    }

    // MARK: - RadarViewModel

    private let sampleTimeline = RadarTimeline(
        host: "https://example.com",
        frames: [RadarFrame(timeEpochSeconds: 1, path: "/a", isForecast: false)]
    )

    private let laterTimeline = RadarTimeline(
        host: "https://example.com",
        frames: [RadarFrame(timeEpochSeconds: 2, path: "/b", isForecast: false)]
    )

    // MARK: - Radar images

    private func pixel() -> CGImage {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    func testOverlaysLoadNearestNowFirstAndARefreshedTimelineKeepsTheOnesItShares() async {
        let image = pixel()
        let loaded = PathLog()
        let past = RadarTimeline(host: "https://example.com", frames: [
            RadarFrame(timeEpochSeconds: 1, path: "/1", isForecast: false),
            RadarFrame(timeEpochSeconds: 2, path: "/2", isForecast: false),
            RadarFrame(timeEpochSeconds: 3, path: "/3", isForecast: true),
        ])
        let source = TimelineSource([past])
        let viewModel = RadarViewModel(
            fetchTimeline: { try await source.next() },
            loadBaseMap: { _ in image },
            loadOverlay: { _, _, frame in
                await loaded.append(frame.path)
                return image
            }
        )
        let tile = RadarTile.from(latitude: 51.5, longitude: -0.1, zoom: RadarTiles.zoom)
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }

        await viewModel.loadBaseMap(for: tile)
        await viewModel.loadOverlays(for: tile)

        XCTAssertNotNil(viewModel.baseMap)
        XCTAssertEqual(Set(viewModel.overlays.keys), ["/1", "/2", "/3"])
        // Loaded again for the same tile, only what's missing is fetched.
        await viewModel.loadOverlays(for: tile)
        let paths = await loaded.paths
        XCTAssertEqual(paths.count, 3)
    }

    func testPlaybackStartsOnNowAndScrubbingPausesIt() async {
        let timeline = RadarTimeline(host: "https://example.com", frames: [
            RadarFrame(timeEpochSeconds: 0, path: "/1", isForecast: false),
            RadarFrame(timeEpochSeconds: 600, path: "/2", isForecast: false),
            RadarFrame(timeEpochSeconds: 1200, path: "/3", isForecast: true),
        ])
        let viewModel = RadarViewModel(
            frameInterval: .milliseconds(1),
            fetchTimeline: { timeline },
            loadBaseMap: { _ in nil },
            loadOverlay: { _, _, _ in nil }
        )
        let tile = RadarTile.from(latitude: 51.5, longitude: -0.1, zoom: RadarTiles.zoom)
        await viewModel.show(tile)
        await waitUntil { viewModel.timeline.successValue != nil }
        await viewModel.startPlayback(on: tile)

        XCTAssertEqual(viewModel.frameIndex, 1, "The latest observed frame")
        XCTAssertTrue(viewModel.playing)
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertTrue(viewModel.currentFrameLabel(timeZone: utc)?.hasPrefix("Now · ") == true)

        viewModel.scrub(to: 9)
        XCTAssertFalse(viewModel.playing)
        XCTAssertEqual(viewModel.frameIndex, 2, "Kept to the frames there are")
        XCTAssertTrue(viewModel.currentFrameLabel(timeZone: utc)?.hasPrefix("Forecast · ") == true)

        viewModel.togglePlaying()
        let player = Task { await viewModel.play() }
        await waitUntil { viewModel.frameIndex == 0 }
        player.cancel()
    }

    func testANewTileStartsTheOverlaysAndMapFromScratch() async {
        let image = pixel()
        let viewModel = RadarViewModel(
            fetchTimeline: { RadarTimeline(host: "https://example.com", frames: [RadarFrame(timeEpochSeconds: 1, path: "/a", isForecast: false)]) },
            loadBaseMap: { _ in nil },
            loadOverlay: { _, _, _ in image }
        )
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }
        await viewModel.loadOverlays(for: RadarTile.from(latitude: 51.5, longitude: -0.1, zoom: RadarTiles.zoom))
        XCTAssertEqual(viewModel.overlays.count, 1)

        // Somewhere with no overlays loading: the old city's are dropped, not shown over the new map.
        let gate = OverlayGate()
        let failing = RadarViewModel(
            fetchTimeline: { RadarTimeline(host: "https://example.com", frames: [RadarFrame(timeEpochSeconds: 1, path: "/a", isForecast: false)]) },
            loadBaseMap: { _ in nil },
            loadOverlay: { _, _, _ in await gate.isOpen ? image : nil }
        )
        failing.load()
        await waitUntil { failing.timeline.successValue != nil }
        await failing.loadOverlays(for: RadarTile.from(latitude: 51.5, longitude: -0.1, zoom: RadarTiles.zoom))
        XCTAssertEqual(failing.overlays.count, 1)
        await gate.close()
        await failing.loadOverlays(for: RadarTile.from(latitude: 0, longitude: -179.9, zoom: RadarTiles.zoom))
        XCTAssertTrue(failing.overlays.isEmpty)
        XCTAssertNil(failing.baseMap)
    }

    func testLoadsTheTimelineOnceAndIgnoresLaterLoads() async {
        let calls = Counter()
        let timeline = sampleTimeline
        let viewModel = RadarViewModel(fetchTimeline: {
            await calls.increment()
            return timeline
        })

        viewModel.load()
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }
        viewModel.load()
        await settle()

        XCTAssertEqual(viewModel.timeline, .success(sampleTimeline))
        let count = await calls.value
        XCTAssertEqual(count, 1)
    }

    func testAFreshTimelineIsNotFetchedAgain() async {
        let source = TimelineSource([sampleTimeline, laterTimeline])
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let viewModel = RadarViewModel(fetchTimeline: { try await source.next() }, now: { clock })
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }

        clock += RadarViewModel.staleAfter - 1
        viewModel.load()
        await settle()

        XCTAssertEqual(viewModel.timeline, .success(sampleTimeline))
        XCTAssertEqual(source.calls, 1)
    }

    func testAStaleTimelineIsRefreshedWhileTheOldOneStaysOnScreen() async {
        let source = TimelineSource([sampleTimeline, laterTimeline])
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let viewModel = RadarViewModel(fetchTimeline: { try await source.next() }, now: { clock })
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }

        clock += 5 * 3600
        viewModel.load()

        XCTAssertEqual(viewModel.timeline, .success(sampleTimeline), "No loading state while refreshing")
        await waitUntil { viewModel.timeline == .success(self.laterTimeline) }
    }

    func testAFailedRefreshKeepsTheOldTimelineAndTriesAgainLater() async {
        let source = TimelineSource([sampleTimeline, nil, laterTimeline])
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let viewModel = RadarViewModel(fetchTimeline: { try await source.next() }, now: { clock })
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }

        clock += RadarViewModel.staleAfter
        viewModel.load()
        await waitUntil { source.calls == 2 }
        await settle()
        XCTAssertEqual(viewModel.timeline, .success(sampleTimeline))

        viewModel.load()
        await waitUntil { viewModel.timeline == .success(self.laterTimeline) }
    }

    func testTheRecheckLeavesAStaleRadarAloneWhileItIsOutOfView() async {
        let source = TimelineSource([sampleTimeline, laterTimeline])
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let viewModel = RadarViewModel(fetchTimeline: { try await source.next() }, now: { clock })
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }
        viewModel.setVisible(false)

        clock += RadarViewModel.staleAfter
        viewModel.recheck()
        await settle()

        XCTAssertEqual(viewModel.timeline, .success(sampleTimeline))
        XCTAssertEqual(source.calls, 1)
    }

    func testTheRecheckRefreshesAStaleRadarInView() async {
        let source = TimelineSource([sampleTimeline, laterTimeline])
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let viewModel = RadarViewModel(fetchTimeline: { try await source.next() }, now: { clock })
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }
        viewModel.setVisible(true)
        await settle()
        XCTAssertEqual(source.calls, 1, "Fresh frames aren't fetched again on coming into view")

        clock += RadarViewModel.staleAfter
        viewModel.recheck()

        await waitUntil { viewModel.timeline == .success(self.laterTimeline) }
        XCTAssertEqual(source.calls, 2)
    }

    func testScrollingAStaleRadarIntoViewRefreshesItStraightAway() async {
        let source = TimelineSource([sampleTimeline, laterTimeline])
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let viewModel = RadarViewModel(fetchTimeline: { try await source.next() }, now: { clock })
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }
        viewModel.setVisible(false)

        clock += RadarViewModel.staleAfter
        viewModel.setVisible(true)

        await waitUntil { viewModel.timeline == .success(self.laterTimeline) }
        XCTAssertEqual(source.calls, 2)
    }

    func testTheRecheckRetriesAFailedLoadOnlyWhileInView() async {
        let source = TimelineSource([nil, sampleTimeline])
        let viewModel = RadarViewModel(fetchTimeline: { try await source.next() })
        viewModel.load()
        await waitUntil { viewModel.timeline != .loading }
        XCTAssertEqual(viewModel.timeline, .error(errorKey: "radar_unavailable", canRetry: true))

        viewModel.recheck()
        await settle()
        XCTAssertEqual(source.calls, 1)

        viewModel.setVisible(true)
        await waitUntil { viewModel.timeline == .success(self.sampleTimeline) }
        XCTAssertEqual(source.calls, 2)
    }

    func testAFailedLoadShowsARetryableErrorAndRetryRecovers() async {
        let shouldFail = Flag(true)
        let timeline = sampleTimeline
        let viewModel = RadarViewModel(fetchTimeline: {
            if await shouldFail.value { throw RadarError.network }
            return timeline
        })

        viewModel.load()
        await waitUntil { viewModel.timeline != .loading }
        XCTAssertEqual(viewModel.timeline, .error(errorKey: "radar_unavailable", canRetry: true))

        await shouldFail.set(false)
        viewModel.retry()
        await waitUntil { viewModel.timeline.successValue != nil }
    }

    // MARK: - Coverage

    func testBuildsARainViewerCoverageURLFromHostAndTileCoordinates() {
        let timeline = RadarTimeline(host: "https://tilecache.rainviewer.com", frames: sampleTimeline.frames)

        XCTAssertEqual(
            timeline.coverageURL(z: 7, x: 63, y: 42),
            "https://tilecache.rainviewer.com/v2/coverage/0/256/7/63/42/0/0_0.png"
        )
    }

    func testOnlyAFullyTransparentCoveragePixelHasRadar() {
        XCTAssertTrue(RadarCoverage.isCovered(alpha: 0))
        XCTAssertFalse(RadarCoverage.isCovered(alpha: 1))
        XCTAssertFalse(RadarCoverage.isCovered(alpha: 255))
    }

    func testTheCityPixelIsWhereTheCardCentresInTheMiddleTile() {
        let tile = RadarTile(tileX: 63, tileY: 42, subFractionX: 0.25, subFractionY: 0.5)

        XCTAssertEqual(RadarCoverage.cityPixel(for: tile).x, 320)
        XCTAssertEqual(RadarCoverage.cityPixel(for: tile).y, 384)
        let corner = RadarTile(tileX: 0, tileY: 0, subFractionX: 0.999999, subFractionY: 0.999999)
        XCTAssertEqual(RadarCoverage.cityPixel(for: corner).x, 511)
    }

    func testReadsTheCoverageAtTheCitysPixelCountedFromTheTop() {
        // Black (no radar) over the top half and the left half; transparent in the bottom right.
        let coverage = stitchedCoverage(black: [
            CGRect(x: 0, y: 0, width: 768, height: 384),
            CGRect(x: 0, y: 0, width: 384, height: 768),
        ])

        XCTAssertFalse(RadarCoverage.isCovered(coverage, at: tile(x: 0.8, y: 0.2)))
        XCTAssertFalse(RadarCoverage.isCovered(coverage, at: tile(x: 0.2, y: 0.8)))
        XCTAssertTrue(RadarCoverage.isCovered(coverage, at: tile(x: 0.8, y: 0.8)))
        XCTAssertTrue(RadarCoverage.isCovered(stitchedCoverage(black: []), at: tile(x: 0.5, y: 0.5)))
    }

    func testACityOutsideTheCoverageSaysNoRadarHere() async {
        let black = stitchedCoverage(black: [CGRect(x: 0, y: 0, width: 768, height: 768)])
        let viewModel = RadarViewModel(
            fetchTimeline: { RadarTimeline(host: "https://example.com", frames: [RadarFrame(timeEpochSeconds: 1, path: "/a", isForecast: false)]) },
            loadCoverage: { _, _ in black }
        )
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }

        await viewModel.loadCoverage(for: tile(x: 0.5, y: 0.5))

        XCTAssertNotNil(viewModel.coverage)
        XCTAssertTrue(viewModel.noRadarHere)
    }

    func testACityInsideTheCoverageHasNoLabelAndANewCityStartsAgain() async {
        let clear = stitchedCoverage(black: [])
        let black = stitchedCoverage(black: [CGRect(x: 0, y: 0, width: 768, height: 768)])
        let nairobi = RadarTile.from(latitude: -1.29, longitude: 36.82, zoom: RadarTiles.zoom)
        let calls = Counter()
        let viewModel = RadarViewModel(
            fetchTimeline: { RadarTimeline(host: "https://example.com", frames: [RadarFrame(timeEpochSeconds: 1, path: "/a", isForecast: false)]) },
            loadCoverage: { tile, _ in
                await calls.increment()
                return tile == nairobi ? black : clear
            }
        )
        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }

        let london = RadarTile.from(latitude: 51.5, longitude: -0.1, zoom: RadarTiles.zoom)
        await viewModel.loadCoverage(for: london)
        XCTAssertNotNil(viewModel.coverage)
        XCTAssertFalse(viewModel.noRadarHere)
        // Once per city: the same city again doesn't fetch it again.
        await viewModel.loadCoverage(for: london)
        let afterLondon = await calls.value
        XCTAssertEqual(afterLondon, 1)

        await viewModel.loadCoverage(for: nairobi)
        XCTAssertTrue(viewModel.noRadarHere)
    }

    func testCoverageThatFailsToLoadLeavesTheCardAsBefore() async {
        let black = stitchedCoverage(black: [CGRect(x: 0, y: 0, width: 768, height: 768)])
        let gate = OverlayGate()
        let viewModel = RadarViewModel(
            fetchTimeline: { RadarTimeline(host: "https://example.com", frames: [RadarFrame(timeEpochSeconds: 1, path: "/a", isForecast: false)]) },
            loadCoverage: { _, _ in await gate.isOpen ? black : nil }
        )
        // Before the timeline (and its tile host) arrives there's nothing to load.
        await viewModel.loadCoverage(for: tile(x: 0.5, y: 0.5))
        XCTAssertNil(viewModel.coverage)

        viewModel.load()
        await waitUntil { viewModel.timeline.successValue != nil }
        await viewModel.loadCoverage(for: tile(x: 0.5, y: 0.5))
        XCTAssertTrue(viewModel.noRadarHere)

        // Somewhere else, with the coverage failing: no dimming and no label, not the old city's.
        await gate.close()
        await viewModel.loadCoverage(for: RadarTile.from(latitude: 0, longitude: -179.9, zoom: RadarTiles.zoom))
        XCTAssertNil(viewModel.coverage)
        XCTAssertFalse(viewModel.noRadarHere)
    }

    private func tile(x: Double, y: Double) -> RadarTile {
        RadarTile(tileX: 63, tileY: 42, subFractionX: x, subFractionY: y)
    }

    /// A stitched 3 by 3 coverage image, transparent but for opaque black `black` rects, given in
    /// pixels from the top-left corner like the image itself.
    private func stitchedCoverage(black: [CGRect]) -> CGImage {
        let size = 3 * RadarTiles.pixelSize
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for rect in black {
            // CGContext counts from the bottom.
            context.fill(CGRect(x: rect.minX, y: CGFloat(size) - rect.maxY, width: rect.width, height: rect.height))
        }
        return context.makeImage()!
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor Flag {
    private(set) var value: Bool
    init(_ value: Bool) { self.value = value }
    func set(_ newValue: Bool) { value = newValue }
}

/// Serves timelines in order; nil throws, as a network failure would.
@MainActor
private final class TimelineSource {
    private var queue: [RadarTimeline?]
    private(set) var calls = 0

    init(_ queue: [RadarTimeline?]) { self.queue = queue }

    func next() throws -> RadarTimeline {
        calls += 1
        guard !queue.isEmpty, let timeline = queue.removeFirst() else { throw RadarError.network }
        return timeline
    }
}

/// The overlay paths a test radar was asked for, in order.
private actor PathLog {
    private(set) var paths: [String] = []
    func append(_ path: String) { paths.append(path) }
}

/// Lets a test radar's overlays load until it's closed.
private actor OverlayGate {
    private(set) var isOpen = true
    func close() { isOpen = false }
}
