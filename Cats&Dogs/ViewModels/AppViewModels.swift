import Foundation

/// The app's long-lived view models, made once by the App struct (not by a view, whose
/// initialiser runs again whenever its parent redraws) and handed to RootView. Onboarding's answers
/// go to the view models that own them: the dog to Settings, the location to the city list.
@MainActor
final class AppViewModels {
    let settings: SettingsViewModel
    let cityList: CityListViewModel
    let weather: WeatherForecastViewModel
    let currentWeather: CurrentWeatherViewModel
    let welcome: WelcomeViewModel
    let updatePrompt: UpdatePromptViewModel
    /// The radar's frames are the same for every city, so one view model holds them for the app.
    let radar: RadarViewModel

    init() {
        let settings = SettingsViewModel()
        let cityList = CityListViewModel()
        let weather = WeatherForecastViewModel()
        self.settings = settings
        self.cityList = cityList
        self.weather = weather
        currentWeather = CurrentWeatherViewModel(cityList: cityList, weather: weather)
        welcome = WelcomeViewModel(
            onDogAnswered: settings.setShowWalkCard,
            onLocationChosen: { cityList.addLocation($0) }
        )
        updatePrompt = UpdatePromptViewModel()
        radar = RadarViewModel()
    }
}
