import Foundation

struct WeatherRepository {
    private let client: any OpenWeatherAPI
    private let openMeteo: any OpenMeteoAPI
    private let airQuality: any AirQualityAPI
    private let placeNames: any PlaceNaming
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let useOpenMeteo: @Sendable () -> Bool
    private let useAirQuality: @Sendable () -> Bool

    init(
        client: any OpenWeatherAPI = OpenWeatherClient(),
        openMeteo: any OpenMeteoAPI = OpenMeteoClient(),
        airQuality: any AirQualityAPI = AirQualityClient(),
        placeNames: (any PlaceNaming)? = nil,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        useOpenMeteo: (@Sendable () -> Bool)? = nil,
        useAirQuality: (@Sendable () -> Bool)? = nil
    ) {
        self.client = client
        self.openMeteo = openMeteo
        self.airQuality = airQuality
        self.placeNames = placeNames ?? DevicePlaceNames()
        self.timeZone = timeZone
        self.now = now
        self.useOpenMeteo = useOpenMeteo ?? { RemoteConfigRepository.openMeteoEnabled }
        self.useAirQuality = useAirQuality ?? { RemoteConfigRepository.airQualityEnabled }
    }

    /// `location`'s current reading: by coordinates when it has them, otherwise by name. My Location
    /// has no label of its own, so the phone's place lookup (or the provider) names it. The screen,
    /// the background refresh and the notifications all fetch by this rule.
    func fetchCurrentWeather(for location: SavedLocation, units: WeatherUnits) async -> Result<CurrentWeather, Error> {
        await fetchCurrentWeather(
            units: units,
            locationLabel: location.isCurrentLocation ? "" : location.label,
            cityQuery: Self.cityQuery(for: location),
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    /// `location`'s forecast: by coordinates when it has them, otherwise by name.
    func fetchForecast(for location: SavedLocation, units: WeatherUnits) async -> Result<[DayForecast], Error> {
        await fetchForecast(
            units: units,
            cityQuery: Self.cityQuery(for: location),
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    /// A city saved without coordinates is looked up by its name.
    private static func cityQuery(for location: SavedLocation) -> String? {
        location.latitude == nil || location.longitude == nil ? location.label : nil
    }

    /// With coordinates, Open-Meteo's reading for the exact spot, which agrees with the hourly strip.
    /// OpenWeather's is the backup: when Open-Meteo fails or Remote Config switches it off, and for
    /// name-only cities. An empty `locationLabel` (My Location) is named by the phone.
    func fetchCurrentWeather(
        units: WeatherUnits,
        locationLabel: String = "",
        cityQuery: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async -> Result<CurrentWeather, Error> {
        if let latitude, let longitude {
            if useOpenMeteo(),
               let weather = await openMeteoCurrent(units: units, locationLabel: locationLabel, latitude: latitude, longitude: longitude) {
                return .success(weather)
            }
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

    /// Nil when Open-Meteo fails or sends no reading. The place is named only after a reading
    /// arrives, so a failure doesn't spend one of the phone's lookups.
    private func openMeteoCurrent(
        units: WeatherUnits,
        locationLabel: String,
        latitude: Double,
        longitude: Double
    ) async -> CurrentWeather? {
        guard let response = try? await openMeteo.current(latitude: latitude, longitude: longitude, units: units),
              var weather = OpenMeteoCurrent.weather(from: response, units: units, cityName: "") else {
            return nil
        }
        let label = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty {
            weather.cityName = await placeNames.name(latitude: latitude, longitude: longitude) ?? SavedLocation.myLocationLabel
        } else {
            weather.cityName = label
        }
        return weather
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
            windGust: response.wind.gust,
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
