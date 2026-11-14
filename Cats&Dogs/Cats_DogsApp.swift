//
//  Cats_DogsApp.swift
//  Cats&Dogs
//
//  Created by Colin Tucker on 6/4/26.
//

import SwiftUI

private let splashDuration: Duration = .seconds(1.5)

@main
struct Cats_DogsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    /// Made once, after start-up has set up Firebase and Remote Config, which they read.
    @State private var viewModels: AppViewModels

    init() {
        BrandAppearance.apply()
        AppStartup.launch()
        _viewModels = State(initialValue: AppViewModels())
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
                RootView(viewModels: viewModels)
                    .transition(.opacity)
                    // Set explicitly: on iOS 27 the asset catalog's global accent colour
                    // (NSAccentColorName) isn't applied, and controls fall back to system blue.
                    .tint(Color.accent)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AppStartup.enteredBackground() }
            if phase == .active { AppStartup.becameActive() }
        }
        .backgroundTask(.appRefresh(WeatherBackgroundRefresher.taskIdentifier)) {
            await AppStartup.backgroundRefresh()
        }
    }
}
