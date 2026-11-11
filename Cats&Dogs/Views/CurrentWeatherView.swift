import SwiftUI

struct CurrentWeatherView: View {
    /// Read here rather than passed in as values: if RootView read them, every change would rebuild
    /// the navigation stack, Settings screen included, under the user's finger.
    let settingsViewModel: SettingsViewModel
    let onOpenSettings: () -> Void

    private var unitOverride: UnitOverride { settingsViewModel.unitOverride }
    /// The user's Settings choice; Remote Config can also hide the card for everyone.
    private var showWalkCard: Bool { settingsViewModel.showWalkCard }

    /// What the screen shows, and what it does when: refreshes, My Location and the notification
    /// city. Made once, with the app's other view models (`AppViewModels`): a view's initialiser
    /// runs on every redraw of its parent.
    let viewModel: WeatherForecastViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAddLocation = false
    @State private var selectedDay: DayForecast?

    init(
        viewModel: WeatherForecastViewModel,
        settingsViewModel: SettingsViewModel,
        onOpenSettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.settingsViewModel = settingsViewModel
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        Group {
            if viewModel.locations.isEmpty {
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
            if viewModel.locations.count >= 2 {
                cityTabs
            }
        }
        // The view only says what happened; the view model does the steps.
        .onChange(of: viewModel.activeLocation?.cacheKey) { _, _ in
            viewModel.activeCityChanged()
        }
        .onChange(of: viewModel.locations.notificationLocation?.cacheKey) { _, _ in
            Task { await viewModel.notificationCityChanged() }
        }
        .onChange(of: viewModel.myLocationMoves) { _, _ in
            viewModel.myLocationMoved()
        }
        .onChange(of: unitOverride) { _, _ in
            passDisplaySettings()
            viewModel.unitsChanged()
        }
        // The settings the screen state is worked out with, from the start and as they change.
        .onChange(of: showWalkCard, initial: true) { _, _ in
            passDisplaySettings()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.becameActive() }
        }
        // Restarted (and so only running) while the scene is active.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await viewModel.refreshWhileActive()
        }
        .task(id: viewModel.staleErrorKey) {
            await viewModel.recheckWhileStale()
        }
        .task {
            viewModel.appeared()
        }
        .fullScreenCover(isPresented: $showAddLocation) {
            AddLocationView(
                savedLocations: viewModel.locations,
                onAdd: { location, _, added in
                    viewModel.addCity(location, added: added)
                    showAddLocation = false
                },
                onGoTo: { index in
                    viewModel.selectCity(index)
                    showAddLocation = false
                },
                onClose: { showAddLocation = false }
            )
        }
        .sheet(item: $selectedDay) { day in
            DayDetailSheet(day: day)
                .environment(\.southernHemisphere, isSouthernHemisphere)
                .environment(\.screenNow, viewModel.now)
        }
        // The moon (hero scene and night icons) is lit from the other side down south, and its
        // phase goes by the screen's clock.
        .environment(\.southernHemisphere, isSouthernHemisphere)
        .environment(\.screenNow, viewModel.now)
    }

    private var isSouthernHemisphere: Bool {
        viewModel.activeLocation?.isSouthernHemisphere ?? false
    }

    private var navigationTitle: String {
        viewModel.activeLocation?.label ?? String(localized: "Sunny & Misty", comment: "The app's name")
    }

    private var cityTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.locations.enumerated()), id: \.offset) { index, location in
                    Button {
                        viewModel.selectCity(index)
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
                            index == viewModel.activeIndex
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
                    .accessibilityAddTraits(index == viewModel.activeIndex ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
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

    private func passDisplaySettings() {
        viewModel.displaySettingsChanged(
            hasDog: showWalkCard,
            distanceInMiles: WeatherFormatting.usesMiles(override: unitOverride)
        )
    }

    private var weatherContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch viewModel.screen {
                case .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 48)
                        Spacer()
                    }

                case let .error(errorKey, canRetry, lastUpdated):
                    WeatherErrorStateView(
                        errorKey: errorKey,
                        canRetry: canRetry,
                        onRetry: viewModel.retry,
                        lastUpdated: lastUpdated
                    )

                case let .weather(state):
                    if let stale = state.stale {
                        StaleWeatherBanner(
                            weather: stale.reading,
                            errorKey: stale.errorKey,
                            showingForecast: state.showingForecast,
                            now: state.now
                        )
                    }
                    CurrentWeatherContent(
                        state: state,
                        location: viewModel.activeLocation,
                        onDaySelected: { selectedDay = $0 },
                        onForecastRetry: viewModel.retry
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.pulledToRefresh()
        }
        .overlay(alignment: .top) {
            if viewModel.isRefreshing {
                ProgressView()
                    .padding(.top, 8)
            }
        }
    }
}

