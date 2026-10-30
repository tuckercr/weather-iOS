import XCTest
@testable import Cats_Dogs

@MainActor
final class WeatherRepositoryTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testFetchCurrentWeatherWithCoordinatesSendsCoordinatesAndPreservesLocationLabel() async {
        let api = FakeOpenWeatherAPI()
        let repository = WeatherRepository(client: api, openMeteo: StubOpenMeteoAPI(), airQuality: StubAirQualityAPI(), timeZone: utc)

        let result = await repository.fetchCurrentWeather(
            units: .imperial,
            locationLabel: "Austin, TX, US",
            cityQuery: "Austin",
            latitude: 30.2672,
            longitude: -97.7431
        )

        let weather = try! result.get()
        XCTAssertEqual(weather.cityName, "Austin, TX, US")
        XCTAssertEqual(weather.description, "Clear sky")
        XCTAssertEqual(weather.units, .imperial)
        XCTAssertNil(api.lastCurrentCityQuery)
        XCTAssertEqual(api.lastCurrentLatitude ?? 0, 30.2672, accuracy: 0.0001)
        XCTAssertEqual(api.lastCurrentLongitude ?? 0, -97.7431, accuracy: 0.0001)
        XCTAssertEqual(api.lastCurrentUnits, .imperial)
        XCTAssertEqual(api.currentWeatherCallCount, 1)
    }

    func testFetchCurrentWeatherTrimsCityQueryWhenCoordinatesAreAbsent() async {
        let api = FakeOpenWeatherAPI()
        let repository = WeatherRepository(client: api, openMeteo: StubOpenMeteoAPI(), airQuality: StubAirQualityAPI(), timeZone: utc)

        let result = await repository.fetchCurrentWeather(
            units: .metric,
            cityQuery: "  Denver  "
        )

        let weather = try! result.get()
        XCTAssertEqual(weather.cityName, "OpenWeather City")
        XCTAssertEqual(api.lastCurrentCityQuery, "Denver")
        XCTAssertNil(api.lastCurrentLatitude)
        XCTAssertNil(api.lastCurrentLongitude)
        XCTAssertEqual(api.lastCurrentUnits, .metric)
    }

    func testFetchCurrentWeatherWithBlankCityQueryFailsBeforeCallingAPI() async {
        let api = FakeOpenWeatherAPI()
        let repository = WeatherRepository(client: api, openMeteo: StubOpenMeteoAPI(), airQuality: StubAirQualityAPI(), timeZone: utc)

        let result = await repository.fetchCurrentWeather(units: .metric, cityQuery: "   ")

        guard case .failure(let error as OpenWeatherClientError) = result else {
            return XCTFail("Expected emptyQuery failure")
        }
        XCTAssertEqual(error, .emptyQuery)
        XCTAssertEqual(api.currentWeatherCallCount, 0)
    }

    func testFetchForecastWithMissingApiKeyFailsBeforeCallingAPI() async {
        let api = FakeOpenWeatherAPI()
        let repository = WeatherRepository(
            client: OpenWeatherClient(apiKey: "   "),
            openMeteo: StubOpenMeteoAPI(),
            airQuality: StubAirQualityAPI(),
            timeZone: utc
        )

        let result = await repository.fetchForecast(units: .metric, cityQuery: "Austin")

        guard case .failure(let error as OpenWeatherClientError) = result else {
            return XCTFail("Expected missingApiKey failure")
        }
        XCTAssertEqual(error, .missingApiKey)
        XCTAssertEqual(api.forecastCallCount, 0)
    }

    func testFetchForecastMapsForecastSlotsThroughAggregator() async {
        let dayStart = 1_704_067_200
        let api = FakeOpenWeatherAPI(
            forecastResponse: ForecastResponse(
                list: [
                    forecastItem(epochSeconds: dayStart + 3600, temperature: 1.0, main: "Morning"),
                    forecastItem(epochSeconds: dayStart + 12 * 3600, temperature: 10.0, main: "Noon"),
                ]
            )
        )
        let repository = WeatherRepository(client: api, openMeteo: StubOpenMeteoAPI(), airQuality: StubAirQualityAPI(), timeZone: utc)

        let result = await repository.fetchForecast(units: .metric, cityQuery: " Austin ")

        let forecast = try! result.get()
        XCTAssertEqual(forecast.count, 1)
        XCTAssertEqual(forecast.first?.conditionMain, "Noon")
        XCTAssertEqual(forecast.first?.description, "Noon description")
        XCTAssertEqual(forecast.first?.temperature ?? 0, 10.0, accuracy: 0.0001)
        XCTAssertEqual(forecast.first?.units, .metric)
        XCTAssertEqual(api.lastForecastCityQuery, "Austin")
        XCTAssertNil(api.lastForecastLatitude)
    }

    func testFetchForecastWithCoordinatesUsesOpenMeteoInsteadOfOpenWeather() async {
        let api = FakeOpenWeatherAPI()
        let openMeteo = StubOpenMeteoAPI(response: openMeteoResponse(hours: 1, weatherCode: 0, radiation: 800))
        let repository = WeatherRepository(
            client: api,
            openMeteo: openMeteo,
            airQuality: StubAirQualityAPI(),
            timeZone: utc,
            now: { Date(timeIntervalSince1970: TimeInterval(fixtureDayStart)) }
        )

        let result = await repository.fetchForecast(units: .metric, latitude: 30.2672, longitude: -97.7431)

        let slot = try? result.get().first?.hourlySlots.first
        XCTAssertEqual(api.forecastCallCount, 0)
        XCTAssertEqual(openMeteo.requests.first?.latitude ?? 0, 30.2672, accuracy: 0.0001)
        XCTAssertEqual(openMeteo.requests.first?.units, .metric)
        XCTAssertEqual(try? result.get().first?.conditionMain, "Clear")
        XCTAssertEqual(slot?.temperature, 20)
        XCTAssertEqual(slot?.precipitationChance, 40)
        XCTAssertEqual(slot?.uvIndex, 0)
    }

    func testOpenMeteoForecastCarriesEachHoursAirQuality() async {
        let repository = WeatherRepository(
            client: FakeOpenWeatherAPI(),
            openMeteo: StubOpenMeteoAPI(response: openMeteoResponse(hours: 2)),
            airQuality: StubAirQualityAPI(hourlyIndices: [fixtureDayStart: 40, fixtureDayStart + 3600: 172]),
            timeZone: utc,
            now: { Date(timeIntervalSince1970: TimeInterval(fixtureDayStart)) }
        )

        let result = await repository.fetchForecast(units: .metric, latitude: 30, longitude: -97)

        XCTAssertEqual(try? result.get().flatMap(\.hourlySlots).map(\.airQuality?.band), [0, 3])
        XCTAssertEqual(try? result.get().first?.hourlySlots.last?.airQuality?.index, 172)
    }

    func testNoAirQualityIsFetchedWhileItIsSwitchedOff() async {
        let repository = WeatherRepository(
            client: FakeOpenWeatherAPI(),
            openMeteo: StubOpenMeteoAPI(response: openMeteoResponse(hours: 2)),
            airQuality: StubAirQualityAPI(hourlyIndices: [fixtureDayStart: 172]),
            timeZone: utc,
            now: { Date(timeIntervalSince1970: TimeInterval(fixtureDayStart)) },
            useAirQuality: { false }
        )

        let result = await repository.fetchForecast(units: .metric, latitude: 30, longitude: -97)

        XCTAssertEqual(try? result.get().flatMap(\.hourlySlots).map(\.airQuality), [nil, nil])
    }

    func testAirQualityIsCachedWithTheForecast() throws {
        var slot = HourlySlot(
            timeLabel: "3 PM", iconCode: "01d", description: "clear", temperature: 20, feelsLike: 20,
            windSpeed: 1, windDeg: 0, humidity: 50, pressure: 1013, units: .metric
        )
        slot.airQuality = AirQuality(index: 120, scale: .european, mainPollutant: .ozone)

        let decoded = try JSONDecoder().decode(HourlySlot.self, from: JSONEncoder().encode(slot))

        XCTAssertEqual(decoded.airQuality, slot.airQuality)
    }

    func testForecastStillLoadsWhenAirQualityFails() async {
        let repository = WeatherRepository(
            client: FakeOpenWeatherAPI(),
            openMeteo: StubOpenMeteoAPI(response: openMeteoResponse(hours: 2)),
            airQuality: StubAirQualityAPI(error: URLError(.timedOut)),
            timeZone: utc,
            now: { Date(timeIntervalSince1970: TimeInterval(fixtureDayStart)) }
        )

        let result = await repository.fetchForecast(units: .metric, latitude: 30, longitude: -97)

        XCTAssertEqual(try? result.get().flatMap(\.hourlySlots).map(\.airQuality), [nil, nil])
    }

    func testFetchForecastWithCoordinatesUsesOpenWeatherWhenOpenMeteoIsSwitchedOff() async {
        let api = FakeOpenWeatherAPI()
        let openMeteo = StubOpenMeteoAPI()
        let repository = WeatherRepository(
            client: api,
            openMeteo: openMeteo,
            airQuality: StubAirQualityAPI(),
            timeZone: utc,
            useOpenMeteo: { false }
        )

        _ = await repository.fetchForecast(units: .metric, latitude: 30.2672, longitude: -97.7431)

        XCTAssertTrue(openMeteo.requests.isEmpty)
        XCTAssertEqual(api.forecastCallCount, 1)
        XCTAssertNil(api.lastForecastCityQuery)
        XCTAssertEqual(api.lastForecastLatitude ?? 0, 30.2672, accuracy: 0.0001)
        XCTAssertEqual(api.lastForecastLongitude ?? 0, -97.7431, accuracy: 0.0001)
    }

    func testFetchForecastWithCoordinatesWorksWithoutAnOpenWeatherKey() async {
        let repository = WeatherRepository(
            client: OpenWeatherClient(apiKey: "   "),
            openMeteo: StubOpenMeteoAPI(),
            airQuality: StubAirQualityAPI(),
            timeZone: utc,
            now: { Date(timeIntervalSince1970: TimeInterval(fixtureDayStart)) }
        )

        let result = await repository.fetchForecast(units: .metric, latitude: 1, longitude: 2)

        XCTAssertNotNil(try? result.get())
    }

    func testFetchForecastWithCoordinatesPassesOpenMeteoFailuresThrough() async {
        let repository = WeatherRepository(
            client: FakeOpenWeatherAPI(),
            openMeteo: StubOpenMeteoAPI(error: OpenWeatherClientError.network),
            airQuality: StubAirQualityAPI(),
            timeZone: utc
        )

        let result = await repository.fetchForecast(units: .metric, latitude: 1, longitude: 2)

        guard case .failure(let error as OpenWeatherClientError) = result else {
            return XCTFail("Expected network failure")
        }
        XCTAssertEqual(error, .network)
    }

    func testFetchCurrentWeatherMapsNetworkFailures() async {
        let api = FakeOpenWeatherAPI(currentError: OpenWeatherClientError.network)
        let repository = WeatherRepository(client: api, openMeteo: StubOpenMeteoAPI(), airQuality: StubAirQualityAPI(), timeZone: utc)

        let result = await repository.fetchCurrentWeather(units: .metric, cityQuery: "Austin")

        guard case .failure(let error as OpenWeatherClientError) = result else {
            return XCTFail("Expected network failure")
        }
        XCTAssertEqual(error, .network)
    }

    func testFetchCurrentWeatherMapsOpenWeatherErrorBodyMessage() async {
        let api = FakeOpenWeatherAPI(
            currentError: OpenWeatherClientError.http(statusCode: 404, message: "city not found")
        )
        let repository = WeatherRepository(client: api, openMeteo: StubOpenMeteoAPI(), airQuality: StubAirQualityAPI(), timeZone: utc)

        let result = await repository.fetchCurrentWeather(units: .metric, cityQuery: "Missing City")

        guard case .failure(let error as OpenWeatherClientError) = result else {
            return XCTFail("Expected http failure")
        }
        if case .http(_, let message) = error {
            XCTAssertEqual(message, "city not found")
        } else {
            XCTFail("Expected http case")
        }
    }

    func testFetchCurrentWeatherMapsMissingWeatherEntryToInvalidPayload() async {
        let api = FakeOpenWeatherAPI(
            currentResponse: CurrentWeatherResponse(
                name: "Broken City",
                weather: [],
                main: MainDTO(temp: 21.0, feelsLike: 20.0, humidity: 55),
                wind: WindDTO(speed: 4.2),
                visibility: nil,
                clouds: nil,
                sys: nil
            )
        )
        let repository = WeatherRepository(client: api, openMeteo: StubOpenMeteoAPI(), airQuality: StubAirQualityAPI(), timeZone: utc)

        let result = await repository.fetchCurrentWeather(units: .metric, cityQuery: "Broken City")

        guard case .failure(let error as OpenWeatherClientError) = result else {
            return XCTFail("Expected invalidPayload failure")
        }
        XCTAssertEqual(error, .invalidPayload)
    }
}

