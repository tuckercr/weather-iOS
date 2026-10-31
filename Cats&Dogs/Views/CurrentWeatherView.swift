import SwiftUI

struct CurrentWeatherView: View {
    @Bindable var cityListViewModel: CityListViewModel
    @Bindable var geoViewModel: GeoLocationViewModel
    @Bindable var weatherViewModel: WeatherForecastViewModel
    /// Read here rather than passed in as values: if RootView read them, every change would rebuild
    /// the navigation stack, Settings screen included, under the user's finger.
    let settingsViewModel: SettingsViewModel
    let onOpenSettings: () -> Void

    private var unitOverride: UnitOverride { settingsViewModel.unitOverride }
    /// The user's Settings choice; Remote Config can also hide the card for everyone.
    private var showWalkCard: Bool { settingsViewModel.showWalkCard }

    @Environment(\.scenePhase) private var scenePhase
    @State private var showAddSheet = false
    @State private var selectedDay: DayForecast?
    @State private var rescheduleTask: Task<Void, Never>?
    /// "Now" for the hourly strip, walk advice, captions and moon. Moved on when the app becomes
    /// active and every half hour while it stays open, so a screen left on overnight keeps up.
    @State private var now = Date()
    @State private var airQualityViewModel = AirQualityViewModel()
    @State private var locationViewModel = LocationPermissionViewModel()
    /// Location access at the last check, to spot it being granted later in the Settings app.
    @State private var locationWasGranted: Bool?
    /// Whether the fetch under way is to add My Location, rather than to move a saved one.
    @State private var fetchingMyLocationToAdd = false

    private static let autoRefreshInterval: Duration = .seconds(30 * 60)

    private var forecastDays: [DayForecast] {
        if case .success(let days) = weatherViewModel.forecast { return days }
        return []
    }

