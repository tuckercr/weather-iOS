import Foundation

/// Which notification it is: each has its own Settings switch.
enum NotificationKind: Equatable, CaseIterable {
    case morningBriefing, walkTime, rain
}

/// One local notification to queue: when, and what it says.
struct PlannedNotification: Equatable {
    let identifier: String
    let kind: NotificationKind
    let date: Date
    let title: String
    let body: String
    /// For a rain alert: when the rain starts, and whether it's snow.
    var rainStart: Int? = nil
    var snow = false
    /// For a briefing that gives the hour's weather: the pets' mood then, for its picture.
    var mood: PetMood? = nil

    /// The pets in its picture, the brand look: in the forecast's mood at 8:30 for a briefing that
    /// gives the hour's weather (none otherwise), out for a walk, or under the umbrella.
    var pictureMood: PetMood? {
        switch kind {
        case .morningBriefing: mood
        case .walkTime: .sunny
        case .rain: snow ? .snow : .rain
        }
    }
}

/// The rain alert last queued, so a shower isn't alerted twice once its alert has gone off.
struct RainAlertRecord: Equatable {
    let rainStart: Int
    let fireDate: Date
}

/// The switches the plan follows: the user's, and Remote Config's for the briefing.
struct NotificationSettings: Equatable {
    var morningBriefing = true
    /// Only counts with a dog: Settings hides it otherwise, keeping its value for when one comes back.
    var walkTime = false
    var rain = false
    /// A dog at home ("I have a dog"): the briefing then mentions the walk, and Walk time can nudge.
    var hasDog = false
    /// Remote Config `daily_weather_notifications_enabled`, `walk_time_notifications_enabled` and
    /// `rain_notifications_enabled`: each switches its kind off for everyone.
    var briefingRemotelyEnabled = true
    var walkTimeRemotelyEnabled = true
    var rainRemotelyEnabled = true
}

/// Plans the notifications from the cached weather. iOS can't run code at a set time, so everything
/// is worked out ahead from the forecast and queued, and replaced whenever the app or a background
/// refresh gets newer weather. Same wording as Android's `NotificationWorkerLogic.kt`, which works
/// it out at the time instead.
enum NotificationPlanner {
    /// The morning briefing, on the device's clock.
    static let briefingHour = 8
    static let briefingMinute = 30
    /// Briefings queued ahead. iOS gives no guaranteed background time, so the queue has to outlast
    /// the gaps between refreshes.
    static let daysQueued = 7
    /// Queued notifications go off whether or not iOS has refreshed since, so what they say depends
    /// on how long after the weather was fetched they go off. Up to a day: a briefing gives the
    /// hour's weather and the walk, and walk nudges are queued.
    static let hourlyForecastTrustedFor: TimeInterval = 24 * 60 * 60
    /// Up to 3 days: a briefing gives only the day's forecast high and low, worded as a forecast.
    /// Later ones just say to tap for today's weather.
    static let dailyForecastTrustedFor: TimeInterval = 3 * 24 * 60 * 60
    /// Walk nudges are planned for today and tomorrow only: further out the forecast is too rough.
    static let walkDays = 2
    /// Below this, the day's rain chance isn't worth a mention in the briefing.
    static let briefingRainChance = 40
    /// Alert this far ahead of the rain at most.
    static let rainAlertLead: TimeInterval = 60 * 60
    /// No alerts before 7 AM or from 9 PM, the city's local time.
    static let rainAlertHours = 7 ..< 21
    /// A shower starting within this of the last one alerted about is the same rain.
    static let rainAlertRepeat = 3 * 60 * 60

    static let fallbackBriefing = (title: String(localized: "Sunny & Misty", comment: "The app's name"), body: String(localized: "Tap to see today's weather.", comment: "Morning briefing notification when there is no forecast"))