private struct CurrentWeatherContent: View {
    /// Everything shown, worked out by the view model at its clock.
    let state: WeatherScreenState
    let location: SavedLocation?
    let onDaySelected: (DayForecast) -> Void
    let onForecastRetry: () -> Void

    /// Landscape phones and tablets put the hero beside today's details instead of stacking
    /// everything in one stretched column.
    private static let wideLayoutMinWidth: CGFloat = 600

    @State private var contentWidth: CGFloat = 0
    /// How far the hero temperature is pulled into Baloo 2's empty space above and below its
    /// digits. Scaled with the number, which follows the large title's text size.
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureTrimTop: CGFloat = 8
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureTrimBottom: CGFloat = 14

    private var isWide: Bool { contentWidth >= Self.wideLayoutMinWidth }
    private var weather: CurrentWeather { state.weather }
    /// The hero's night colours go by the clock, so a rainy evening on a theme's day has them too.
    private var night: Bool { state.darkNow }

    var body: some View {
        let outlook = state.rainOutlook
        VStack(alignment: .leading, spacing: 12) {
            if isWide {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) { heroSection(showNextRain: outlook == nil) }
                    VStack(alignment: .leading, spacing: 12) { todaySection }
                }
            } else {
                heroSection(showNextRain: outlook == nil)
            }
            // No section headers: each card says what it is.
            if !state.hourlyStrip.isEmpty {
                HourlyStrip(items: state.hourlyStrip, timeZone: weather.timeZone)
            }
            // After the hourly strip in either layout: on wide screens Today is already up top.
            if let outlook {
                RainOutlookCard(outlook: outlook)
            }
            if !isWide {
                todaySection
            }
            if state.showsRadar {
                RadarCard(location: location, timeZone: weather.timeZone)
            }
            restOfWeek
        }
        .environment(\.seasonalTheme, state.seasonalTheme)
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
        if showNextRain, let nextRain = state.nextRain {
            NextRainLine(nextRain: nextRain, timeZone: weather.timeZone)
        }
        if let walkCard = state.walkCard {
            WalkCard(content: walkCard)
        }
    }

    @ViewBuilder
    private var todaySection: some View {
        detailsCard
    }

    @ViewBuilder
    private var restOfWeek: some View {
        switch state.week {
        case let .days(days):
            // Wide screens show the days in two columns, with matching row heights, rather than
            // stretched rows.
            let columns = isWide ? 2 : 1
            Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 0) {
                ForEach(Array(stride(from: 0, to: days.count, by: columns)), id: \.self) { start in
                    GridRow {
                        ForEach(days[start ..< min(start + columns, days.count)]) { day in
                            UpcomingDayRow(day: day) {
                                onDaySelected(day)
                            }
                        }
                        if columns == 2, start + 1 >= days.count {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        case .loading:
            HStack {
                Spacer()
                ProgressView()
                    .padding(.vertical, 24)
                Spacer()
            }
        case let .error(errorKey, canRetry):
            VStack(alignment: .leading, spacing: 8) {
                Text(WeatherErrorMessages.message(for: errorKey))
                    .foregroundStyle(.red)
                if canRetry {
                    Button("Retry", action: onForecastRetry)
                }
            }
        case nil:
            EmptyView()
        }
    }

    private var heroCard: some View {
        Button {
            if let today = state.today {
                onDaySelected(today)
            }
        } label: {
            VStack(spacing: 4) {
                // Kept smaller than the card so the scene doesn't dominate, especially on wide screens.
                PetScene(mood: state.mood, decorations: state.seasonalTheme?.decorations ?? [], dark: state.darkNow, foggy: state.foggy)
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
                Text("H \(state.high)° · L \(state.low)°")
                    .fontWeight(.medium)
                    // "H 64°" would be read as the letter H.
                    .accessibilityLabel("High \(state.high)°, low \(state.low)°")
                Text(state.heroCaption)
                    .font(.brand(.title3))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .foregroundStyle(state.seasonalTheme?.heroInk(night: night) ?? state.mood.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(
                state.seasonalTheme?.heroBackground(night: night) ?? state.mood.heroSkyColor(foggy: state.foggy),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .disabled(state.today == nil)
    }

    private var detailsCard: some View {
        TodayTiles(state: state.todayTiles)
    }
}

struct HourlyStrip: View {
    let items: [HourlyStripItem]
    let timeZone: TimeZone
    @Environment(\.seasonalTheme) private var seasonalTheme
    @State private var fade = ScrollEdgeFade.none

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(items) { item in
                    switch item {
                    case let .hour(slot): hour(slot)
                    case let .sun(event): SunMarker(event: event, timeZone: timeZone)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            // The visible part of the strip in the content's own coordinates: its left edge is how
            // far the strip has scrolled. Only a change of fade reaches the view, not every scroll.
            .onGeometryChange(for: ScrollEdgeFade.self) { proxy in
                let visible = proxy.bounds(of: .scrollView) ?? .zero
                return ScrollEdgeFade.forScroll(
                    offset: visible.minX,
                    contentWidth: proxy.size.width,
                    viewportWidth: visible.width
                )
            } action: { newFade in
                withAnimation(.easeInOut(duration: 0.2)) { fade = newFade }
            }
        }
        // A hint that the strip scrolls: its edges fade where there is more past them. A mask, not
        // an overlay, so it suits every card colour; decorative, so VoiceOver reads the same.
        .mask { edgeFadeMask }
        .background(Color.card(seasonalTheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Opaque in the middle; each edge fades to clear over `ScrollEdgeFade.width` while that side
    /// fades, and is opaque otherwise.
    private var edgeFadeMask: some View {
        HStack(spacing: 0) {
            edgeFade(fading: fade.leading, towards: .leading)
            Color.black
            edgeFade(fading: fade.trailing, towards: .trailing)
        }
    }

    private func edgeFade(fading: Bool, towards edge: UnitPoint) -> some View {
        ZStack {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: edge,
                endPoint: edge == .leading ? .trailing : .leading
            )
            // Covers the gradient when this side doesn't fade; its opacity animates.
            Color.black.opacity(fading ? 0 : 1)
        }
        .frame(width: ScrollEdgeFade.width)
    }

    private func hour(_ slot: HourlySlot) -> some View {
        VStack(spacing: 6) {
            Text(slot.timeLabel)
                .font(.caption)
                .foregroundStyle(Color.secondaryText)
                .accessibilitySortPriority(3)
            HourIconSpace {
                if WeatherFormatting.rainChance(slot.precipitationChance) != nil {
                    VStack(spacing: HourIconMetrics.chanceSpacing) {
                        icon(slot, size: HourIconMetrics.iconBesideChance)
                        // Read last, after the temperature, as before it moved up beside the icon.
                        PrecipChance(percent: slot.precipitationChance)
                    }
                } else {
                    icon(slot, size: HourIconMetrics.iconSize)
                }
            }
            Text("\(Int(slot.temperature.rounded()))°")
                .fontWeight(.semibold)
                .accessibilitySortPriority(1)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private func icon(_ slot: HourlySlot, size: CGFloat) -> some View {
        WeatherIconView(iconCode: slot.iconCode, size: size, description: slot.description, date: slot.date)
            .accessibilitySortPriority(2)
    }
}

/// An hour's icon on its own, and the smaller one with a rain chance under it.
enum HourIconMetrics {
    static let iconSize: CGFloat = 32
    static let iconBesideChance: CGFloat = 24
    static let chanceSpacing: CGFloat = 2
}

/// The icon's space in an hour of the strip, the same height in every hour, so the card never
/// changes height with the rain and never ends in a gap. An hour with a rain chance shows a smaller
/// icon with the chance under it, inside the space; an hour without one, the full-size icon in the
/// middle. The sunrise and sunset markers use it for the sun too, so their lines meet the
/// temperatures. Same sizes as Android's `HourIconSpace`.
struct HourIconSpace<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            // An unseen smaller icon and chance, a point wide, give the space its height at any text
            // size, whether or not any hour has rain.
            VStack(spacing: HourIconMetrics.chanceSpacing) {
                Color.clear.frame(width: HourIconMetrics.iconBesideChance, height: HourIconMetrics.iconBesideChance)
                PrecipChance(percent: 50)
            }
            .fixedSize()
            .frame(width: 1)
            .hidden()
            .accessibilityHidden(true)
            content
        }
        .frame(minHeight: HourIconMetrics.iconSize)
    }
}

/// A sunrise or sunset between two hours of the strip: half a column, with the time ("6:50"), the
/// sun on the horizon in the hours' icon space and a thin line beside the temperatures. It's never
/// taller than the hours beside it, so the strip doesn't grow for it.
private struct SunMarker: View {
    let event: SunEvent
    let timeZone: TimeZone
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 6) {
            Text(event.shortTime(timeZone: timeZone))
                .font(.caption.weight(.medium))
                // The walk card's amber, the dark shade on the light card and the pale one on the dark.
                .foregroundStyle(Color(hex: colorScheme == .dark ? 0xFAC775 : 0x633806))
            HourIconSpace {
                Image(event.kind == .sunrise ? "wx_sunrise" : "wx_sunset")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            }
            // An unseen temperature gives the line its height whatever the text size; at its own
            // width inside the line's, it doesn't widen it.
            Text(verbatim: "0°")
                .fontWeight(.semibold)
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
