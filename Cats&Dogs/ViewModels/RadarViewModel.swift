import Foundation
import Observation

/// Holds the RainViewer radar timeline. The frame list is global (not per city), so one shared
/// instance holds it. `load()` fetches it the first time and again once it's stale, so an app that
/// sat in the background for hours doesn't replay old frames labelled "Now". While the screen stays
/// open, frames are only kept current while the radar is in view, so a radar scrolled out of sight
/// doesn't keep fetching frames nobody watches.
@MainActor
@Observable
final class RadarViewModel {
    static let shared = RadarViewModel()

    /// Delay between animation frames, from Remote Config (default 850 ms).
    let frameInterval: Duration

    /// RainViewer publishes a new frame every 10 minutes, and keeps only about two hours of them.
    nonisolated static let staleAfter: TimeInterval = 10 * 60
    /// How often the radar card checks for staleness while the screen is open.
    nonisolated static let recheckInterval: Duration = .seconds(60)

    private(set) var timeline: LoadingState<RadarTimeline> = .idle

    private let fetchTimeline: @Sendable () async throws -> RadarTimeline
    private let now: () -> Date
    private var loadedAt: Date?
    private var isRefreshing = false
    /// Whether any of the radar is inside the visible part of the screen.
    @ObservationIgnored private var isVisible = false

    init(
        frameInterval: Duration? = nil,
        fetchTimeline: (@Sendable () async throws -> RadarTimeline)? = nil,
        now: (() -> Date)? = nil
    ) {
        self.frameInterval = frameInterval ?? RemoteConfigRepository.shared.radarFrameInterval
        self.fetchTimeline = fetchTimeline ?? { try await RadarRepository().timeline() }
        self.now = now ?? { Date() }
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
}
