import Foundation

/// When to ask for an App Store rating (RATINGS.md). Only the system prompt is used, and only at a
/// happy moment for someone who keeps coming back. Same rules, Remote Config keys and defaults as
/// Android's `domain/ReviewPrompt.kt`.

/// The happy moments that can ask. The raw values are the names in `review_prompt_moments`.
enum ReviewPromptMoment: String, CaseIterable, Sendable {
    /// The walk card says "Now is a great time".
    case greatWalk = "great_walk"
    /// The pets in their sunny or fair mood, by day: for people without a dog too.
    case pleasantWeather = "pleasant_weather"
}

/// The Remote Config values, validated by `RemoteConfigRepository`.
struct ReviewPromptSettings: Equatable, Sendable {
    /// Off for the first release: turned on from the console once it's been tried on a phone.
    var enabled = false
    /// Days since install before asking; never on the day of install, whatever this says.
    var minDaysInstalled = 7
    /// Different days the weather screen was shown before asking.
    var minActiveDays = 5
    var moments: Set<ReviewPromptMoment> = Set(ReviewPromptMoment.allCases)
    /// The wait after a moment, with the screen unchanged, before asking.
    var delaySeconds = 3
    var oncePerVersion = true
    var cooldownDays = 120
    /// Asks in all, ever; 0 means no limit.
    var maxRequests = 3
    /// Whether a visit that started from a notification can ask.
    var onNotificationOpen = false

    static let standard = ReviewPromptSettings()

    static let minDaysInstalledRange = 1 ... 365
    static let minActiveDaysRange = 1 ... 100
    static let delaySecondsRange = 0 ... 30
    static let cooldownDaysRange = 30 ... 365
    static let maxRequestsRange = 0 ... 20

    /// `review_prompt_moments`: comma-separated names; unknown ones are ignored and an empty list
    /// never asks. Nil (not set) gives every moment.
    static func moments(fromList list: String?) -> Set<ReviewPromptMoment> {
        guard let list else { return standard.moments }
        return Set(list.split(separator: ",").compactMap {
            ReviewPromptMoment(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }
}

/// What's saved on the phone between launches.
struct ReviewPromptHistory: Codable, Equatable, Sendable {
    /// Different days the weather screen was shown.
    var activeDays = 0
    /// The start of the last of those days, by the phone's calendar.
    var lastActiveDay: Date?
    /// Times the system prompt was asked for (the stores never say whether it showed).
    var requests = 0
    var lastRequestAt: Date?
    var lastRequestVersion: String?
}

/// This visit to the app: since it last came to the foreground.
struct ReviewPromptVisit: Equatable, Sendable {
    /// Opened by tapping one of the app's notifications.
    var fromNotification = false
    /// Something covered the app in this visit: a permission request or another system alert.
    var interrupted = false
}

enum ReviewPromptPolicy {
    /// `history` with today counted, if it wasn't already.
    static func recordingActiveDay(_ history: ReviewPromptHistory, now: Date, calendar: Calendar) -> ReviewPromptHistory {
        let today = calendar.startOfDay(for: now)
        guard history.lastActiveDay.map({ !calendar.isDate($0, inSameDayAs: today) }) ?? true else { return history }
        var history = history
        history.activeDays += 1
        history.lastActiveDay = today
        return history
    }

    /// `history` after asking now, in app version `version`.
    static func recordingRequest(_ history: ReviewPromptHistory, now: Date, version: String) -> ReviewPromptHistory {
        var history = history
        history.requests += 1
        history.lastRequestAt = now
        history.lastRequestVersion = version
        return history
    }

    /// True when `moment`, on screen now, may ask for a rating.
    static func shouldAsk(
        moment: ReviewPromptMoment,
        history: ReviewPromptHistory,
        settings: ReviewPromptSettings,
        installedAt: Date,
        now: Date,
        version: String,
        visit: ReviewPromptVisit,
        calendar: Calendar
    ) -> Bool {
        guard settings.enabled, settings.moments.contains(moment) else { return false }
        guard !visit.interrupted, !visit.fromNotification || settings.onNotificationOpen else { return false }
        let daysInstalled = days(from: installedAt, to: now, calendar: calendar)
        guard daysInstalled >= max(1, settings.minDaysInstalled) else { return false }
        guard history.activeDays >= settings.minActiveDays else { return false }
        guard settings.maxRequests == 0 || history.requests < settings.maxRequests else { return false }
        if settings.oncePerVersion, history.lastRequestVersion == version { return false }
        if let last = history.lastRequestAt, days(from: last, to: now, calendar: calendar) < settings.cooldownDays {
            return false
        }
        return true
    }

    /// Calendar days from `start` to `end`: 1 from any time yesterday.
    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}