    var body: some View {
        Group {
            if cityListViewModel.locations.isEmpty {
                emptyState
            } else {
                weatherContent
            }
        }
        .background(Color.brandSurface)
        .navigationTitle(navigationTitle)
        // A single-line bar with the city tabs fixed beneath it, like Android's top app bar. A large
        // title under the tabs' inset is drawn blurred behind the scroll edge effect.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add a city")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Open settings")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if cityListViewModel.locations.count >= 2 {
                cityTabs
            }
        }
        .onChange(of: cityListViewModel.activeLocation?.cacheKey) { _, _ in
            refreshActiveLocation()
            // Also covers removing the last city, which must clear its notifications.
            rescheduleNotificationsSoon()
        }
        // Notifications are for My Location, otherwise the first city, whichever tab is showing. When
        // that changes (reordered, added, removed, or My Location moved), its weather may not be
        // cached yet: fetch it, then replan.
        .onChange(of: cityListViewModel.locations.notificationLocation?.cacheKey) { _, _ in
            Task { await WeatherBackgroundRefresher.shared.performRefresh(replan: true) }
        }
        .onChange(of: unitOverride) { _, _ in
            // Cached data is in the old units, so this has to be a real refetch.
            refreshActiveLocation()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date()
                backgroundRefreshActiveLocation()
                updateMyLocation()
                cityListViewModel.fillInMissingCoordinates()
            }
        }
        // The same quiet refresh every half hour while the app stays in the foreground. Restarted
        // (and so only running) while the scene is active.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.autoRefreshInterval)
                guard !Task.isCancelled else { return }
                now = Date()
                backgroundRefreshActiveLocation()
            }
        }
        // While refreshes keep failing, re-read the clock every few minutes so old weather gives way
        // to the forecast once it passes the cutoff.
        .task(id: weatherViewModel.staleErrorKey) {
            guard weatherViewModel.staleErrorKey != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: StaleWeather.recheckInterval)
                guard !Task.isCancelled else { return }
                now = Date()
            }
        }
        .onChange(of: weatherViewModel.currentWeather) { _, state in
            if case .success = state { rescheduleNotificationsSoon() }
        }
        .onChange(of: weatherViewModel.forecast) { _, state in
            if case .success = state { rescheduleNotificationsSoon() }
        }
        .task {
            refreshActiveLocation()
            updateMyLocation()
        }
        .onChange(of: locationViewModel.state) { _, state in
            guard case .located(let location) = state else { return }
            if cityListViewModel.locations.contains(where: \.isCurrentLocation) {
                cityListViewModel.updateCurrentLocation(location)
            } else if fetchingMyLocationToAdd {
                // A position read only to move My Location, arriving after it was removed, adds nothing.
                cityListViewModel.addLocation(location)
            }
            fetchingMyLocationToAdd = false
        }
        .sheet(isPresented: $showAddSheet) {
            AddCitySheet(
                savedLocations: cityListViewModel.locations,
                geoViewModel: geoViewModel,
                onAddCity: addCityFromSheet,
                onRemoveSaved: { index in
                    cityListViewModel.removeLocation(at: index)
                },
                onAddMyLocation: { cityListViewModel.addLocation($0) },
                onDismiss: {
                    geoViewModel.reset()
                    showAddSheet = false
                }
            )
        }
        .sheet(item: $selectedDay) { day in
            DayDetailSheet(day: day)
                .environment(\.southernHemisphere, isSouthernHemisphere)
        }
        // The moon (hero scene and night icons) is lit from the other side down south.
        .environment(\.southernHemisphere, isSouthernHemisphere)
        .environment(\.distanceInMiles, WeatherFormatting.usesMiles(override: unitOverride))
    }

    private var isSouthernHemisphere: Bool {
        (cityListViewModel.activeLocation?.latitude ?? 0) < 0
    }

    private var navigationTitle: String {
        cityListViewModel.activeLocation?.label ?? "Sunny & Misty"
    }

    private var cityTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(cityListViewModel.locations.enumerated()), id: \.offset) { index, location in
                    Button {
                        cityListViewModel.setActiveIndex(index)
                    } label: {
                        HStack(spacing: 4) {
                            if location.isCurrentLocation {
                                Image(systemName: "location.fill")
                                    .font(.caption2)
                            }
                            Text(location.label)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            index == cityListViewModel.activeIndex
                                ? Color.accent.opacity(0.2)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                        // 6pt above and below the capsule makes a 44pt touch target without
                        // changing the layout (the row's vertical padding shrinks to match).
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(index == cityListViewModel.activeIndex ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .background(Color.brandSurface)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accent.opacity(0.4))
            Text("No cities added yet")
                .font(.brand(.title2))
                .multilineTextAlignment(.center)
            Text("Tap the + button to add your first city and get started.")
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                showAddSheet = true
            } label: {
                Label("Add city", systemImage: "plus")
            }
            .accentButtonStyle()
        }
        .padding(32)
        // Fills the screen, so the background behind it does too rather than boxing the message.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var weatherContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch weatherViewModel.currentWeather {
                case .idle, .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 48)
                        Spacer()
                    }

                case .success(let cached):
                    // Past the cutoff the old reading isn't shown as "now": the cached forecast's
                    // current hour stands in, or the error if it doesn't cover now.
                    let staleErrorKey = weatherViewModel.staleErrorKey
                    let tooOld = staleErrorKey != nil && StaleWeather.isTooOldToShowAsNow(cached, now: now)
                    let forecastNow: CurrentWeather? = tooOld ? weatherViewModel.forecast.successValue.flatMap {
                        StaleWeather.forecastAsCurrent(cached, forecast: $0, now: now)
                    } : nil
                    if tooOld && forecastNow == nil {
                        WeatherErrorStateView(
                            errorKey: staleErrorKey ?? "generic",
                            canRetry: true,
                            onRetry: refreshActiveLocation,
                            lastUpdated: StaleWeather.readingTime(cached, now: now)
                        )
                    } else {
                    if let staleErrorKey {
                        StaleWeatherBanner(
                            weather: cached,
                            errorKey: staleErrorKey,
                            showingForecast: forecastNow != nil,
                            now: now
                        )
                    }
                    CurrentWeatherContent(
                        weather: forecastNow ?? cached,
                        showingForecast: forecastNow != nil,
                        forecastState: weatherViewModel.forecast,
                        location: cityListViewModel.activeLocation,
                        showWalkCard: showWalkCard,
                        airQuality: airQualityViewModel.reading(for: cityListViewModel.activeLocation),
                        now: now,
                        onDaySelected: { selectedDay = $0 },
                        onForecastRetry: refreshActiveLocation
                    )
                    }

                case .error(let errorKey, let canRetry):
                    WeatherErrorStateView(errorKey: errorKey, canRetry: canRetry, onRetry: refreshActiveLocation)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable {
            refreshActiveLocation()
            // Keep the pull spinner up until the fetch has finished, rather than dropping it at once.
            while weatherViewModel.isRefreshing {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .overlay(alignment: .top) {
            if weatherViewModel.isRefreshing {
                ProgressView()
                    .padding(.top, 8)
            }
        }
    }

    /// On launch and each return to the app, with location access on:
    /// - re-reads the position while My Location is saved, so it follows the device rather than
    ///   staying where it was added;
    /// - otherwise adds it once access turns up after onboarding went without it (granted later in
    ///   the Settings app, say). Only when there are no cities yet, or access has just changed to
    ///   granted, so someone who removed My Location on purpose doesn't get it back every launch.
    private func updateMyLocation() {
        let granted = locationViewModel.hasLocationPermission()
        let newlyGranted = granted && locationWasGranted == false
        locationWasGranted = granted
        guard granted, locationViewModel.state != .locating else { return }
        if cityListViewModel.locations.contains(where: \.isCurrentLocation) {
            guard cityListViewModel.claimMyLocationCheck() else { return }
            fetchingMyLocationToAdd = false
            locationViewModel.fetchLocation()
        } else if newlyGranted || cityListViewModel.locations.isEmpty {
            fetchingMyLocationToAdd = true
            locationViewModel.fetchLocation()
        }
    }

    private func refreshActiveLocation() {
        // A refresh also moves "now" on, so the hourly strip and captions update even when the
        // weather itself hasn't changed.
        now = Date()
        guard let location = cityListViewModel.activeLocation else { return }
        weatherViewModel.refreshCurrent(location: location)
        weatherViewModel.refreshForecast(location: location)
        airQualityViewModel.load(for: location)
    }

    /// Notification text is built from the cache, so reschedule once fresh data has landed. One
    /// refresh changes state up to four times (cached then fresh, for current and forecast), so the
    /// calls are coalesced into a single run.
    private func rescheduleNotificationsSoon() {
        rescheduleTask?.cancel()
        rescheduleTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await WeatherNotificationScheduler.shared.scheduleNotifications()
        }
    }

    private func backgroundRefreshActiveLocation() {
        guard let location = cityListViewModel.activeLocation else { return }
        weatherViewModel.backgroundRefreshCurrent(location: location)
        weatherViewModel.backgroundRefreshForecast(location: location)
        airQualityViewModel.load(for: location)
    }

    private func addCityFromSheet() {
        guard let location = geoViewModel.locationToAdd else { return }
        cityListViewModel.addLocation(location)
        geoViewModel.reset()
        showAddSheet = false
    }
}

