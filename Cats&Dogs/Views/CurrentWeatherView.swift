import SwiftUI

struct CurrentWeatherView: View {
    @Bindable var cityListViewModel: CityListViewModel
    @Bindable var weatherViewModel: WeatherForecastViewModel
    /// Read here rather than passed in as values: if RootView read them, every change would rebuild
    /// the navigation stack, Settings screen included, under the user's finger.
    let settingsViewModel: SettingsViewModel
    let onOpenSettings: () -> Void

    private var unitOverride: UnitOverride { settingsViewModel.unitOverride }
    /// The user's Settings choice; Remote Config can also hide the card for everyone.
    private var showWalkCard: Bool { settingsViewModel.showWalkCard }

    @Environment(\.scenePhase) private var scenePhase
    @State private var showAddLocation = false
    @State private var selectedDay: DayForecast?
    @State private var rescheduleTask: Task<Void, Never>?
    /// "Now" for the hourly strip, walk advice, captions and moon. Moved on when the app becomes
    /// active and every half hour while it stays open, so a screen left on overnight keeps up.
    @State private var now = Date()
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
            // Locations are added from Manage Locations in Settings, or the empty screen's button
            // when there are none.
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
        .fullScreenCover(isPresented: $showAddLocation) {
            AddLocationView(
                savedLocations: cityListViewModel.locations,
                onAdd: { location, _, added in
                    cityListViewModel.addLocation(location, added: added)
                    showAddLocation = false
                },
                onGoTo: { index in
                    cityListViewModel.setActiveIndex(index)
                    showAddLocation = false
                },
                onClose: { showAddLocation = false }
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
            Text("No locations added yet")
                .font(.brand(.title2))
                .multilineTextAlignment(.center)
            Text("Add your first location to get started.")
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                showAddLocation = true
            } label: {
                Label("Add location", systemImage: "plus")
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
    let now: Date
    let onDaySelected: (DayForecast) -> Void
    let onForecastRetry: () -> Void

    /// The hourly strip covers the next 24 hours.
    private static let hourlyStripCount = 24
    /// Landscape phones and tablets put the hero beside today's details instead of stacking
    /// everything in one stretched column.
    private static let wideLayoutMinWidth: CGFloat = 600

    @State private var contentWidth: CGFloat = 0
    /// How far the hero temperature is pulled into Baloo 2's empty space above and below its
    /// digits. Scaled with the number, which follows the large title's text size.
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureTrimTop: CGFloat = 8
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureTrimBottom: CGFloat = 14

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

    /// Day or night by the clock, so a reading cached before sunset doesn't flash the daytime hero.
    private var iconCodeNow: String { StaleWeather.iconCode(weather, at: now) }

    private var mood: PetMood {
        PetMood.forConditions(
            conditionMain: weather.conditionMain,
            iconCode: iconCodeNow,
            feelsLikeC: feelsLikeC,
            thresholds: RemoteConfigRepository.shared.petWeatherThresholds
        )
    }

    /// The reading with today's sunrise and sunset, for one cached on an earlier day, so the Daylight
    /// tile and the walk card follow the clock as the hero does.
    private var weatherToday: CurrentWeather { StaleWeather.withSunTimesToday(weather, at: now) }

    /// Nil while the forecast is loading or failed, which hides the card rather than giving advice
    /// with nothing to base it on.
    private var walkAdvice: WalkAdvice? {
        let weatherToday = weatherToday
        return WalkAdvisor.advice(
            currentFeelsLikeC: feelsLikeC,
            upcoming: upcomingSlots,
            now: now,
            timeZone: weather.timeZone,
            thresholds: RemoteConfigRepository.shared.petWeatherThresholds,
            precipitatingNow: WalkAdvisor.isPrecipitating(conditionMain: weather.conditionMain),
            sunsetEpoch: weatherToday.sunsetEpoch,
            darkNow: StaleWeather.isDark(weatherToday, at: now)
        )
    }

    /// From the hour in progress on, however old the forecast on screen is.
    private var upcomingSlots: [HourlySlot] {
        forecastDays.flatMap(\.hourlySlots).upcoming(from: now)
    }

    private var hourlySlots: [HourlySlot] {
        Array(upcomingSlots.prefix(Self.hourlyStripCount))
    }

    /// "Rain starting around 3:15 PM", only when rain or snow is due in the next 2 hours.
    private var nextRain: NextRain? {
        guard RemoteConfigRepository.shared.nextRainEnabled else { return nil }
        return NextRain.from(forecastDays.first?.quarterHours ?? [], now: now)
    }

    /// The chance of rain over the next few hours, when one of them reaches Remote Config's chance.
    /// It takes over the next-rain line, whose text becomes its headline.
    private var rainOutlook: RainOutlook? {
        let config = RemoteConfigRepository.shared
        return RainOutlook.from(
            upcomingSlots,
            enabled: config.rainOutlookEnabled,
            hours: config.rainOutlookHours,
            minChance: config.rainOutlookMinChance,
            units: weather.units,
            nextRainLine: nextRain?.line(timeZone: weather.timeZone)
        )
    }

    /// Today's seasonal theme by the city's own date, worked out again whenever `now` moves on, so
    /// it ends by itself when its day does.
    private var seasonalTheme: SeasonalTheme? {
        SeasonalThemes.theme(on: now, timeZone: weather.timeZone, in: RemoteConfigRepository.shared.seasonalThemes)
    }

    var body: some View {
        let outlook = rainOutlook
        VStack(alignment: .leading, spacing: 12) {
            if isWide {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) { heroSection(showNextRain: outlook == nil) }
                    VStack(alignment: .leading, spacing: 12) { todaySection }
                }
            } else {
                heroSection(showNextRain: outlook == nil)
            }
            if RemoteConfigRepository.shared.hourlyForecastEnabled, !hourlySlots.isEmpty {
                SectionHeader("HOURLY")
                HourlyStrip(
                    items: HourlyStripItem.strip(
                        hourlySlots,
                        events: SunEvent.all(forecast: forecastDays, weather: weatherToday),
                        now: now
                    ),
                    timeZone: weather.timeZone
                )
            }
            // After the hourly strip in either layout: on wide screens Today is already up top.
            if let outlook {
                SectionHeader("RAIN OUTLOOK")
                RainOutlookCard(outlook: outlook)
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
        .environment(\.seasonalTheme, seasonalTheme)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            contentWidth = width
        }
    }

    /// `showNextRain` is false while the Rain outlook card shows, as its headline says the same.
    @ViewBuilder
    private func heroSection(showNextRain: Bool) -> some View {
        heroCard
        if showNextRain, let nextRain {
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
        if RemoteConfigRepository.shared.weekForecastEnabled,
           !upcomingDays.isEmpty || forecastState == .loading || isForecastError {
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

    /// The theme's caption on its day, otherwise the weather's.
    private var heroCaption: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = weather.timeZone
        return seasonalTheme?.caption(night: mood == .night, on: now, calendar: calendar)
            ?? mood.caption(on: now, timeZone: weather.timeZone, hasDog: showWalkCard)
    }

    private var heroCard: some View {
        Button {
            if let today = todayForecast {
                onDaySelected(today)
            }
        } label: {
            VStack(spacing: 4) {
                // Kept smaller than the card so the scene doesn't dominate, especially on wide screens.
                PetScene(mood: mood, moonPhase: MoonPhase(at: now), decorations: seasonalTheme?.decorations ?? [])
                    .frame(maxWidth: 280)
                    .padding(.horizontal, 24)
                // Medium weight on the small lines so they hold up on the brighter hero colours.
                Text(weather.description)
                    .fontWeight(.medium)
                if location != nil {
                    Text(weather.cityName)
                        .font(.brand(.title2, size: 24))
                        .padding(.top, 4)
                }
                Text(WeatherFormatting.temperature(weather.temperature, units: weather.units))
                    .font(.brand(.largeTitle, size: 56, weight: .bold))
                    // Baloo 2 keeps room above its digits for taller letters, and below them for
                    // descenders. Digits need neither, so the number is pulled in to sit close
                    // under the city name and over the high and low.
                    .padding(.top, -temperatureTrimTop)
                    .padding(.bottom, -temperatureTrimBottom)
                // Today's high and low in whole degrees: "H 64° · L 61°".
                let highLow = TodayDetails.highLow(current: weather, today: todayForecast)
                let high = Int(highLow.high.rounded())
                let low = Int(highLow.low.rounded())
                Text("H \(high)° · L \(low)°")
                    .fontWeight(.medium)
                    // "H 64°" would be read as the letter H.
                    .accessibilityLabel("High \(high)°, low \(low)°")
                Text(heroCaption)
                    .font(.brand(.title3))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .foregroundStyle(seasonalTheme?.heroInk(night: mood == .night) ?? mood.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(
                seasonalTheme?.heroBackground(night: mood == .night) ?? mood.skyColor,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .disabled(todayForecast == nil)
    }

    private var detailsCard: some View {
        TodayTiles(
            weather: weatherToday,
            showingForecast: showingForecast,
            // Paw check goes with the walk card: Settings' Dog walking switch hides both.
            pavementNow: showWalkCard ? upcomingSlots.first?.pavementTemperature : nil,
            groundWet: upcomingSlots.first?.groundWet == true
                || WalkAdvisor.isPrecipitating(conditionMain: weather.conditionMain),
            // UV is always 0 after dark, so it only shows in the daytime (night icons end in "n").
            uvIndex: iconCodeNow.hasSuffix("n") ? nil : upcomingSlots.first?.uvIndex,
            uvPeak: todayForecast?.hourlySlots.filter { $0.uvIndex != nil }.max { ($0.uvIndex ?? 0) < ($1.uvIndex ?? 0) },
            // The forecast's hour in progress, so it shows offline too. A forecast cached before the
            // switch went off can still have it, hence the check here as well.
            airQuality: RemoteConfigRepository.airQualityEnabled ? upcomingSlots.first?.airQuality : nil,
            hasDog: showWalkCard,
            now: now,
            thresholds: RemoteConfigRepository.shared.petWeatherThresholds,
            distanceInMiles: distanceInMiles,
            switches: RemoteConfigRepository.shared.todayTiles
        )
    }
}

private struct SectionHeader: View {
    let title: String
    @Environment(\.seasonalTheme) private var seasonalTheme

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(seasonalTheme?.accent ?? Color.secondaryText)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct HourlyStrip: View {
    let items: [HourlyStripItem]
    let timeZone: TimeZone
    @Environment(\.seasonalTheme) private var seasonalTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    switch item {
                    case let .hour(slot): hour(slot)
                    case let .sun(event):
                        SunMarker(
                            event: event,
                            timeZone: timeZone,
                            besideRain: HourlyStripItem.besideRainChance(items, at: index) {
                                WeatherFormatting.rainChance($0.precipitationChance) != nil
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color.card(seasonalTheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func hour(_ slot: HourlySlot) -> some View {
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

/// A sunrise or sunset between two hours of the strip: half a column, with the time ("6:50"), the
/// sun on the horizon and a thin line beside the temperatures, running on beside the rain chances
/// when an hour either side shows one (`besideRain`). It's never taller than the hours beside it, so
/// the strip doesn't grow for it.
private struct SunMarker: View {
    let event: SunEvent
    let timeZone: TimeZone
    let besideRain: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 6) {
            Text(event.shortTime(timeZone: timeZone))
                .font(.caption.weight(.medium))
                // The walk card's amber, the dark shade on the light card and the pale one on the dark.
                .foregroundStyle(Color(hex: colorScheme == .dark ? 0xFAC775 : 0x633806))
            Image(event.kind == .sunrise ? "wx_sunrise" : "wx_sunset")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .padding(.vertical, 2)
            // An unseen temperature, and rain chance when there is one beside it, laid out as in an
            // hour cell, give the line their height whatever the text size; at their own width inside
            // the line's, they don't widen it.
            VStack(spacing: 6) {
                Text(verbatim: "0°")
                    .fontWeight(.semibold)
                if besideRain {
                    PrecipChance(percent: 50)
                }
            }
            .fixedSize()
            .hidden()
            .frame(width: 1.5)
            .overlay(Capsule().fill(Color.secondaryText.opacity(0.4)))
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.spoken(timeZone: timeZone))
    }
}

/// Small "raindrop N%" chip; shows nothing at 0% to avoid clutter.
/// One line under the top card: when rain or snow starts or stops in the next 2 hours.
private struct NextRainLine: View {
    let nextRain: NextRain
    let timeZone: TimeZone
    @Environment(\.seasonalTheme) private var seasonalTheme

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
        .background(Color.card(seasonalTheme), in: RoundedRectangle(cornerRadius: 12))
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
    /// Wide enough for "H 85° · L 76°", so the icons line up down the list.
    @ScaledMetric(relativeTo: .body) private var temperaturesWidth: CGFloat = 112
    /// The day's description ("Overcast"), 2 points up from the caption size.
    @ScaledMetric(relativeTo: .caption) private var descriptionSize: CGFloat = 14

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
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.dateLabel)
                        .fontWeight(.medium)
                    Text(day.description)
                        .font(.system(size: descriptionSize))
                        .foregroundStyle(Color.secondaryText)
                    PrecipChance(percent: day.precipitationChance)
                }
                Spacer(minLength: 0)
                WeatherIconView(iconCode: day.iconCode, size: 36)
                // The high and low as the hero has them, "H 85° · L 76°", with the high stronger.
                let high = Int(day.tempMax.rounded())
                let low = Int(day.tempMin.rounded())
                (Text("H \(high)°").fontWeight(.semibold)
                    + Text(" · L \(low)°").foregroundStyle(Color.secondaryText))
                    .frame(minWidth: temperaturesWidth, alignment: .trailing)
                    // "H 85°" would be read as the letter H.
                    .accessibilityLabel("High \(high)°, low \(low)°")
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
