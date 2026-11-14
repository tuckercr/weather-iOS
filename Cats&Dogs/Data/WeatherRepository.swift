import Foundation

/// A forecast, with the air quality hours put on its slots: fetched with it, or reused from the
/// cache (`AirQualityHours`). Nil air quality when it's switched off, failed or the forecast isn't
/// Open-Meteo's.
struct ForecastFetch: Sendable {
    let days: [DayForecast]
    let airQuality: AirQualityHours?
}

struct WeatherRepository {
    private let client: any OpenWeatherAPI
    private let openMeteo: any OpenMeteoAPI
    private let airQuality: any AirQualityAPI
    private let placeNames: any PlaceNaming
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let useOpenMeteo: @Sendable () -> Bool
    private let useAirQuality: @Sendable () -> Bool
    /// Every failed request to a weather service, for `weather_error`, even when a fallback covers it.
    private let onRequestFailed: @Sendable (WeatherRequestFailure) -> Void

    init(
        client: any OpenWeatherAPI = OpenWeatherClient(),
        openMeteo: any OpenMeteoAPI = OpenMeteoClient(),
        airQuality: any AirQualityAPI = AirQualityClient(),
        placeNames: (any PlaceNaming)? = nil,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        useOpenMeteo: (@Sendable () -> Bool)? = nil,
        useAirQuality: (@Sendable () -> Bool)? = nil,
        onRequestFailed: (@Sendable (WeatherRequestFailure) -> Void)? = nil
    ) {
        self.client = client
        self.openMeteo = openMeteo
        self.airQuality = airQuality
        self.placeNames = placeNames ?? DevicePlaceNames()
        self.timeZone = timeZone
        self.now = now
        self.useOpenMeteo = useOpenMeteo ?? { RemoteConfigRepository.openMeteoEnabled }
        self.useAirQuality = useAirQuality ?? { RemoteConfigRepository.airQualityEnabled }
        self.onRequestFailed = onRequestFailed ?? { failure in
            Task { @MainActor in AnalyticsRepository.shared.logWeatherError(failure) }
        }
    }

    private func reportFailure(_ provider: WeatherRequestFailure.Provider, _ request: WeatherRequestFailure.Request, _ error: Error) {
        onRequestFailed(WeatherRequestFailure(
            provider: provider,
            request: request,
            errorKey: WeatherErrorMessages.errorKey(for: error)
        ))
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
        await fetchForecast(for: location, units: units, cachedAirQuality: nil).map(\.days)
    }

    /// `location`'s forecast, with `cachedAirQuality` reused when it's still good for it
    /// (`AirQualityHours.canBeReused`), otherwise air quality fetched afresh.
    func fetchForecast(
        for location: SavedLocation,
        units: WeatherUnits,
        cachedAirQuality: AirQualityHours?
    ) async -> Result<ForecastFetch, Error> {
        await fetchForecastWithAirQuality(
            units: units,
            cityQuery: Self.cityQuery(for: location),
            latitude: location.latitude,
            longitude: location.longitude,
            cachedAirQuality: cachedAirQuality
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
        await fetchForecastWithAirQuality(
            units: units,
            cityQuery: cityQuery,
            latitude: latitude,
            longitude: longitude,
            cachedAirQuality: nil
        ).map(\.days)
    }

    private func fetchForecastWithAirQuality(
        units: WeatherUnits,
        cityQuery: String?,
        latitude: Double?,
        longitude: Double?,
        cachedAirQuality: AirQualityHours?
    ) async -> Result<ForecastFetch, Error> {
        // Prefer Open-Meteo (true hourly, UV, pavement heat) whenever there are coordinates, unless
        // Remote Config has switched it off; then OpenWeatherMap's 3-hourly forecast by coordinates.
        if let latitude, let longitude {
            guard useOpenMeteo() else {
                return await performForecastFetch(units: units, cityQuery: nil, latitude: latitude, longitude: longitude)
                    .map { ForecastFetch(days: $0, airQuality: nil) }
            }
            do {
                // Air quality for the tile and the walk planner, on the city's scale only. A city's
                // scale doesn't change, so the cached hours' scale lets it go alongside the forecast,
                // whose time zone then confirms it; without a cache it waits for that time zone.
                // Without air quality the forecast still stands. Same as Android.
                let airOn = useAirQuality()
                let guessed = airOn ? cachedAirQuality?.scale : nil
                async let early: AirQualityHours? = guessed == nil
                    ? nil
                    : await airQualityHours(latitude: latitude, longitude: longitude, scale: guessed, cached: cachedAirQuality)
                let response = try await openMeteo.forecast(latitude: latitude, longitude: longitude, units: units)
                let days = OpenMeteoForecast.dayForecasts(from: response, units: units, now: now())
                let scale = response.timezone.map(AirQuality.Scale.forTimeZone)
                let air: AirQualityHours?
                if !airOn {
                    air = nil
                } else if let guessed, scale == nil || scale == guessed {
                    air = await early
                } else {
                    air = await airQualityHours(latitude: latitude, longitude: longitude, scale: scale, cached: cachedAirQuality)
                }
                return .success(ForecastFetch(days: Self.withAirQuality(days, byHour: air?.byHour ?? [:]), airQuality: air))
            } catch {
                reportFailure(.openMeteo, .forecast, error)
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
        ).map { ForecastFetch(days: $0, airQuality: nil) }
    }

    /// `cached` when it's still good on `scale` (the city's), otherwise fetched on that scale only (both
    /// scales when it isn't known, and then the response's time zone picks). Nil when the fetch
    /// fails. Same as Android's forecast refresh.
    private func airQualityHours(
        latitude: Double,
        longitude: Double,
        scale: AirQuality.Scale?,
        cached: AirQualityHours?
    ) async -> AirQualityHours? {
        if let scale, let cached, cached.canBeReused(on: scale, now: now()) { return cached }
        let response: AirQualityHourlyResponse
        do {
            response = try await airQuality.hourly(latitude: latitude, longitude: longitude, scale: scale)
        } catch {
            reportFailure(.openMeteo, .airQuality, error)
            return nil
        }
        let used = scale ?? .forTimeZone(response.timezone)
        return AirQualityHours(fetchedAt: now(), scale: used, byHour: response.byHour(on: used))
    }

    /// Nil when Open-Meteo fails or sends no reading. The place is named only after a reading
    /// arrives, so a failure doesn't spend one of the phone's lookups.
    private func openMeteoCurrent(
        units: WeatherUnits,
        locationLabel: String,
        latitude: Double,
        longitude: Double
    ) async -> CurrentWeather? {
        let response: OpenMeteoCurrentResponse
        do {
            response = try await openMeteo.current(latitude: latitude, longitude: longitude, units: units)
        } catch {
            reportFailure(.openMeteo, .current, error)
            return nil
        }
        guard var weather = OpenMeteoCurrent.weather(from: response, units: units, cityName: "") else {
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
            reportFailure(.openWeather, .current, error)
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
            reportFailure(.openWeather, .forecast, error)
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