private final class FakeOpenWeatherAPI: OpenWeatherAPI, @unchecked Sendable {
    var currentWeatherCallCount = 0
    var forecastCallCount = 0
    var lastCurrentCityQuery: String?
    var lastCurrentLatitude: Double?
    var lastCurrentLongitude: Double?
    var lastCurrentUnits: WeatherUnits?
    var lastForecastCityQuery: String?
    var lastForecastLatitude: Double?
    var lastForecastLongitude: Double?

    private let currentResponse: CurrentWeatherResponse
    private let forecastResponse: ForecastResponse
    private let currentError: Error?

    init(
        currentResponse: CurrentWeatherResponse = currentWeatherResponse(),
        forecastResponse: ForecastResponse = ForecastResponse(list: []),
        currentError: Error? = nil
    ) {
        self.currentResponse = currentResponse
        self.forecastResponse = forecastResponse
        self.currentError = currentError
    }

    func currentWeather(
        cityQuery: String?,
        latitude: Double?,
        longitude: Double?,
        units: WeatherUnits
    ) async throws -> CurrentWeatherResponse {
        currentWeatherCallCount += 1
        lastCurrentCityQuery = cityQuery
        lastCurrentLatitude = latitude
        lastCurrentLongitude = longitude
        lastCurrentUnits = units
        if let currentError { throw currentError }
        return currentResponse
    }

