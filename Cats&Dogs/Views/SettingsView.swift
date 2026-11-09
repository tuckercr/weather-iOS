import SwiftUI
import UIKit

struct SettingsView: SettingsScreen {
    @Bindable var settingsViewModel: SettingsViewModel
    let onOpenNotifications: () -> Void
    let onOpenLocations: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCacheCleared = false

    var body: some View {
        List {
            Section {
                // One switch for everything dog: the walk card, Paw check and the walk notifications.
                switchRow(
                    "I have a dog",
                    summary: "Walk times, pavement checks and walk reminders",
                    isOn: settingsViewModel.showWalkCard,
                    set: settingsViewModel.setShowWalkCard
                )
            } header: {
                sectionHeader("My Pets")
            }

            Section {
                Button("Manage Locations", action: onOpenLocations)
            } header: {
                sectionHeader("My Locations")
            }

            Section {
                Button(action: onOpenNotifications) {
                    HStack {
                        Text("Notifications")
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text(notificationsSummary)
                            .foregroundStyle(Color.secondaryText)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                permissionRow(
                    status: settingsViewModel.locationPermission,
                    // iOS's own words for the two kinds of access.
                    grantedText: settingsViewModel.locationAlways
                        ? "Location access: Always"
                        : "Location access: While Using the App",
                    requestTitle: "Allow location access",
                    openSettingsTitle: "Open Settings to enable location",
                    settingsURL: UIApplication.openSettingsURLString,
                    onRequest: { Task { await settingsViewModel.requestLocationAccess() } }
                )
            } header: {
                sectionHeader("Location")
            }

            Section {
                ForEach(UnitOverride.allCases, id: \.self) { option in
                    Button {
                        settingsViewModel.setUnitOverride(option)
                    } label: {
                        HStack {
                            Text(unitLabel(for: option))
                            Spacer()
                            if settingsViewModel.unitOverride == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accent)
                            }
                        }
                        // A plain button only hit-tests what it draws; make the whole row tappable.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // The checkmark is visual only; VoiceOver reads "Selected" from this trait.
                    .accessibilityAddTraits(settingsViewModel.unitOverride == option ? .isSelected : [])
                }
            } header: {
                sectionHeader("Units")
            }

            Section {
                Button("Clear cached weather") {
                    settingsViewModel.clearCache()
                    showCacheCleared = true
                }
            } header: {
                sectionHeader("Cache")
            }

            Section {
                switchRow(
                    "Share usage statistics",
                    isOn: settingsViewModel.shareUsageStatistics,
                    set: settingsViewModel.setShareUsageStatistics
                )
            } header: {
                sectionHeader("Privacy")
            } footer: {
                Text("Anonymous counts of which features get used, to help improve Sunny & Misty. Never your location.")
                    .foregroundStyle(Color.secondaryText)
            }

            Section {
                Button("Weather data by OpenWeather") {
                    openURL(URL(string: "https://openweathermap.org/")!)
                }
                // Open-Meteo's free API is CC BY 4.0, which requires this credit.
                Button("Forecast data by Open-Meteo.com") {
                    openURL(URL(string: "https://open-meteo.com")!)
                }
                // Town and city search uses Open-Meteo's geocoding, whose terms ask for this credit.
                Button("Location data based on GeoNames") {
                    openURL(URL(string: "https://www.geonames.org")!)
                }
                Button("Privacy Policy") {
                    openURL(URL(string: "https://sunnyandmisty.com/privacy")!)
                }
                Button("Terms of Use") {
                    openURL(URL(string: "https://sunnyandmisty.com/terms")!)
                }
            } header: {
                sectionHeader("About")
            } footer: {
                Text(Self.versionText)
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.brandSurface)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await settingsViewModel.refreshPermissions() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await settingsViewModel.refreshPermissions() }
            }
        }
        .alert("Cache cleared", isPresented: $showCacheCleared) {
            Button("OK", role: .cancel) {}
        }
    }

    /// "Off" until notifications are allowed, then how many of the switches are on.
    private var notificationsSummary: String {
        guard settingsViewModel.notificationPermission == .granted else { return String(localized: "Off", comment: "Settings: how many kinds of notification are on") }
        let count = settingsViewModel.notificationsOnCount
        return count == 0 ? String(localized: "Off", comment: "Settings: how many kinds of notification are on") : String(localized: "\(count) on", comment: "Settings: how many kinds of notification are on")
    }

    /// "Version 1.0", plus "· Debug build" in debug builds, so a screenshot says what was tested.
    static var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        #if DEBUG
        return String(localized: "Version \(version) · Debug build", comment: "Settings footer: the app version")
        #else
        return String(localized: "Version \(version)", comment: "Settings footer: the app version")
        #endif
    }

    private func unitLabel(for override: UnitOverride) -> String {
        switch override {
        case .system: String(localized: "Use system setting", comment: "Settings: unit choice")
        case .metric: String(localized: "Metric (°C)", comment: "Settings: unit choice")
        case .imperial: String(localized: "Imperial (°F)", comment: "Settings: unit choice")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(
            settingsViewModel: SettingsViewModel(),
            onOpenNotifications: {},
            onOpenLocations: {}
        )
    }
}

