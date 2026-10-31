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

    static let fallbackBriefing = (title: "Sunny & Misty", body: "Tap to see today's weather.")

    static func plan(
        weather: CurrentWeather?,
        forecast: [DayForecast],
        now: Date,
        settings: NotificationSettings,
        thresholds: PetWeatherThresholds = .standard,
        lastRainAlert: RainAlertRecord? = nil,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        let slots = forecast.flatMap(\.hourlySlots)
        let briefings = briefingDates(after: now, calendar: calendar)
        var planned: [PlannedNotification] = []

        let briefingOn = settings.morningBriefing && settings.briefingRemotelyEnabled
        if briefingOn {
            for (day, date) in briefings.enumerated() {
                let content = weather.flatMap {
                    briefingContent(
                        at: date,
                        weather: $0,
                        forecast: forecast,
                        slots: slots,
                        hasDog: settings.hasDog,
                        thresholds: thresholds,
                        calendar: calendar
                    )
                } ?? fallbackBriefing
                planned.append(PlannedNotification(
                    identifier: "briefing_\(day)",
                    kind: .morningBriefing,
                    date: date,
                    title: content.title,
                    body: content.body
                ))
            }
        }

        if settings.walkTime, settings.hasDog, settings.walkTimeRemotelyEnabled, let weather {
            for (day, briefing) in briefings.prefix(walkDays).enumerated() {
                guard let slot = bestWalkSlot(after: briefing, slots: slots, thresholds: thresholds, calendar: calendar),
                      let start = slot.date else { continue }
                // The slot under way at 8:30 is "now": the briefing says so (it mentions the walk with
                // a dog, which a nudge needs too), or without it the nudge goes with the briefing time.
                let covers = start <= briefing
                if covers, briefingOn { continue }
                let date = max(start, briefing)
                guard date > now else { continue }
                planned.append(PlannedNotification(
                    identifier: "walk_\(day)",
                    kind: .walkTime,
                    date: date,
                    title: "Time for a walk",
                    body: "\(Int(slot.temperature.rounded()))° and \(conditionPhrase(slot)) in \(weather.cityName). Sunny's waiting by the door."
                        + (badAirPhrase(after: briefing, slots: slots, thresholds: thresholds, calendar: calendar)
                            .map { " \($0), so a short one." } ?? "")
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
        guard let slot = slot(at: date, in: slots),
              let day = forecast.first(where: { $0.hourlySlots.contains(slot) }) else { return nil }
        let title = "\(Int(slot.temperature.rounded()))° and \(conditionPhrase(slot)) in \(weather.cityName)"
        var body = "High \(Int(day.tempMax.rounded()))°, low \(Int(day.tempMin.rounded()))°"
        if let chance = WeatherFormatting.rainChance(day.precipitationChance), chance >= briefingRainChance {
            body += ", \(chance)% chance of rain"
        }
        body += "."
        if hasDog {
            // Bad-air hours are left out of the walk silently, so the briefing says why.
            let air = badAirPhrase(after: date, slots: slots, thresholds: thresholds, calendar: calendar)
            if let best = bestWalkSlot(after: date, slots: slots, thresholds: thresholds, calendar: calendar), let start = best.date {
                body += start <= date
                    ? " Sunny says now's a great time for a walk."
                    : " Sunny's picked \(best.timeLabel) for a walk."
                if let air { body += " \(air), so keep it short." }
            } else {
                body += air.map { " \($0), so potty breaks only." } ?? " Not a good day for walkies."
            }
        }
        return (title, body)
    }

    /// The first walkable hour from the one under way at `date` to the end of that day.
    static func bestWalkSlot(
        after date: Date,
        slots: [HourlySlot],
        thresholds: PetWeatherThresholds,
        calendar: Calendar
    ) -> HourlySlot? {
        slots.first { slot in
            guard let start = slot.date else { return false }
            return start.addingTimeInterval(60 * 60) > date
                && calendar.isDate(start, inSameDayAs: date)
                && WalkAdvisor.isWalkable(slot, thresholds)
        }
    }

    /// "Smoky air today" when bad air rules out walking hours from the one under way at `date` to the
    /// end of that day, named by the worst hour's main pollutant: particles read as smoke, ozone by
    /// name, anything else as poor air. Nil on a clean day.
    static func badAirPhrase(
        after date: Date,
        slots: [HourlySlot],
        thresholds: PetWeatherThresholds,
        calendar: Calendar
    ) -> String? {
        let worst = slots.filter { slot in
            guard let start = slot.date else { return false }
            return start.addingTimeInterval(60 * 60) > date
                && calendar.isDate(start, inSameDayAs: date)
                && WalkAdvisor.hasBadAirForWalking(slot, thresholds)
        }.max { ($0.airQuality?.index ?? 0) < ($1.airQuality?.index ?? 0) }
        guard let worst else { return nil }
        return switch worst.airQuality?.mainPollutant {
        case .fineParticles, .coarseParticles: "Smoky air today"
        case .ozone: "High ozone today"
        default: "Poor air today"
        }
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
        return TodayDetails.skyCondition(conditionMain: "", cloudPercent: nil, iconCode: slot.iconCode).rawValue.lowercased()
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
        let what = snow ? "Snow" : "Rain"
        return PlannedNotification(
            identifier: "rain_next",
            kind: .rain,
            date: fire,
            title: "\(what) starting around \(WeatherFormatting.epochTime(start, timeZone: weather.timeZone))",
            body: "\(what) on the way in \(weather.cityName). " + (hasDog ? "Walk now or wait it out." : "Misty's staying in."),
            rainStart: start,
            snow: snow
        )
    }
}