    func forecast(
        cityQuery: String?,
        latitude: Double?,
        longitude: Double?,
        units: WeatherUnits
    ) async throws -> ForecastResponse {
        forecastCallCount += 1
        lastForecastCityQuery = cityQuery
        lastForecastLatitude = latitude
        lastForecastLongitude = longitude
        return forecastResponse
    }
}

private func currentWeatherResponse() -> CurrentWeatherResponse {
    CurrentWeatherResponse(
        name: "OpenWeather City",
        weather: [
            WeatherDescDTO(main: "Clear", description: "clear sky", icon: "01d"),
        ],
        main: MainDTO(temp: 72.5, feelsLike: 70.0, humidity: 42),
        wind: WindDTO(speed: 5.5),
        visibility: 10_000,
        clouds: CloudsDTO(all: 25),
        sys: SysDTO(sunrise: 1_700_000_000, sunset: 1_700_010_000)
    )
}

private func forecastItem(epochSeconds: Int, temperature: Double, main: String) -> ForecastListItemDTO {
    ForecastListItemDTO(
        dt: epochSeconds,
        main: MainDTO(temp: temperature, feelsLike: temperature - 1.0, humidity: 50),
        weather: [
            WeatherDescDTO(
                main: main,
                description: "\(main.lowercased()) description",
                icon: "01d"
            ),
        ],
        wind: WindDTO(speed: 1.0)
    )
}
