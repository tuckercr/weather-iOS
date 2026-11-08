import SwiftUI

private enum AppScreen: Hashable {
    case settings
    case notifications
    case locations
}

struct RootView: View {
    @State private var welcomeViewModel: WelcomeViewModel
    @State private var cityListViewModel: CityListViewModel
    @State private var weatherViewModel = WeatherForecastViewModel()
    @State private var settingsViewModel: SettingsViewModel
    @State private var path: [AppScreen] = []
    @State private var updatePrompt = UpdatePromptViewModel()
    /// The radar's frames are the same for every city, so one view model holds them for the app.
    @State private var radarViewModel = RadarViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Onboarding's answers go to the view models that own them: the dog to Settings, the
        // location to the city list.
        let settings = SettingsViewModel()
        let cityList = CityListViewModel()
        _settingsViewModel = State(initialValue: settings)
        _cityListViewModel = State(initialValue: cityList)
        _welcomeViewModel = State(initialValue: WelcomeViewModel(
            onDogAnswered: settings.setShowWalkCard,
            onLocationChosen: { cityList.addLocation($0) }
        ))
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
    RootView()
}