    static func plan(
        weather: CurrentWeather?,
        forecast: [DayForecast],
        now: Date,
        settings: NotificationSettings,
        thresholds: PetWeatherThresholds = .standard,
        lastRainAlert: RainAlertRecord? = nil,
        walkNudgesGoneOff: [Date] = [],
        forecastFetchedAt: Date? = nil,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        let slots = forecast.flatMap(\.hourlySlots)
        let briefings = briefingDates(after: now, calendar: calendar)
        // How old the forecast is, since it's what they say: when it was fetched, or for a forecast
        // cached before that was kept, the current reading's time.
        let fetchedAt = forecastFetchedAt
            ?? weather?.observedAtEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? now
        var planned: [PlannedNotification] = []

        let briefingOn = settings.morningBriefing && settings.briefingRemotelyEnabled
        if briefingOn {
            for (day, date) in briefings.enumerated() {
                let age = date.timeIntervalSince(fetchedAt)
                var content: (title: String, body: String)?
                var mood: PetMood?
                if let weather, age < hourlyForecastTrustedFor,
                   let hourly = briefingContent(
                       at: date,
                       weather: weather,
                       forecast: forecast,
                       slots: slots,
                       hasDog: settings.hasDog,
                       thresholds: thresholds,
                       calendar: calendar
                   ) {
                    content = hourly
                    mood = slot(at: date, in: slots).map { PetMood.forHour($0, thresholds: thresholds) }
                } else if let weather, age < dailyForecastTrustedFor {
                    content = forecastBriefingContent(at: date, weather: weather, forecast: forecast)
                }
                let shown = content ?? fallbackBriefing
                planned.append(PlannedNotification(
                    identifier: "briefing_\(day)",
                    kind: .morningBriefing,
                    date: date,
                    title: shown.title,
                    body: shown.body,
                    mood: mood
                ))
            }
        }

        if settings.walkTime, settings.hasDog, settings.walkTimeRemotelyEnabled, let weather {
            for (day, briefing) in walkDates(on: now, calendar: calendar).enumerated() {
                // One a day: none again on a day one has already gone off.
                if walkNudgesGoneOff.contains(where: { calendar.isDate($0, inSameDayAs: briefing) }) { continue }
                guard let slot = bestWalkSlot(after: briefing, slots: slots, thresholds: thresholds, calendar: calendar),
                      let start = slot.date else { continue }
                // The slot under way at 8:30 is "now": the briefing says so (it mentions the walk with
                // a dog, which a nudge needs too), or without it the nudge goes with the briefing time.
                let covers = start <= briefing
                if covers, briefingOn { continue }
                let date = max(start, briefing)
                // Not off a forecast more than a day old: unlike Android's, the nudge can't check the
                // weather again when it goes off.
                guard date > now, date.timeIntervalSince(fetchedAt) < hourlyForecastTrustedFor else { continue }
                planned.append(PlannedNotification(
                    identifier: "walk_\(day)",
                    kind: .walkTime,
                    date: date,
                    title: String(localized: "Time for a walk", comment: "Walk reminder notification title"),
                    body: String(localized: "\(Int(slot.temperature.rounded()))° and \(conditionPhrase(slot)) in \(weather.cityName). Sunny's waiting by the door.", comment: "Walk reminder notification: temperature, the sky or weather (lower case), and the city. Sunny is the dog.")
                        // The air from the walk on, not from 8:30: smoke that cleared by then doesn't count.
                        + (badAirPhrase(after: date, slots: slots, thresholds: thresholds, calendar: calendar)
                            .map { " " + String(localized: "\($0), so a short one.", comment: "Walk reminder notification, after the walk. The argument is the bad air, as in Smoky air today.") } ?? "")
                ))
            }
        }

        if settings.rain, settings.rainRemotelyEnabled, let weather, let alert = rainAlert(
            weather: weather,
            forecast: forecast,
            now: now,
            lastRainAlert: lastRainAlert,
            hasDog: settings.hasDog
        ) {
            planned.append(alert)
        }
        return planned.sorted { $0.date < $1.date }
    }

    /// The walk nudges on record that have gone off by `now`: what `plan` takes as
    /// `walkNudgesGoneOff`, so a day that has had one doesn't get a second.
    static func walkNudgesGoneOff(recorded: [Date], now: Date) -> [Date] {
        recorded.filter { $0 <= now }
    }

    /// The walk nudges to keep on record after planning: today's that have gone off, so a later
    /// replan doesn't send a second, and the ones `plan` has just queued.
    static func walkNudgeRecord(
        goneOff: [Date],
        plan: [PlannedNotification],
        now: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        goneOff.filter { calendar.isDate($0, inSameDayAs: now) } + plan.filter { $0.kind == .walkTime }.map(\.date)
    }

    /// The rain alert to keep on record after planning: the one `plan` has just queued, if any.
    /// Nil leaves the record as it was, so rain already alerted about still isn't alerted again.
    static func rainAlertRecord(plan: [PlannedNotification]) -> RainAlertRecord? {
        plan.last { $0.rainStart != nil }.flatMap { planned in
            planned.rainStart.map { RainAlertRecord(rainStart: $0, fireDate: planned.date) }
        }
    }

