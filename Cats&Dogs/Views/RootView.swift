import SwiftUI

private enum AppScreen: Hashable {
    case settings
    case notifications
    case locations
}

struct RootView: View {
    private let welcomeViewModel: WelcomeViewModel
    private let cityListViewModel: CityListViewModel
    private let weatherViewModel: WeatherForecastViewModel
    private let settingsViewModel: SettingsViewModel
    private let updatePrompt: UpdatePromptViewModel
    private let radarViewModel: RadarViewModel
    @State private var path: [AppScreen] = []
    @Environment(\.scenePhase) private var scenePhase

    init(viewModels: AppViewModels) {
        welcomeViewModel = viewModels.welcome
        cityListViewModel = viewModels.cityList
        weatherViewModel = viewModels.weather
        settingsViewModel = viewModels.settings
        updatePrompt = viewModels.updatePrompt
        radarViewModel = viewModels.radar
    }

    var body: some View {
        Group {
            if updatePrompt.prompt == .required {
                UpdateRequiredView(storeURL: updatePrompt.storeURL)
            } else {
                switch welcomeViewModel.step {
                case nil:
                    ProgressView()
                case .welcome:
                    WelcomeView(onGetStarted: welcomeViewModel.completeWelcome)
                case .dog:
                    OnboardingDogView(onAnswered: welcomeViewModel.answerDogQuestion)
                case .notifications:
                    OnboardingNotificationView(
                        text: welcomeViewModel.notificationOnboardingText,
                        onAllow: welcomeViewModel.allowNotifications,
                        onNotNow: welcomeViewModel.completeNotificationOnboarding
                    )
                case .location:
                    OnboardingLocationView(
                        onLocationResolved: welcomeViewModel.chooseLocation,
                        onSkip: welcomeViewModel.completeLocationOnboarding
                    )
                case .done:
                    NavigationStack(path: $path) {
                        CurrentWeatherView(
                            viewModel: weatherViewModel,
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
                                    onOpenLocations: { path.append(.locations) }
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
                    .onChange(of: settingsViewModel.notificationSettingsRequested, initial: true) { _, requested in
                        guard requested else { return }
                        settingsViewModel.notificationSettingsShown()
                        path = [.settings, .notifications]
                    }
                }
            }
        }
        .environment(radarViewModel)
        // Remote Config values fetched in the background apply from the next read.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updatePrompt.refresh() }
        }
    }
}

#Preview {
    RootView(viewModels: AppViewModels())
}