extension EnvironmentValues {
    /// Whether distances (visibility) read in miles rather than kilometres.
    @Entry var distanceInMiles = false
}

private struct CurrentWeatherContent: View {
    @Environment(\.distanceInMiles) private var distanceInMiles
    let weather: CurrentWeather
    /// True when `weather` is the cached forecast's current hour standing in for an old reading:
    /// there's no cloud cover (or visibility) to show.
    var showingForecast = false
    let forecastState: LoadingState<[DayForecast]>
    let location: SavedLocation?
    let showWalkCard: Bool
    let airQuality: AirQuality?
    let now: Date
    let onDaySelected: (DayForecast) -> Void
    let onForecastRetry: () -> Void

    /// The hourly strip covers the next 24 hours.
    private static let hourlyStripCount = 24
    /// Landscape phones and tablets put the hero beside today's details instead of stacking
    /// everything in one stretched column.
    private static let wideLayoutMinWidth: CGFloat = 600

    @State private var contentWidth: CGFloat = 0

    private var isWide: Bool { contentWidth >= Self.wideLayoutMinWidth }

    private var forecastDays: [DayForecast] {
        forecastState.successValue ?? []
    }

    /// "Today" in the city's own date, so it matches the city-local forecast labels.
    private var todayForecast: DayForecast? {
        let todayLabel = WeatherFormatting.todayLabel(timeZone: weather.timeZone)
        return forecastDays.first.flatMap { $0.dateLabel == todayLabel ? $0 : nil }
    }

