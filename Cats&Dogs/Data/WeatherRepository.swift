import Foundation

struct WeatherRepository {
    private let client: any OpenWeatherAPI
    private let openMeteo: any OpenMeteoAPI
    private let airQuality: any AirQualityAPI
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let useOpenMeteo: @Sendable () -> Bool
    private let useAirQuality: @Sendable () -> Bool

    init(
        client: any OpenWeatherAPI = OpenWeatherClient(),
        openMeteo: any OpenMeteoAPI = OpenMeteoClient(),
        airQuality: any AirQualityAPI = AirQualityClient(),
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        useOpenMeteo: (@Sendable () -> Bool)? = nil,
        useAirQuality: (@Sendable () -> Bool)? = nil
    ) {
        self.client = client
        self.openMeteo = openMeteo
        self.airQuality = airQuality
        self.timeZone = timeZone
        self.now = now
        self.useOpenMeteo = useOpenMeteo ?? { RemoteConfigRepository.openMeteoEnabled }
        self.useAirQuality = useAirQuality ?? { RemoteConfigRepository.airQualityEnabled }
    }

    func fetchCurrentWeather(
        units: WeatherUnits,
        locationLabel: String = "",
        cityQuery: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async -> Result<CurrentWeather, Error> {
        if let latitude, let longitude {
            return await performCurrentFetch(
                units: units,
                locationLabel: locationLabel,
                cityQuery: nil,
                latitude: latitude,
                longitude: longitude
            )
        }

        let query = cityQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return .failure(OpenWeatherClientError.emptyQuery)
        }

        return await performCurrentFetch(
            units: units,
            locationLabel: locationLabel,
            cityQuery: query,
            latitude: nil,
            longitude: nil
        )
    }

    func fetchForecast(
        units: WeatherUnits,
        cityQuery: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async -> Result<[DayForecast], Error> {
        // Prefer Open-Meteo (true hourly, UV, pavement heat) whenever there are coordinates, unless
        // Remote Config has switched it off; then OpenWeatherMap's 3-hourly forecast by coordinates.
        if let latitude, let longitude {
            guard useOpenMeteo() else {
                return await performForecastFetch(units: units, cityQuery: nil, latitude: latitude, longitude: longitude)
            }
            do {
                // Air quality comes alongside, for the tile and the walk planner; without it the
                // forecast still stands.
                async let air = useAirQuality()
                    ? try? airQuality.hourly(latitude: latitude, longitude: longitude).byHour
                    : nil
                let response = try await openMeteo.forecast(latitude: latitude, longitude: longitude, units: units)
                let days = OpenMeteoForecast.dayForecasts(from: response, units: units, now: now())
                return .success(Self.withAirQuality(days, byHour: await air ?? [:]))
            } catch {
                return .failure(error)
            }
        }

        let query = cityQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return .failure(OpenWeatherClientError.emptyQuery)
        }

        return await performForecastFetch(
            units: units,
            cityQuery: query,
            latitude: nil,
            longitude: nil
        )
    }

    /// Puts each hour's air quality on its slot.
    static func withAirQuality(_ days: [DayForecast], byHour: [Int: AirQuality]) -> [DayForecast] {
        guard !byHour.isEmpty else { return days }
        return days.map { day in
            var day = day
            day.hourlySlots = day.hourlySlots.map { slot in
                var slot = slot
                slot.airQuality = slot.epochSeconds.flatMap { byHour[$0] }
                return slot
            }
            return day
        }
    }

    private func performCurrentFetch(
        units: WeatherUnits,
        locationLabel: String,
        cityQuery: String?,
        latitude: Double?,
        longitude: Double?
    ) async -> Result<CurrentWeather, Error> {
        do {
            let response = try await client.currentWeather(
                cityQuery: cityQuery,
                latitude: latitude,
                longitude: longitude,
                units: units
            )
            return .success(try mapCurrent(response, units: units, locationLabel: locationLabel))
        } catch {
            return .failure(error)
        }
    }

    private func performForecastFetch(
        units: WeatherUnits,
        cityQuery: String?,
        latitude: Double?,
        longitude: Double?
    ) async -> Result<[DayForecast], Error> {
        do {
            let response = try await client.forecast(
                cityQuery: cityQuery,
                latitude: latitude,
                longitude: longitude,
                units: units
            )
            return .success(try mapForecast(response, units: units))
        } catch {
            return .failure(error)
        }
    }

    private func mapCurrent(
        _ response: CurrentWeatherResponse,
        units: WeatherUnits,
        locationLabel: String
    ) throws -> CurrentWeather {
        guard let weather = response.weather.first else {
            throw OpenWeatherClientError.invalidPayload
        }
        let displayCity = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? response.name

        return CurrentWeather(
            cityName: displayCity,
            conditionMain: weather.main,
            description: weather.description.weatherSentenceCased,
            iconCode: weather.icon,
            temperature: response.main.temp,
            feelsLike: response.main.feelsLike,
            tempMin: response.main.tempMin,
            tempMax: response.main.tempMax,
            humidityPercent: response.main.humidity,
            pressureHpa: response.main.pressure,
            windSpeed: response.wind.speed,
            windDeg: response.wind.deg,
            visibilityMeters: response.visibility,
            cloudPercent: response.clouds?.all ?? 0,
            units: units,
            sunriseEpoch: positiveEpoch(response.sys?.sunrise),
            sunsetEpoch: positiveEpoch(response.sys?.sunset),
            timezoneOffsetSeconds: response.timezone,
            observedAtEpoch: positiveEpoch(response.dt)
        )
    }

    private func positiveEpoch(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func mapForecast(_ response: ForecastResponse, units: WeatherUnits) throws -> [DayForecast] {
        var slots: [ForecastAggregator.Slot] = []
        for item in response.list {
            guard let weather = item.weather.first else {
                throw OpenWeatherClientError.invalidPayload
            }
            slots.append(
                ForecastAggregator.Slot(
                    epochSeconds: item.dt,
                    temperature: item.main.temp,
                    feelsLike: item.main.feelsLike,
                    tempMin: item.main.tempMin,
                    tempMax: item.main.tempMax,
                    conditionMain: weather.main,
                    description: weather.description,
                    iconCode: weather.icon,
                    windSpeed: item.wind.speed,
                    windDeg: item.wind.deg,
                    humidity: item.main.humidity,
                    pressure: item.main.pressure,
                    pop: item.pop ?? 0
                )
            )
        }
        // Group and label in the city's own local time, so a remote city's days and hours read on its clock.
        let cityTimeZone = response.city?.timezone.flatMap { TimeZone(secondsFromGMT: $0) } ?? timeZone
        return ForecastAggregator.aggregate(slots: slots, timeZone: cityTimeZone, units: units)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
