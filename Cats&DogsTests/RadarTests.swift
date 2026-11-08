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
