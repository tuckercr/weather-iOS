import Foundation

/// A sunrise or a sunset, shown in the hourly strip as a slim marker between the hours it falls
/// between ("6:50" between 6 PM and 7 PM). Same rules as Android's `util/SunEvents.kt`.
struct SunEvent: Equatable, Identifiable {
    enum Kind: Equatable {
        case sunrise, sunset
    }

    let kind: Kind
    let epochSeconds: Int

    var id: String { "\(kind)-\(epochSeconds)" }

    var name: String { kind == .sunrise ? String(localized: "Sunrise", comment: "Sunrise or sunset marker in the hourly strip") : String(localized: "Sunset", comment: "Sunrise or sunset marker in the hourly strip") }

    /// "6:50" in the city's time zone, without AM or PM: the hours either side say which.
    func shortTime(timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.dateFormat = "h:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    /// What VoiceOver reads: "Sunset, 6:50 PM".
    func spoken(timeZone: TimeZone) -> String {
        String(localized: "\(name), \(WeatherFormatting.epochTime(epochSeconds, timeZone: timeZone))", comment: "Spoken by VoiceOver: Sunrise or Sunset, then the time")
    }

    /// The forecast's sunrises and sunsets, from Open-Meteo. When it has none (the OpenWeather
    /// 3-hourly fallback, or a forecast cached before they were kept), today's from `weather`, the
    /// current reading with its sun times moved to today, so the strip has no tomorrow's sunrise.
    static func all(forecast: [DayForecast], weather: CurrentWeather) -> [SunEvent] {
        let fromForecast = forecast.flatMap { day in
            [day.sunriseEpoch.map { SunEvent(kind: .sunrise, epochSeconds: $0) },
             day.sunsetEpoch.map { SunEvent(kind: .sunset, epochSeconds: $0) }].compactMap { $0 }
        }
        if !fromForecast.isEmpty { return fromForecast.sorted { $0.epochSeconds < $1.epochSeconds } }
        // A sunrise after the sunset isn't a day (polar day or night), as for the Daylight tile.
        guard let sunrise = weather.sunriseEpoch, let sunset = weather.sunsetEpoch, sunrise < sunset else { return [] }
        return [SunEvent(kind: .sunrise, epochSeconds: sunrise), SunEvent(kind: .sunset, epochSeconds: sunset)]
    }
}

/// One cell of the hourly strip: an hour, or a sunrise or sunset between two of them.
enum HourlyStripItem: Equatable, Identifiable {
    case hour(HourlySlot)
    case sun(SunEvent)

    var id: String {
        switch self {
        case let .hour(slot): "hour-\(slot.id)"
        case let .sun(event): event.id
        }
    }

    /// The hours with each sunrise and sunset still to come placed before the first hour starting at
    /// or after it, so a 6:50 sunset sits between 6 PM and 7 PM, and one at 7:00 before 7 PM. One
    /// before the first hour or after the last starts isn't between two of them, so it's left out.
    static func strip(_ slots: [HourlySlot], events: [SunEvent], now: Date) -> [HourlyStripItem] {
        let nowEpoch = Int(now.timeIntervalSince1970)
        var before: [Int: [SunEvent]] = [:]
        for event in events where event.epochSeconds > nowEpoch {
            guard let index = slots.firstIndex(where: { ($0.epochSeconds ?? .min) >= event.epochSeconds }),
                  index > 0 else { continue }
            before[index, default: []].append(event)
        }
        return slots.enumerated().flatMap { index, slot in
            (before[index] ?? []).sorted { $0.epochSeconds < $1.epochSeconds }.map(HourlyStripItem.sun) + [.hour(slot)]
        }
    }
}
