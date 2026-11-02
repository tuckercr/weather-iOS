import Foundation

/// Handling of cached weather on screen, while a refresh is under way or after one fails. Same rules
/// as Android's `util/StaleWeather.kt`.
enum StaleWeather {
    /// How old cached current conditions can be and still be shown as "now" when a refresh fails.
    /// Older than this, the screen shows the cached forecast for the current hour instead.
    static let showAsNowFor: TimeInterval = 3 * 60 * 60

    /// How often old weather is re-checked against the cutoff while a refresh keeps failing.
    static let recheckInterval: Duration = .seconds(5 * 60)

    /// The longest forecast slot (OpenWeather's 3-hourly ones), for when the last slot ends.
    private static let longestSlot = 3 * 60 * 60

    /// True when this reading is too old to show as the current conditions; unknown age counts as fresh.
    static func isTooOldToShowAsNow(_ weather: CurrentWeather, now: Date) -> Bool {
        guard let observedAt = weather.observedAtEpoch else { return false }
        return now.timeIntervalSince1970 - TimeInterval(observedAt) > showAsNowFor
    }

    /// A reading this old has its icon's day or night ending checked against the clock.
    static let dayNightRecheckAfter: TimeInterval = 30 * 60

    /// `weather.iconCode` with its day or night ending ("d" or "n") for `now` rather than for when the
    /// reading was taken, from the city's sunrise and sunset by time of day. A reading cached before
    /// sunset would otherwise put up the daytime hero after dark until the refresh lands. Readings
    /// under half an hour old, and ones without sun times, keep OpenWeather's icon.
    static func iconCode(_ weather: CurrentWeather, at now: Date) -> String {
        let icon = weather.iconCode
        guard let observedAt = weather.observedAtEpoch,
              let sunrise = weather.sunriseEpoch,
              let sunset = weather.sunsetEpoch,
              now.timeIntervalSince1970 - TimeInterval(observedAt) >= dayNightRecheckAfter,
              icon.hasSuffix("d") || icon.hasSuffix("n")
        else { return icon }
        let offset = weather.timeZone.secondsFromGMT(for: now)
        func timeOfDay(_ epoch: Int) -> Int { ((epoch + offset) % secondsPerDay + secondsPerDay) % secondsPerDay }
        let nowTime = timeOfDay(Int(now.timeIntervalSince1970))
        let rise = timeOfDay(sunrise)
        let set = timeOfDay(sunset)
        // Polar day or night, where the times can wrap past midnight: leave it to OpenWeather.
        guard rise < set else { return icon }
        return String(icon.dropLast()) + (nowTime < rise || nowTime >= set ? "n" : "d")
    }

    /// `weather` with its sunrise and sunset moved onto today in the city when they're from an
    /// earlier day (a reading cached yesterday), so the Daylight tile and the walk card go by today's
    /// sun, as the hero does. Whole days are added, so the times can be a minute or two out. Sun
    /// times from today, or from tomorrow, are left alone.
    static func withSunTimesToday(_ weather: CurrentWeather, at now: Date) -> CurrentWeather {
        guard let sunrise = weather.sunriseEpoch, let sunset = weather.sunsetEpoch else { return weather }
        let offset = weather.timeZone.secondsFromGMT(for: now)
        func cityDay(_ epoch: Int) -> Int { Int((Double(epoch + offset) / Double(secondsPerDay)).rounded(.down)) }
        let days = cityDay(Int(now.timeIntervalSince1970)) - cityDay(sunrise)
        guard days > 0 else { return weather }
        var moved = weather
        moved.sunriseEpoch = sunrise + days * secondsPerDay
        moved.sunsetEpoch = sunset + days * secondsPerDay
        return moved
    }

    /// Whether it's dark in the city at `now` by `weather`'s sun times. False without them, or when
    /// they don't make a day (polar day or night), leaving it to the forecast's icons.
    static func isDark(_ weather: CurrentWeather, at now: Date) -> Bool {
        guard let sunrise = weather.sunriseEpoch, let sunset = weather.sunsetEpoch, sunrise < sunset else { return false }
        let nowEpoch = Int(now.timeIntervalSince1970)
        return nowEpoch < sunrise || nowEpoch >= sunset
    }

    private static let secondsPerDay = 24 * 60 * 60

    /// The cached forecast's slot in progress at `now`, as current conditions: temperature, conditions,
    /// wind and humidity from the forecast, today's high and low, and everything else (city, time zone,
    /// sunrise and sunset, observation time) from `weather`. Visibility isn't forecast, so it's
    /// cleared. Nil when the forecast doesn't cover now (it ran out, or has no timestamps).
    static func forecastAsCurrent(_ weather: CurrentWeather, forecast: [DayForecast], now: Date) -> CurrentWeather? {
        let nowEpoch = Int(now.timeIntervalSince1970)
        let slots = forecast
            .flatMap { day in day.hourlySlots.map { (day, $0) } }
            .filter { $0.1.epochSeconds != nil }
            .sorted { $0.1.epochSeconds! < $1.1.epochSeconds! }
        guard let index = slots.lastIndex(where: { $0.1.epochSeconds! <= nowEpoch }) else { return nil }
        let (day, slot) = slots[index]
        // The slot must still be in progress: before the next one starts, or for the last slot,
        // within the longest slot length.
        let end = index + 1 < slots.count ? slots[index + 1].1.epochSeconds! : slot.epochSeconds! + longestSlot
        guard nowEpoch < end else { return nil }
        return CurrentWeather(
            cityName: weather.cityName,
            conditionMain: conditionMain(forIcon: slot.iconCode),
            description: slot.description,
            iconCode: slot.iconCode,
            temperature: slot.temperature,
            feelsLike: slot.feelsLike,
            tempMin: day.tempMin,
            tempMax: day.tempMax,
            humidityPercent: slot.humidity,
            pressureHpa: slot.pressure,
            windSpeed: slot.windSpeed,
            windDeg: slot.windDeg,
            visibilityMeters: nil,
            cloudPercent: weather.cloudPercent,
            units: slot.units,
            sunriseEpoch: weather.sunriseEpoch,
            sunsetEpoch: weather.sunsetEpoch,
            timezoneOffsetSeconds: weather.timezoneOffsetSeconds,
            observedAtEpoch: weather.observedAtEpoch
        )
    }

    /// OpenWeather's condition group for an icon code ("10d" is rain), as `CurrentWeather.conditionMain`.
    static func conditionMain(forIcon iconCode: String) -> String {
        switch iconCode.prefix(2) {
        case "01": "Clear"
        case "02", "03", "04": "Clouds"
        case "09", "10": "Rain"
        case "11": "Thunderstorm"
        case "13": "Snow"
        case "50": "Mist"
        default: "Clouds"
        }
    }

    /// When `weather` was observed: "10:10 AM" today, "yesterday at 10:10 AM", or "Sat at 10:10 AM",
    /// in the city's own date. Nil when the observation time isn't known.
    static func readingTime(_ weather: CurrentWeather, now: Date) -> String? {
        guard let observedAt = weather.observedAtEpoch else { return nil }
        let time = WeatherFormatting.epochTime(observedAt, timeZone: weather.timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = weather.timeZone
        let then = Date(timeIntervalSince1970: TimeInterval(observedAt))
        if calendar.isDate(then, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(then, inSameDayAs: yesterday) {
            return "yesterday at \(time)"
        }
        let formatter = DateFormatter()
        formatter.timeZone = weather.timeZone
        formatter.locale = .current
        formatter.dateFormat = "EEE"
        return "\(formatter.string(from: then)) at \(time)"
    }
}
