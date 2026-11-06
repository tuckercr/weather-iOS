import Foundation

/// Turns Open-Meteo's current reading into the hero's `CurrentWeather`. It's the forecast model's
/// value for the exact spot, so it agrees with the hourly strip. OpenWeather's reading leans on the
/// nearest weather station, which can be miles away and several degrees off, so it's only the
/// backup now. Same rules as Android's `OpenMeteoCurrent.kt`.
enum OpenMeteoCurrent {
    /// Nil without a time or temperature, so `WeatherRepository` falls back to OpenWeather.
    static func weather(
        from response: OpenMeteoCurrentResponse,
        units: WeatherUnits,
        cityName: String
    ) -> CurrentWeather? {
        let reading = response.current
        guard let time = reading.time, let temperature = reading.temperature else { return nil }
        let condition = WmoWeatherCodes.condition(reading.weatherCode ?? 3, isDay: (reading.isDay ?? 1) == 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: response.utcOffsetSeconds) ?? .current
        let sun = OpenMeteoForecast.sunTimes(from: response.daily, calendar: calendar).values.first
        // Today's high and low come from the hourly forecast, so they can miss a reading between hours.
        let high = response.daily.temperatureMax.first.flatMap { $0 }.map { max($0, temperature) } ?? temperature
        let low = response.daily.temperatureMin.first.flatMap { $0 }.map { min($0, temperature) } ?? temperature
        return CurrentWeather(
            cityName: cityName,
            conditionMain: condition.main,
            description: condition.description.weatherSentenceCased,
            iconCode: condition.iconCode,
            temperature: temperature,
            feelsLike: reading.apparentTemperature ?? temperature,
            tempMin: low,
            tempMax: high,
            humidityPercent: reading.relativeHumidity ?? 0,
            pressureHpa: Int((reading.seaLevelPressure ?? 0).rounded()),
            windSpeed: reading.windSpeed ?? 0,
            windDeg: reading.windDirection ?? 0,
            windGust: reading.windGusts,
            visibilityMeters: reading.visibility.map { Int($0.rounded()) },
            cloudPercent: reading.cloudCover ?? 0,
            units: units,
            sunriseEpoch: sun?.sunrise,
            sunsetEpoch: sun?.sunset,
            timezoneOffsetSeconds: response.utcOffsetSeconds,
            observedAtEpoch: time
        )
    }
}
