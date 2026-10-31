import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class WeatherNotificationScheduler {
    static let shared = WeatherNotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    /// Every identifier this app has queued under, now or in older versions (the 9 AM / 1 PM / 7 PM
    /// "weather_daily" ones), so a reschedule clears them all and leaves nothing else alone.
    nonisolated static let identifierPrefixes = ["weather_daily", "briefing_", "walk_", "rain_"]

    private init() {}

    /// `.providesAppNotificationSettings` adds the link to the Notifications screen in iOS Settings.
    private static let authorizationOptions: UNAuthorizationOptions = [
        .alert, .sound, .badge, .providesAppNotificationSettings,
    ]

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: Self.authorizationOptions)
        } catch {
            return false
        }
    }

    /// Asks again, without a prompt, when already allowed: people who allowed notifications before
    /// the Settings link existed get it too. Only for full authorization: a provisional user would
    /// see the real prompt.
    func refreshAuthorizationOptions() async {
        guard await authorizationStatus() == .authorized else { return }
        _ = await requestAuthorization()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func isAuthorized() async -> Bool {
        let status = await authorizationStatus()
        return status == .authorized || status == .provisional
    }

    /// Replaces the queued notifications with a fresh plan from the cached weather for the active
    /// city: the 8:30 AM briefings, the walk-time nudges and the next rain alert, as each switch
    /// allows. Callers run this after a refresh has written the cache, so it never needs the network.
    func scheduleNotifications(preferences: PreferencesStore? = nil) async {
        let preferences = preferences ?? .shared
        await removePendingNotifications()
        guard let location = preferences.savedLocations.notificationLocation, await isAuthorized() else { return }
        let weather = preferences.cachedWeather(for: location.cacheKey)
        let settings = NotificationSettings(
            morningBriefing: preferences.notifyMorningBriefing,
            walkTime: preferences.notifyWalkTime,
            rain: preferences.notifyRain,
            hasDog: preferences.showWalkCard,
            briefingRemotelyEnabled: RemoteConfigRepository.shared.dailyWeatherNotificationsEnabled,
            walkTimeRemotelyEnabled: RemoteConfigRepository.shared.walkTimeNotificationsEnabled,
            rainRemotelyEnabled: RemoteConfigRepository.shared.rainNotificationsEnabled
        )
        let plan = NotificationPlanner.plan(
            weather: weather,
            forecast: preferences.cachedForecast(for: location.cacheKey) ?? [],
            now: Date(),
            settings: settings,
            thresholds: RemoteConfigRepository.shared.petWeatherThresholds,
            lastRainAlert: preferences.lastRainAlert
        )

        let southern = (location.latitude ?? 0) < 0
        let calendar = Calendar.current
        for planned in plan {
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: planned.date),
                repeats: false
            )
            // The brand look: the pets, in today's mood for the next briefing, out for a walk, or
            // under the umbrella.
            let mood: PetMood? = switch planned.kind {
            case .morningBriefing: planned.identifier == "briefing_0" ? weather.map(currentMood) : nil
            case .walkTime: .sunny
            case .rain: planned.snow ? .snow : .rain
            }
            let content = content(for: planned, mood: mood, southernHemisphere: southern)
            try? await center.add(UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger))
            if let start = planned.rainStart {
                preferences.setLastRainAlert(RainAlertRecord(rainStart: start, fireDate: planned.date))
            }
        }
    }

    private func content(for planned: PlannedNotification, mood: PetMood?, southernHemisphere: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default
        // Groups them by kind in Notification Center, like Android's channels.
        content.threadIdentifier = Self.threadIdentifier(planned.kind)
        // The category gives a stack its own summary ("3 more briefings").
        content.categoryIdentifier = Self.threadIdentifier(planned.kind)
        if let mood, let png = petsPicture(mood: mood, southernHemisphere: southernHemisphere),
           let attachment = Self.attachment(png, identifier: planned.identifier) {
            content.attachments = [attachment]
        }
        return content
    }

    #if DEBUG
    /// Debug builds only: one of each kind, plus a second briefing so a group forms, a few seconds
    /// apart with made-up text, through the same content code. Shows the look and the grouping
    /// without waiting for 8:30 or the weather.
    func sendSamples(preferences: PreferencesStore? = nil) async {
        guard await isAuthorized() else { return }
        let preferences = preferences ?? .shared
        // They follow "I have a dog", and use the notification city's name, as the real ones do.
        let hasDog = preferences.showWalkCard
        let location = preferences.savedLocations.notificationLocation
        let city = location.flatMap { preferences.cachedWeather(for: $0.cacheKey)?.cityName }
            ?? location.flatMap { $0.isCurrentLocation ? nil : $0.label }
            ?? "Knoxville"
        let walk = hasDog ? " Sunny's picked 1 PM for a walk." : ""
        let advice = hasDog ? "Walk now or wait it out." : "Misty's staying in."
        let notToday = hasDog ? " Not a good day for walkies." : ""
        let samples: [(PlannedNotification, PetMood)] = [
            (PlannedNotification(identifier: "debug_briefing_1", kind: .morningBriefing, date: .now,
                                 title: "52° and partly cloudy in \(city)",
                                 body: "High 70°, low 45°, 60% chance of rain.\(walk)"), .cloudy),
            (PlannedNotification(identifier: "debug_walk", kind: .walkTime, date: .now,
                                 title: "Time for a walk",
                                 body: "64° and clear in \(city). Sunny's waiting by the door."), .sunny),
            (PlannedNotification(identifier: "debug_rain", kind: .rain, date: .now,
                                 title: "Rain starting around 3:15 PM",
                                 body: "Rain on the way in \(city). \(advice)"), .rain),
            (PlannedNotification(identifier: "debug_snow", kind: .rain, date: .now,
                                 title: "Snow starting around 6:45 PM",
                                 body: "Snow on the way in \(city). \(advice)"), .snow),
            (PlannedNotification(identifier: "debug_briefing_2", kind: .morningBriefing, date: .now,
                                 title: "48° and light rain in \(city)",
                                 body: "High 61°, low 44°, 80% chance of rain.\(notToday)"), .rain),
        ]
        for (index, (planned, mood)) in samples.enumerated() {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(5 + index * 3), repeats: false)
            let content = content(for: planned, mood: mood, southernHemisphere: false)
            try? await center.add(UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger))
        }
    }
    #endif

    /// One category per kind, so a stack of them reads "3 more briefings" rather than "3 more
    /// notifications". The format is looked up when shown, so Localizable.stringsdict can pick
    /// "1 more briefing".
    nonisolated static var categories: Set<UNNotificationCategory> {
        Set(NotificationKind.allCases.map { kind in
            UNNotificationCategory(
                identifier: threadIdentifier(kind),
                actions: [],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: nil,
                categorySummaryFormat: NSString.localizedUserNotificationString(forKey: summaryFormat(kind), arguments: nil),
                options: []
            )
        })
    }

    /// The summary for a stack of `kind`; `%u` is how many more there are.
    nonisolated static func summaryFormat(_ kind: NotificationKind) -> String {
        switch kind {
        case .morningBriefing: "%u more briefings"
        case .walkTime: "%u more walk reminders"
        case .rain: "%u more rain alerts"
        }
    }

    /// The same names as Android's notification channels.
    nonisolated static func threadIdentifier(_ kind: NotificationKind) -> String {
        switch kind {
        case .morningBriefing: "morning_briefing"
        case .walkTime: "walk_time"
        case .rain: "rain_alerts"
        }
    }

    private func currentMood(_ weather: CurrentWeather) -> PetMood {
        PetMood.forConditions(
            conditionMain: weather.conditionMain,
            iconCode: weather.iconCode,
            feelsLikeC: weather.units.toCelsius(weather.feelsLike),
            thresholds: RemoteConfigRepository.shared.petWeatherThresholds
        )
    }

    /// A PNG of the pets in `mood`.
    private func petsPicture(mood: PetMood, southernHemisphere: Bool) -> Data? {
        let renderer = ImageRenderer(
            content: PetSceneIcon(mood: mood, southernHemisphere: southernHemisphere)
                .frame(width: 120, height: 120)
        )
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }

    /// Each notification needs its own file: iOS moves an attachment's file into its own store.
    private static func attachment(_ png: Data, identifier: String) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-pets-\(identifier)-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: "pets", url: url)
        } catch {
            return nil
        }
    }

    /// Only this app's weather requests, so anything else queued is left alone.
    private func removePendingNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { id in Self.identifierPrefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }
}
