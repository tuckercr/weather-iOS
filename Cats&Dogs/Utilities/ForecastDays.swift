import Foundation

extension DayForecast {
    /// Whether this is `date`'s day in `timeZone` (the city's): by its hours' timestamps, or by its
    /// label for a forecast cached before they were recorded. What the screen and the notifications
    /// both find today by. Same as Android's `DayForecast.isDayOf`.
    func isDay(of date: Date, in timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if let start = hourlySlots.lazy.compactMap(\.date).first {
            return calendar.isDate(start, inSameDayAs: date)
        }
        return dateLabel == WeatherFormatting.todayLabel(timeZone: timeZone, on: date)
    }
}

extension [DayForecast] {
    /// The forecast for `date`'s day in `timeZone` (the city's); nil beyond the forecast.
    func day(of date: Date, in timeZone: TimeZone) -> DayForecast? {
        first { $0.isDay(of: date, in: timeZone) }
    }
}
