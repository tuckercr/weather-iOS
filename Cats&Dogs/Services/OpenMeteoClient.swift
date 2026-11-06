import Foundation

protocol OpenMeteoAPI: Sendable {
    func forecast(latitude: Double, longitude: Double, units: WeatherUnits) async throws -> OpenMeteoResponse
    /// The reading now, for the hero, with today's high, low, sunrise and sunset.
    func current(latitude: Double, longitude: Double, units: WeatherUnits) async throws -> OpenMeteoCurrentResponse
}

/// Open-Meteo's forecast endpoint: free and keyless. Errors reuse `OpenWeatherClientError` so they
/// map onto the same user-facing messages as the OpenWeatherMap calls.
struct OpenMeteoClient: OpenMeteoAPI {
    private let session: URLSession
    private static let baseURL = URL(string: "https://api.open-meteo.com/v1/forecast")!
    private static let forecastDays = 7
    private static let hourlyFields = [
        "temperature_2m", "apparent_temperature", "precipitation_probability", "weather_code",
        "wind_speed_10m", "wind_direction_10m", "relative_humidity_2m", "pressure_msl",
        "uv_index", "shortwave_radiation", "is_day", "precipitation", "snow_depth",
    ].joined(separator: ",")
    private static let currentFields = [
        "temperature_2m", "apparent_temperature", "relative_humidity_2m", "weather_code",
        "cloud_cover", "pressure_msl", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m", "visibility",
        "is_day",
    ].joined(separator: ",")

    init(session: URLSession = .shared) {
        self.session = session
    }

    func forecast(latitude: Double, longitude: Double, units: WeatherUnits) async throws -> OpenMeteoResponse {
        try await get([
            URLQueryItem(name: "hourly", value: Self.hourlyFields),
            // Each day's sunrise and sunset, for the hourly strip, which reaches into tomorrow.
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: String(Self.forecastDays)),
            // Yesterday too, so the pavement and wet ground remember last night's weather.
            URLQueryItem(name: "past_days", value: "1"),
            // A few hours of 15-minute rain and snow from now, for "Rain starting around…" (a little
            // more than the 2 hours shown, so a cached forecast still covers them).
            URLQueryItem(name: "minutely_15", value: "precipitation,snowfall"),
            URLQueryItem(name: "forecast_minutely_15", value: "16"),
            URLQueryItem(name: "past_minutely_15", value: "0"),
        ], latitude: latitude, longitude: longitude, units: units)
    }

    func current(latitude: Double, longitude: Double, units: WeatherUnits) async throws -> OpenMeteoCurrentResponse {
        try await get([
            URLQueryItem(name: "current", value: Self.currentFields),
            URLQueryItem(name: "daily", value: "sunrise,sunset,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ], latitude: latitude, longitude: longitude, units: units)
    }

    private func get<Response: Decodable>(
        _ items: [URLQueryItem],
        latitude: Double,
        longitude: Double,
        units: WeatherUnits
    ) async throws -> Response {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
        ] + items + [
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "temperature_unit", value: units == .imperial ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: units == .imperial ? "mph" : "ms"),
        ]

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: components.url!)
        } catch {
            throw OpenWeatherClientError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw OpenWeatherClientError.invalidPayload
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OpenWeatherClientError.http(statusCode: http.statusCode, message: "http_\(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OpenWeatherClientError.invalidPayload
        }
    }
}
