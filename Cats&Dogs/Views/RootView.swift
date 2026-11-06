import SwiftUI

private enum AppScreen: Hashable {
    case settings
    case notifications
    case locations
}

struct RootView: View {
    @State private var welcomeViewModel = WelcomeViewModel()
    @State private var cityListViewModel = CityListViewModel()
    @State private var weatherViewModel = WeatherForecastViewModel()
    @State private var settingsViewModel = SettingsViewModel()
    @State private var path: [AppScreen] = []
    @State private var updatePrompt = UpdatePromptViewModel()
    @Environment(\.scenePhase) private var scenePhase
    private let notificationSettingsLink = NotificationSettingsLink.shared

    var body: some View {
        Group {
            if updatePrompt.prompt == .required {
                UpdateRequiredView(storeURL: updatePrompt.storeURL)
            } else if let state = welcomeViewModel.onboardingState {
                if !state.hasSeenWelcome {
                    WelcomeView {
                        welcomeViewModel.completeWelcome()
                    }
                } else if welcomeViewModel.isAskingAboutDog {
                    OnboardingDogView { hasDog in
                        // The walk card only shows when there's a dog.
                        settingsViewModel.setShowWalkCard(hasDog)
                        welcomeViewModel.completeDogQuestion()
                    }
                } else if !state.notificationOnboardingDone {
                    OnboardingNotificationView {
                        welcomeViewModel.completeNotificationOnboarding()
                    }
                } else if !state.locationOnboardingDone {
                    OnboardingLocationView(
                        onLocationResolved: { location in
                            cityListViewModel.addLocation(location)
                            welcomeViewModel.completeLocationOnboarding()
                        },
                        onSkip: {
                            welcomeViewModel.completeLocationOnboarding()
                        }
                    )
                } else {
                    NavigationStack(path: $path) {
                        CurrentWeatherView(
                            cityListViewModel: cityListViewModel,
                            weatherViewModel: weatherViewModel,
                            settingsViewModel: settingsViewModel,
                            onOpenSettings: {
                                weatherViewModel.logSettingsOpened()
                                path.append(.settings)
                            }
                        )
                        .safeAreaInset(edge: .top) {
                            if updatePrompt.prompt == .recommended {
                                UpdateBanner(storeURL: updatePrompt.storeURL, onDismiss: updatePrompt.dismissBanner)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                            }
                        }
                        .navigationDestination(for: AppScreen.self) { screen in
                            switch screen {
                            case .settings:
                                SettingsView(
                                    settingsViewModel: settingsViewModel,
                                    onOpenNotifications: { path.append(.notifications) },
                                    onOpenLocations: { path.append(.locations) },
                                    onLocationResolved: { cityListViewModel.addLocation($0) }
                                )
                            case .notifications:
                                NotificationSettingsView(settingsViewModel: settingsViewModel)
                            case .locations:
                                LocationsView(
                                    cityListViewModel: cityListViewModel,
                                    onShowWeather: { path.removeAll() }
                                )
                            }
                        }
                    }
                    // From the link in iOS Settings; waits here until onboarding is done.
                    .onChange(of: notificationSettingsLink.isRequested, initial: true) { _, requested in
                        guard requested else { return }
                        notificationSettingsLink.isRequested = false
                        path = [.settings, .notifications]
                    }
                }
            } else {
                ProgressView()
            }
        }
        // Remote Config values fetched in the background apply from the next read.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updatePrompt.refresh() }
        }
    }
}

#Preview {
    RootView()
}
