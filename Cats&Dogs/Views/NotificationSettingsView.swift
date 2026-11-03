import SwiftUI
import UIKit

/// A switch for each notification, under Settings. Walk time only shows with a dog ("I have a dog"
/// in Settings), any kind is hidden while Remote Config has it off, and hidden switches keep their
/// values. Follow my location shows when there's a My Location.
struct NotificationSettingsView: SettingsScreen {
    @Bindable var settingsViewModel: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                // Once allowed, the switches below say it all.
                if settingsViewModel.notificationPermission != .granted {
                    permissionRow(
                        status: settingsViewModel.notificationPermission,
                        grantedText: "Notifications enabled",
                        requestTitle: "Allow notifications",
                        openSettingsTitle: "Open Settings to enable notifications",
                        // Lands directly on this app's notification settings rather than its general page.
                        settingsURL: UIApplication.openNotificationSettingsURLString,
                        onRequest: {
                            Task { await settingsViewModel.requestNotificationPermission() }
                        }
                    )
                } else {
                    // Each shows unless Remote Config has switched it off for everyone; Walk time
                    // also needs a dog.
                    if settingsViewModel.isAvailable(.morningBriefing) {
                        switchRow(
                            "Morning briefing",
                            summary: settingsViewModel.showWalkCard
                                ? "Today's weather and a walk time, each morning"
                                : "Today's weather each morning",
                            isOn: settingsViewModel.notifyMorningBriefing,
                            set: settingsViewModel.setNotifyMorningBriefing
                        )
                    }
                    if settingsViewModel.isAvailable(.walkTime) {
                        switchRow(
                            "Walk time",
                            summary: "A nudge at the day's best time for a walk",
                            isOn: settingsViewModel.notifyWalkTime,
                            set: settingsViewModel.setNotifyWalkTime
                        )
                    }
                    if settingsViewModel.isAvailable(.rain) {
                        switchRow(
                            "Rain alerts",
                            summary: "When rain or snow is about to start",
                            isOn: settingsViewModel.notifyRain,
                            set: settingsViewModel.setNotifyRain
                        )
                    }
                    if settingsViewModel.hasMyLocation {
                        FollowMyLocationToggle()
                    }
                }
            }

            #if DEBUG
            Section {
                Button("Send sample notifications") {
                    Task { await WeatherNotificationScheduler.shared.sendSamples() }
                }
            } header: {
                sectionHeader("Debug")
            } footer: {
                Text("One of each kind, a few seconds apart. Debug builds only.")
                    .foregroundStyle(Color.secondaryText)
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(Color.brandSurface)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await settingsViewModel.refreshPermissions() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await settingsViewModel.refreshPermissions() }
            }
        }
    }
}

/// Follow my location. It shows on only while it's set and "Always" is allowed. Turning it on
/// explains first, then asks for "Always", which iOS only shows once; after that it opens the
/// Settings app. Same as Android's `FollowMyLocationRow`.
private struct FollowMyLocationToggle: SettingsScreen {
    private let follower = MyLocationFollower.shared
    @State private var explaining = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        switchRow(
            "Follow my location",
            summary: "Notifications for wherever you are, even when the app is closed",
            isOn: follower.isFollowing,
            set: { turnOn in
                if turnOn { explaining = true } else { follower.turnOff() }
            }
        )
        .alert("Follow your location?", isPresented: $explaining) {
            Button("Not now", role: .cancel) {}
            Button("Continue") {
                follower.turnOn {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } message: {
            Text("Sunny & Misty uses your location to send weather for where you are, even when the app is closed or not in use. It's only used for the weather.")
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(settingsViewModel: SettingsViewModel())
    }
}
