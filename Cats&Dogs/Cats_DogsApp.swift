//
//  Cats_DogsApp.swift
//  Cats&Dogs
//
//  Created by Colin Tucker on 6/4/26.
//

import SwiftUI
import UserNotifications

private let splashDuration: Duration = .seconds(1.5)

@main
struct Cats_DogsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    init() {
        BrandAppearance.apply()
        FirebaseSetup.configureIfAvailable()
        AnalyticsRepository.shared.applyUsageSharingPreference()
        // Start the Remote Config fetch early so the values are ready by the next launch.
        _ = RemoteConfigRepository.shared
        // Set before launch finishes, so a tap on the iOS Settings link that opened the app arrives.
        UNUserNotificationCenter.current().delegate = NotificationSettingsLink.shared
        UNUserNotificationCenter.current().setNotificationCategories(WeatherNotificationScheduler.categories)
        Task { await WeatherNotificationScheduler.shared.refreshAuthorizationOptions() }
        #if DEBUG
        // xcrun simctl launch <device> com.fangjet.weather -sendSampleNotifications
        if ProcessInfo.processInfo.arguments.contains("-sendSampleNotifications") {
            Task { await WeatherNotificationScheduler.shared.sendSamples() }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: splashDuration)
                        withAnimation(.easeOut(duration: 0.3)) {
                            showSplash = false
                        }
                    }
            } else {
                RootView()
                    .transition(.opacity)
                    // Set explicitly: on iOS 27 the asset catalog's global accent colour
                    // (NSAccentColorName) isn't applied, and controls fall back to system blue.
                    .tint(Color.accent)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                WeatherBackgroundRefresher.shared.scheduleNextRefresh()
            }
        }
        .backgroundTask(.appRefresh(WeatherBackgroundRefresher.taskIdentifier)) {
            await WeatherBackgroundRefresher.shared.handleAppRefresh()
        }
    }
}
