import Foundation
import Observation

/// Where the phone is, for My Location. `LocationPermissionViewModel` provides it; tests fake it.
@MainActor
protocol DevicePositioning: AnyObject {
    func hasLocationPermission() -> Bool
    /// The phone's position now, waited for; nil without permission, during another fetch, or
    /// without a fix.
    func currentPosition() async -> SavedLocation?
}

extension LocationPermissionViewModel: DevicePositioning {}

/// What the weather screen does, and in what order: refreshing the city on screen when it changes,
/// on returning to the app and every half hour; moving My Location to where the phone is (or adding
/// it once location access turns up); and refreshing the notification city when that changes. The
/// view only tells it what happened. Same steps as Android's `CurrentWeatherViewModel`.
@MainActor
@Observable
final class CurrentWeatherViewModel {
    let cityList: CityListViewModel
    let weather: WeatherForecastViewModel

    /// The quiet refresh while the app stays open, so a screen left on overnight keeps up.
    static let autoRefreshInterval: Duration = .seconds(30 * 60)

    private let position: any DevicePositioning
    private let follower: MyLocationFollower
    private let refreshNotificationCity: @MainActor () async -> Void
    private let sleep: (Duration) async throws -> Void
    /// Location access at the last check, to spot it being granted later in the Settings app.
    private var locationWasGranted: Bool?
    /// A position is being read, so another check doesn't start one too.
    private var locating = false

    init(
        cityList: CityListViewModel,
        weather: WeatherForecastViewModel,
        position: (any DevicePositioning)? = nil,
        follower: MyLocationFollower? = nil,
        refreshNotificationCity: (@MainActor () async -> Void)? = nil,
        sleep: ((Duration) async throws -> Void)? = nil
    ) {
        self.cityList = cityList
        self.weather = weather
        self.position = position ?? LocationPermissionViewModel()
        self.follower = follower ?? .shared
        self.refreshNotificationCity = refreshNotificationCity ?? {
            await WeatherBackgroundRefresher.shared.performRefresh(replan: true)
        }
        self.sleep = sleep ?? { try await Task.sleep(for: $0) }
    }

    /// Follow my location's moves of My Location in storage, for the view to pass on with
    /// `myLocationMoved()`.
    var myLocationMoves: Int { follower.moves }

    // MARK: - What happened on screen

    /// The screen first shows.
    func appeared() {
        refreshActiveCity()
        updateMyLocation()
    }

    /// The app comes back to the foreground: the clock moves on, the city on screen is quietly
    /// refreshed, My Location follows the phone, and cities added by name get their coordinates.
    func becameActive() {
        weather.tick()
        quietlyRefreshActiveCity()
        updateMyLocation()
        cityList.fillInMissingCoordinates()
    }

    /// Another city is on screen, or the units changed (the cache is in the old ones): a real refetch.
    func activeCityChanged() {
        refreshActiveCity()
    }

    func unitsChanged() {
        refreshActiveCity()
    }

    /// The retry buttons.
    func retry() {
        refreshActiveCity()
    }

    /// Notifications are for My Location, otherwise the first city, whichever tab is showing. When
    /// that changes (reordered, added, removed, or My Location moved), its weather may not be cached
    /// yet: it's fetched, then the notifications are replanned.
    func notificationCityChanged() async {
        await refreshNotificationCity()
    }

    /// Follow my location moved My Location in storage while the app is open: the screen takes the
    /// move up, and the new place's weather comes with the active city changing.
    func myLocationMoved() {
        cityList.followStoredMyLocation()
    }

    /// Pull to refresh. On My Location the phone's position is read first, whatever the 15-minute
    /// limit, so My Location moves (by the usual 1 km rule) before its weather is fetched: a drive
    /// with the screen on never returns to the app, so this is how to catch up by hand. Returns once
    /// the fetch is done, so the spinner stays up until then.
    func pulledToRefresh() async {
        if cityList.activeLocation?.isCurrentLocation == true, let here = await position.currentPosition() {
            cityList.noteMyLocationChecked()
            cityList.updateCurrentLocation(here)
        }
        // At once, after a move too, so the spinner waits on a fetch already under way.
        refreshActiveCity()
        await waitForRefresh()
    }

    // MARK: - While the screen is up

    /// The quiet refresh every half hour, run by the view while the app is active, until cancelled.
    func refreshWhileActive() async {
        while (try? await sleep(Self.autoRefreshInterval)) != nil, !Task.isCancelled {
            weather.tick()
            quietlyRefreshActiveCity()
        }
    }

    /// While refreshes keep failing, the clock is re-read every few minutes so old weather gives way
    /// to the forecast once it passes the cutoff. Run by the view while there's an error, until
    /// cancelled.
    func recheckWhileStale() async {
        guard weather.staleErrorKey != nil else { return }
        while (try? await sleep(StaleWeather.recheckInterval)) != nil, !Task.isCancelled {
            weather.tick()
        }
    }

    // MARK: - Steps

    private func refreshActiveCity() {
        // A refresh also moves "now" on, so the hourly strip and captions update even when the
        // weather itself hasn't changed.
        weather.tick()
        guard let location = cityList.activeLocation else { return }
        weather.refreshCurrent(location: location)
        weather.refreshForecast(location: location)
    }

    private func quietlyRefreshActiveCity() {
        guard let location = cityList.activeLocation else { return }
        weather.backgroundRefreshCurrent(location: location)
        weather.backgroundRefreshForecast(location: location)
    }

    /// On first showing and each return to the app, with location access on:
    /// - re-reads the position while My Location is saved (at most every 15 minutes), so it follows
    ///   the device rather than staying where it was added;
    /// - otherwise adds it once access turns up after onboarding went without it (granted later in
    ///   the Settings app, say). Only when there are no cities yet, or access has just changed to
    ///   granted, so someone who removed My Location on purpose doesn't get it back every launch.
    private func updateMyLocation() {
        let granted = position.hasLocationPermission()
        let newlyGranted = granted && locationWasGranted == false
        locationWasGranted = granted
        guard granted, !locating else { return }
        let adding: Bool
        if cityList.locations.contains(where: \.isCurrentLocation) {
            guard cityList.claimMyLocationCheck() else { return }
            adding = false
        } else if newlyGranted || cityList.locations.isEmpty {
            adding = true
        } else {
            return
        }
        locating = true
        Task {
            defer { locating = false }
            guard let here = await position.currentPosition() else { return }
            if cityList.locations.contains(where: \.isCurrentLocation) {
                cityList.updateCurrentLocation(here)
            } else if adding {
                // A position read only to move My Location, arriving after it was removed, adds nothing.
                cityList.addLocation(here)
            }
        }
    }

    private func waitForRefresh() async {
        while weather.isRefreshing, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
