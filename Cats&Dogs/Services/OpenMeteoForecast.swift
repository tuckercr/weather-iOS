import Foundation

/// Turns an Open-Meteo response into day forecasts: true hourly data in the city's own time zone,
/// with UV index and an estimated pavement temperature. Coordinates only; name-only cities fall
/// back to OpenWeatherMap in `WeatherRepository`.
enum OpenMeteoForecast {
    /// Converts the parallel hourly arrays into day forecasts, dropping hours before the current
    /// one so hourly views start at "now".
    static func dayForecasts(
        from response: OpenMeteoResponse,
        units: WeatherUnits,
        now: Date
    ) -> [DayForecast] {
        let hourly = response.hourly
        let timeZone = response.timezone.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: response.utcOffsetSeconds)
            ?? .current
        let currentHourStart = startOfLocalHour(containing: now, in: timeZone)
        // Worked out over every hour sent (from yesterday's midnight), including the ones dropped below,
        // so the pavement remembers the night and the morning's sun.
        let pavementC = PavementHeat.series(
            airC: hourly.time.indices.map { i in (hourly.temperature[ifPresent: i] ?? nil).map(units.toCelsius) },
            shortwaveRadiationWm2: hourly.time.indices.map { i in hourly.shortwaveRadiation[ifPresent: i] ?? nil },
            isDay: hourly.time.indices.map { i in (hourly.isDay[ifPresent: i] ?? nil) == 1 }
        )

        // Each day's high and low over all of its hours, including the ones before now that are
        // dropped below, so today reads as the whole day's range rather than what's left of it.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func dayStart(_ epoch: Int) -> Date {
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(epoch)))
        }
        var dayRanges: [Date: (low: Double, high: Double)] = [:]
        for i in hourly.time.indices {
            guard let temperature = hourly.temperature[ifPresent: i] ?? nil else { continue }
            let day = dayStart(hourly.time[i])
            let range = dayRanges[day] ?? (temperature, temperature)
            dayRanges[day] = (min(range.low, temperature), max(range.high, temperature))
        }

        let slots = hourly.time.indices.compactMap { i -> ForecastAggregator.Slot? in
            let epoch = hourly.time[i]
            guard let temperature = hourly.temperature[ifPresent: i] ?? nil, epoch >= currentHourStart else {
                return nil
            }
            let isDay = (hourly.isDay[ifPresent: i] ?? nil) == 1
            let condition = WmoWeatherCodes.condition((hourly.weatherCode[ifPresent: i] ?? nil) ?? 3, isDay: isDay)
            let dayRange = dayRanges[dayStart(epoch)]
            return ForecastAggregator.Slot(
                epochSeconds: epoch,
                temperature: temperature,
                feelsLike: (hourly.apparentTemperature[ifPresent: i] ?? nil) ?? temperature,
                tempMin: dayRange?.low ?? 0,
                tempMax: dayRange?.high ?? 0,
                conditionMain: condition.main,
                description: condition.description,
                iconCode: condition.iconCode,
                windSpeed: (hourly.windSpeed[ifPresent: i] ?? nil) ?? 0,
                windDeg: (hourly.windDirection[ifPresent: i] ?? nil) ?? 0,
                humidity: (hourly.relativeHumidity[ifPresent: i] ?? nil) ?? 0,
                pressure: Int((hourly.seaLevelPressure[ifPresent: i] ?? nil) ?? 0),
                pop: Double((hourly.precipitationProbability[ifPresent: i] ?? nil) ?? 0) / 100,
                uvIndex: hourly.uvIndex[ifPresent: i] ?? nil,
                pavementTemperature: pavementC[i].map(units.fromCelsius),
                groundWet: groundWet(hourly, at: i)
            )
        }
        var days = ForecastAggregator.aggregate(slots: slots, timeZone: timeZone, units: units)
        let quarters = quarterHours(from: response)
        if !quarters.isEmpty, !days.isEmpty { days[0].quarterHours = quarters }
        return days
    }

    /// Each amount is for the 15 minutes before its time, so its quarter starts 15 minutes earlier.
    static func quarterHours(from response: OpenMeteoResponse) -> [QuarterHour] {
        let m = response.minutely15
        return m.time.indices.compactMap { i in
            guard let precipitation = m.precipitation[ifPresent: i] ?? nil else { return nil }
            return QuarterHour(
                epochSeconds: m.time[i] - 15 * 60,
                precipitationMm: precipitation,
                snowfallCm: (m.snowfall[ifPresent: i] ?? nil) ?? 0
            )
        }
    }

    /// How far back rain or snow counts towards wet (and, below freezing, icy) ground.
    private static let wetGroundHours = 12

    /// Rain or snow in the `wetGroundHours` before hour `i` starts or during it, or snow lying.
    /// Precipitation at time t is the total for the hour before t, so hour i's own falls at i + 1.
    static func groundWet(_ hourly: OpenMeteoHourlyDTO, at i: Int) -> Bool {
        if ((hourly.snowDepth[ifPresent: i] ?? nil) ?? 0) > 0 { return true }
        return (i - wetGroundHours + 1 ... i + 1).contains { ((hourly.precipitation[ifPresent: $0] ?? nil) ?? 0) > 0 }
    }

    /// Slots start on local hour boundaries, which aren't UTC hour boundaries in half-hour zones
    /// (India +5:30, Adelaide +9:30, Nepal +5:45), so "now" is floored in local time.
    private static func startOfLocalHour(containing date: Date, in timeZone: TimeZone) -> Int {
        let now = Int(date.timeIntervalSince1970)
        let offset = timeZone.secondsFromGMT(for: date)
        let localNow = now + offset
        let intoHour = ((localNow % 3600) + 3600) % 3600
        return localNow - intoHour - offset
    }
}