    private var upcomingDays: [DayForecast] {
        todayForecast != nil ? Array(forecastDays.dropFirst()) : forecastDays
    }

    private var feelsLikeC: Double { weather.units.toCelsius(weather.feelsLike) }

    private var mood: PetMood {
        PetMood.forConditions(
            conditionMain: weather.conditionMain,
            iconCode: weather.iconCode,
            feelsLikeC: feelsLikeC,
            thresholds: RemoteConfigRepository.shared.petWeatherThresholds
        )
    }

    /// Nil while the forecast is loading or failed, which hides the card rather than giving advice
    /// with nothing to base it on.
    private var walkAdvice: WalkAdvice? {
        WalkAdvisor.advice(
            currentFeelsLikeC: feelsLikeC,
            upcoming: upcomingSlots,
            now: now,
            timeZone: weather.timeZone,
            thresholds: RemoteConfigRepository.shared.petWeatherThresholds,
            precipitatingNow: WalkAdvisor.isPrecipitating(conditionMain: weather.conditionMain)
        )
    }

    /// From the hour in progress on, however old the forecast on screen is.
    private var upcomingSlots: [HourlySlot] {
        forecastDays.flatMap(\.hourlySlots).upcoming(from: now)
    }

    private var hourlySlots: [HourlySlot] {
        Array(upcomingSlots.prefix(Self.hourlyStripCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isWide {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) { heroSection }
                    VStack(alignment: .leading, spacing: 12) { todaySection }
                }
            } else {
                heroSection
            }
            if !hourlySlots.isEmpty {
                SectionHeader("HOURLY")
                HourlyStrip(slots: hourlySlots)
            }
            if !isWide {
                todaySection
            }
            if RemoteConfigRepository.shared.radarEnabled {
                SectionHeader("RADAR")
                RadarCard(location: location, timeZone: weather.timeZone)
            }
            restOfWeek
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            contentWidth = width
        }
    }

    @ViewBuilder
    private var heroSection: some View {
        heroCard
        // "Rain starting around 3:15 PM", only when rain or snow is due in the next 2 hours.
        if let nextRain = NextRain.from(forecastDays.first?.quarterHours ?? [], now: now) {
            NextRainLine(nextRain: nextRain, timeZone: weather.timeZone)
        }
        if showWalkCard, RemoteConfigRepository.shared.walkCardEnabled, let walkAdvice {
            WalkCard(advice: walkAdvice)
        }
    }

    @ViewBuilder
    private var todaySection: some View {
        SectionHeader("TODAY")
        detailsCard
    }

    @ViewBuilder
    private var restOfWeek: some View {
        if !upcomingDays.isEmpty || forecastState == .loading || isForecastError {
            SectionHeader("REST OF WEEK")

            if !upcomingDays.isEmpty {
                // Wide screens show the days in two columns, with matching row heights, rather than
                // stretched rows.
                let columns = isWide ? 2 : 1
                Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 0) {
                    ForEach(Array(stride(from: 0, to: upcomingDays.count, by: columns)), id: \.self) { start in
                        GridRow {
                            ForEach(upcomingDays[start ..< min(start + columns, upcomingDays.count)]) { day in
                                UpcomingDayRow(day: day) {
                                    onDaySelected(day)
                                }
                            }
                            if columns == 2, start + 1 >= upcomingDays.count {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                    }
                }
            } else if forecastState == .loading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 24)
                    Spacer()
                }
            } else if case .error(let errorKey, let canRetry) = forecastState {
                VStack(alignment: .leading, spacing: 8) {
                    Text(WeatherErrorMessages.message(for: errorKey))
                        .foregroundStyle(.red)
                    if canRetry {
                        Button("Retry", action: onForecastRetry)
                    }
                }
            }
        }
    }

    private var isForecastError: Bool {
        if case .error = forecastState { return true }
        return false
    }

    private var heroCard: some View {
        Button {
            if let today = todayForecast {
                onDaySelected(today)
            }
        } label: {
            VStack(spacing: 4) {
                // Kept smaller than the card so the scene doesn't dominate, especially on wide screens.
                PetScene(mood: mood, moonPhase: MoonPhase(at: now))
                    .frame(maxWidth: 280)
                    .padding(.horizontal, 24)
                Text(weather.description)
                if location != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                        Text(weather.cityName)
                            .font(.brand(.title2))
                    }
                    .padding(.top, 4)
                }
                Text(WeatherFormatting.temperature(weather.temperature, units: weather.units))
                    .font(.brand(.largeTitle, weight: .bold))
                    // Baloo 2 reserves a lot of empty space above its digits; pull the number up
                    // into it so it sits close under the city name.
                    .padding(.top, -10)
                // Today's high and low in whole degrees: "H 64° · L 61°".
                Text("H \(Int(weather.tempMax.rounded()))° · L \(Int(weather.tempMin.rounded()))°")
                    // "H 64°" would be read as the letter H.
                    .accessibilityLabel("High \(Int(weather.tempMax.rounded()))°, low \(Int(weather.tempMin.rounded()))°")
                Text(mood.caption(on: now, timeZone: weather.timeZone))
                    .font(.brand(.headline))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            .foregroundStyle(mood.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(mood.skyColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(todayForecast == nil)
    }

    private var detailsCard: some View {
        TodayTiles(
            weather: weather,
            showingForecast: showingForecast,
            // Paw check goes with the walk card: Settings' Dog walking switch hides both.
            pavementNow: showWalkCard ? upcomingSlots.first?.pavementTemperature : nil,
            groundWet: upcomingSlots.first?.groundWet == true
                || WalkAdvisor.isPrecipitating(conditionMain: weather.conditionMain),
            // UV is always 0 after dark, so it only shows in the daytime (night icons end in "n").
            uvIndex: weather.iconCode.hasSuffix("n") ? nil : upcomingSlots.first?.uvIndex,
            airQuality: airQuality,
            hasDog: showWalkCard,
            now: now,
            thresholds: RemoteConfigRepository.shared.petWeatherThresholds,
            distanceInMiles: distanceInMiles
        )
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Color.secondaryText)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct HourlyStrip: View {
    let slots: [HourlySlot]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(slots) { slot in
                    VStack(spacing: 6) {
                        Text(slot.timeLabel)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                        WeatherIconView(iconCode: slot.iconCode, size: 32, description: slot.description, date: slot.date)
                        Text("\(Int(slot.temperature.rounded()))°")
                            .fontWeight(.semibold)
                        PrecipChance(percent: slot.precipitationChance)
                    }
                    .padding(.horizontal, 8)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Small "raindrop N%" chip; shows nothing at 0% to avoid clutter.
/// One line under the top card: when rain or snow starts or stops in the next 2 hours.
private struct NextRainLine: View {
    let nextRain: NextRain
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: 12) {
            // The app's own shower and snow icons, as in the hourly row; the text says it all.
            WeatherIconView(iconCode: nextRain.isSnow ? "13d" : "09d", size: 28)
                .accessibilityHidden(true)
            Text(nextRain.line(timeZone: timeZone))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceVariant, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Chance of rain with a drop, as in the hourly row, the week list and the day sheet, shown as
/// `WeatherFormatting.rainChance` has it: nothing under 10%.
struct PrecipChance: View {
    let percent: Int

    var body: some View {
        if let shown = WeatherFormatting.rainChance(percent) {
            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 9))
                Text("\(shown)%")
                    .font(.caption)
            }
            .foregroundStyle(Color.accent)
            .accessibilityLabel("Chance of precipitation \(shown)%")
        }
    }
}

private struct UpcomingDayRow: View {
    let day: DayForecast
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            dayButton
                .frame(maxHeight: .infinity)
            Divider()
        }
    }

    private var dayButton: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                WeatherIconView(iconCode: day.iconCode, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.dateLabel)
                        .fontWeight(.medium)
                    Text(day.description)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                    PrecipChance(percent: day.precipitationChance)
                }
                Spacer()
                Text(WeatherFormatting.temperature(day.tempMax, units: day.units))
                    .fontWeight(.semibold)
                Text(WeatherFormatting.temperature(day.tempMin, units: day.units))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