    /// The 8:30s walk nudges are planned from, on the device's clock: today's, even once it has
    /// passed, so a replan later in the morning keeps today's nudge, then the next `walkDays - 1`.
    static func walkDates(on now: Date, calendar: Calendar = .current) -> [Date] {
        guard let today = calendar.date(bySettingHour: briefingHour, minute: briefingMinute, second: 0, of: now)
        else { return [] }
        return (0 ..< walkDays).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// The next `daysQueued` 8:30s after `now`, on the device's clock.
    static func briefingDates(after now: Date, calendar: Calendar = .current) -> [Date] {
        guard let next = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: briefingHour, minute: briefingMinute),
            matchingPolicy: .nextTime
        ) else { return [] }
        return (0 ..< daysQueued).compactMap { calendar.date(byAdding: .day, value: $0, to: next) }
    }

    /// "52° and partly cloudy in Knoxville" / "High 70°, low 45°, 60% chance of rain. Sunny's picked
    /// 1 PM for a walk." from the forecast hour under way at the briefing; nil beyond the forecast.
    static func briefingContent(
        at date: Date,
        weather: CurrentWeather,
        forecast: [DayForecast],
        slots: [HourlySlot],
        hasDog: Bool,
        thresholds: PetWeatherThresholds,
        calendar: Calendar = .current
    ) -> (title: String, body: String)? {
        // Forecast days are the city's, so today is the city's date at the briefing, not the device's.
        guard let slot = slot(at: date, in: slots),
              let day = forecast.day(of: date, in: weather.timeZone) else { return nil }
        let title = String(localized: "\(Int(slot.temperature.rounded()))° and \(conditionPhrase(slot)) in \(weather.cityName)", comment: "Morning briefing title: temperature, the sky or weather (lower case), and the city")
        // As on the hero: the day's high and low, taking in the hour's temperature.
        var body = highLowLine(TodayDetails.highLow(temperature: slot.temperature, today: day), rainChance: day.precipitationChance)
        if hasDog {
            // Bad-air hours are left out of the walk silently, so the briefing says why.
            let air = badAirPhrase(after: date, slots: slots, thresholds: thresholds, calendar: calendar)
            if let best = bestWalkSlot(after: date, slots: slots, thresholds: thresholds, calendar: calendar), let start = best.date {
                body += " " + (start <= date
                    ? String(localized: "Sunny says now's a great time for a walk.", comment: "Morning briefing notification. Sunny is the dog.")
                    : String(localized: "Sunny's picked \(best.timeLabel) for a walk.", comment: "Morning briefing notification. Sunny is the dog. The argument is a time."))
                if let air { body += " " + String(localized: "\(air), so keep it short.", comment: "Morning briefing notification, about the walk. The argument is the bad air, as in Smoky air today.") }
            } else {
                body += " " + (air.map { String(localized: "\($0), so potty breaks only.", comment: "Morning briefing notification, about walks. The argument is the bad air, as in Smoky air today.") }
                    ?? String(localized: "Not a good day for walkies.", comment: "Morning briefing notification"))
            }
        }
        return (title, body)
    }

    /// "Today's forecast for Knoxville" / "High 70°, low 45°, 60% chance of rain." from the day's
    /// forecast alone, for a briefing too long after the fetch to give the hour's weather as if it
    /// were current. Nil beyond the forecast.
    static func forecastBriefingContent(
        at date: Date,
        weather: CurrentWeather,
        forecast: [DayForecast]
    ) -> (title: String, body: String)? {
        // Forecast days are the city's, so "today" is the city's date at the briefing, not the
        // device's: a city to the west would otherwise get its day before.
        guard let day = forecast.day(of: date, in: weather.timeZone) else { return nil }
        return (
            String(localized: "Today's forecast for \(weather.cityName)", comment: "Morning briefing title from the day's forecast. The argument is the city."),
            highLowLine((day.tempMax, day.tempMin), rainChance: day.precipitationChance)
        )
    }

    /// "High 70°, low 45°, 60% chance of rain.", the rain only from `briefingRainChance`.
    private static func highLowLine(_ highLow: (high: Double, low: Double), rainChance: Int) -> String {
        let high = Int(highLow.high.rounded())
        let low = Int(highLow.low.rounded())
        if let chance = WeatherFormatting.rainChance(rainChance), chance >= briefingRainChance {
            return String(localized: "High \(high)°, low \(low)°, \(chance)% chance of rain.", comment: "Morning briefing notification: the day's high and low temperatures and the chance of rain")
        }
        return String(localized: "High \(high)°, low \(low)°.", comment: "Morning briefing notification: the day's high and low temperatures")
    }

    /// The first walkable hour from the one under way at `date` to the end of that day.
    static func bestWalkSlot(
        after date: Date,
        slots: [HourlySlot],
        thresholds: PetWeatherThresholds,
        calendar: Calendar
    ) -> HourlySlot? {
        restOfDay(from: date, slots, calendar: calendar).first { WalkAdvisor.isWalkable($0, thresholds) }
    }

    /// The hours from the one under way at `date` to the end of that day: what the walk and the
    /// bad-air phrase both look at.
    private static func restOfDay(from date: Date, _ slots: [HourlySlot], calendar: Calendar) -> [HourlySlot] {
        slots.filter { slot in
            guard let start = slot.date else { return false }
            return start.addingTimeInterval(60 * 60) > date && calendar.isDate(start, inSameDayAs: date)
        }
    }

    /// "Smoky air today" when bad air rules out walking hours from the one under way at `date` to the
    /// end of that day, named by the worst hour's main pollutant as the hero's caption names it
    /// (`WalkReason.airName`): fine particles read as smoke, coarse ones as dust, ozone by name,
    /// anything else as poor air. Nil on a clean day.
    static func badAirPhrase(
        after date: Date,
        slots: [HourlySlot],
        thresholds: PetWeatherThresholds,
        calendar: Calendar
    ) -> String? {
        let worst = restOfDay(from: date, slots, calendar: calendar)
            .filter { WalkAdvisor.hasBadAirForWalking($0, thresholds) }
            .max { ($0.airQuality?.index ?? 0) < ($1.airQuality?.index ?? 0) }
        guard let worst else { return nil }
        let air = WalkReason.airName(worst.airQuality?.mainPollutant) ?? String(localized: "Poor air", comment: "Bad air of no particular kind, at the start of a sentence (Poor air today.)")
        return String(localized: "\(air) today", comment: "Bad air in notifications, followed by more of the sentence. The argument is the bad air, as in Smoky air.")
    }

    /// The forecast hour under way at `date`.
    static func slot(at date: Date, in slots: [HourlySlot]) -> HourlySlot? {
        slots.last { slot in slot.date.map { $0 <= date } ?? false }
            .flatMap { slot in slot.date.map { date.timeIntervalSince($0) < 60 * 60 } == true ? slot : nil }
    }

    /// Rain, snow, storms and fog by their own description ("light rain"); otherwise the sky ("partly
    /// cloudy").
    static func conditionPhrase(_ slot: HourlySlot) -> String {
        let group = slot.iconCode.prefix(2)
        if ["09", "10", "11", "13", "50"].contains(group) { return slot.description.lowercased() }
        return TodayDetails.skyCondition(conditionMain: "", cloudPercent: nil, iconCode: slot.iconCode).name.lowercased()
    }

    /// "Rain starting around 3:15 PM" an hour before rain due within the 15-minute forecast, in the
    /// daytime, and not again for rain whose alert has already gone off. Mentions the walk only with
    /// a dog.
    static func rainAlert(
        weather: CurrentWeather,
        forecast: [DayForecast],
        now: Date,
        lastRainAlert: RainAlertRecord?,
        hasDog: Bool
    ) -> PlannedNotification? {
        guard case let .starting(start, snow) = NextRain.from(forecast.first?.quarterHours ?? [], now: now) else { return nil }
        let startDate = Date(timeIntervalSince1970: TimeInterval(start))
        let fire = max(startDate.addingTimeInterval(-rainAlertLead), now.addingTimeInterval(60))
        guard fire < startDate else { return nil }
        var cityCalendar = Calendar(identifier: .gregorian)
        cityCalendar.timeZone = weather.timeZone
        guard rainAlertHours.contains(cityCalendar.component(.hour, from: fire)) else { return nil }
        if let last = lastRainAlert, abs(start - last.rainStart) < rainAlertRepeat, last.fireDate <= now { return nil }
        let time = WeatherFormatting.epochTime(start, timeZone: weather.timeZone)
        let city = weather.cityName
        let advice = hasDog
            ? String(localized: "Walk now or wait it out.", comment: "Rain alert notification, about the walk")
            : String(localized: "Misty's staying in.", comment: "Rain alert notification without a dog. Misty is the cat.")
        return PlannedNotification(
            identifier: "rain_next",
            kind: .rain,
            date: fire,
            title: snow
                ? String(localized: "Snow starting around \(time)", comment: "Next rain line. The argument is a time.")
                : String(localized: "Rain starting around \(time)", comment: "Next rain line. The argument is a time."),
            body: (snow
                ? String(localized: "Snow on the way in \(city).", comment: "Rain alert notification. The argument is the city.")
                : String(localized: "Rain on the way in \(city).", comment: "Rain alert notification. The argument is the city.")) + " " + advice,
            rainStart: start,
            snow: snow
        )
    }
}
