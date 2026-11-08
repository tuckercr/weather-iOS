import Foundation

/// The app's long-lived view models, made once by the App struct (not by a view, whose
/// initialiser runs again whenever its parent redraws) and handed to RootView, with the
/// repositories they share: one copy of the saved cities and one owner of the location manager.
/// Onboarding's answers go to whoever owns them: the dog to Settings, the location to the cities.
@MainActor
final class AppViewModels {
    let settings: SettingsViewModel
    let cityList: CityListViewModel
    let weather: WeatherForecastViewModel
    let welcome: WelcomeViewModel
    let updatePrompt: UpdatePromptViewModel
    /// The radar's frames are the same for every city, so one view model holds them for the app.
    let radar: RadarViewModel

    init() {
        let cities = CityRepository()
        let location = LocationRepository.shared
        let settings = SettingsViewModel(location: location, addCity: { cities.addLocation($0) })
        self.settings = settings
        cityList = CityListViewModel(cities: cities)
        weather = WeatherForecastViewModel(cities: cities, position: location)
        welcome = WelcomeViewModel(
            onDogAnswered: settings.setShowWalkCard,
            onLocationChosen: { cities.addLocation($0) }
        )
        updatePrompt = UpdatePromptViewModel()
        radar = RadarViewModel()
    }
}
