import Foundation

enum ForecastAggregator {
    struct Slot {
        let epochSeconds: Int
        let temperature: Double
        let feelsLike: Double
        let tempMin: Double
        let tempMax: Double
        let conditionMain: String
        let description: String
        let iconCode: String
        let windSpeed: Double
        let windDeg: Int
        let humidity: Int
        let pressure: Int
        /// Probability of precipitation, 0.0...1.0.
        let pop: Double
        /// Rain and snow in mm of water, for the same hour as `pop`; nil when unknown.
        let precipitationMm: Double?
        let uvIndex: Double?
        let pavementTemperature: Double?
        let groundWet: Bool

        init(
            epochSeconds: Int,
            temperature: Double,
            feelsLike: Double,
            tempMin: Double = 0,
            tempMax: Double = 0,
            conditionMain: String,
            description: String,
            iconCode: String,
            windSpeed: Double = 0,
            windDeg: Int = 0,
            humidity: Int = 0,
            pressure: Int = 0,
            pop: Double = 0,
            precipitationMm: Double? = nil,
            uvIndex: Double? = nil,
            pavementTemperature: Double? = nil,
            groundWet: Bool = false
        ) {
            self.epochSeconds = epochSeconds
            self.temperature = temperature
            self.feelsLike = feelsLike
            self.tempMin = tempMin
            self.tempMax = tempMax
            self.conditionMain = conditionMain
            self.description = description
            self.iconCode = iconCode
            self.windSpeed = windSpeed
            self.windDeg = windDeg
            self.humidity = humidity
            self.pressure = pressure
            self.pop = pop
            self.precipitationMm = precipitationMm
            self.uvIndex = uvIndex
            self.pavementTemperature = pavementTemperature
            self.groundWet = groundWet
        }
    }

    static func aggregate(
        slots: [Slot],
        timeZone: TimeZone = .current,
        units: WeatherUnits
    ) -> [DayForecast] {
        guard !slots.isEmpty else { return [] }

        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let grouped = Dictionary(grouping: slots) { slot -> Date in
            let date = Date(timeIntervalSince1970: TimeInterval(slot.epochSeconds))
            return calendar.startOfDay(for: date)
        }

        let dayFormatter = DateFormatter()
        dayFormatter.timeZone = timeZone
        dayFormatter.locale = .current
        dayFormatter.dateFormat = "EEE, MMM d"

        let timeFormatter = DateFormatter()
        timeFormatter.timeZone = timeZone
        timeFormatter.locale = .current
        timeFormatter.dateFormat = "h a"

        return grouped.keys.sorted().map { dayStart in
            let daySlots = grouped[dayStart] ?? []
            let representative = daySlots.min { lhs, rhs in
                minutesFromNoon(lhs.epochSeconds, calendar: calendar) <
                    minutesFromNoon(rhs.epochSeconds, calendar: calendar)
            }!

            let dailyMin = daySlots.map { slot in
                slot.tempMin != 0 ? slot.tempMin : slot.temperature
            }.min() ?? representative.temperature

            let dailyMax = daySlots.map { slot in
                slot.tempMax != 0 ? slot.tempMax : slot.temperature
            }.max() ?? representative.temperature

            let hourlySlots = daySlots
                .sorted { $0.epochSeconds < $1.epochSeconds }
                .map { slot -> HourlySlot in
                    let date = Date(timeIntervalSince1970: TimeInterval(slot.epochSeconds))
                    return HourlySlot(
                        timeLabel: timeFormatter.string(from: date),
                        iconCode: slot.iconCode,
                        description: slot.description.weatherSentenceCased,
                        temperature: slot.temperature,
                        feelsLike: slot.feelsLike,
                        windSpeed: slot.windSpeed,
                        windDeg: slot.windDeg,
                        humidity: slot.humidity,
                        pressure: slot.pressure,
                        units: units,
                        precipitationChance: percent(slot.pop),
                        precipitationMm: slot.precipitationMm,
                        uvIndex: slot.uvIndex,
                        pavementTemperature: slot.pavementTemperature,
                        localHour: calendar.component(.hour, from: date),
                        epochSeconds: slot.epochSeconds,
                        groundWet: slot.groundWet
                    )
                }

            return DayForecast(
                dateLabel: dayFormatter.string(from: dayStart),
                conditionMain: representative.conditionMain,
                description: representative.description.weatherSentenceCased,
                iconCode: representative.iconCode,
                temperature: representative.temperature,
                feelsLike: representative.feelsLike,
                tempMin: dailyMin,
                tempMax: dailyMax,
                units: units,
                hourlySlots: hourlySlots,
                precipitationChance: percent(daySlots.map(\.pop).max() ?? 0),
                uvIndexMax: daySlots.compactMap(\.uvIndex).max()
            )
        }
    }

    private static func percent(_ probability: Double) -> Int {
        Int((probability * 100).rounded())
    }

    private static func minutesFromNoon(_ epochSeconds: Int, calendar: Calendar) -> Int {
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return abs(hour * 60 + minute - 12 * 60)
    }
}
