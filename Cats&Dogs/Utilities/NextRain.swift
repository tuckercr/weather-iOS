import Foundation

/// What the next 2 hours hold, for the one line under the top card: "Rain starting around 3:15 PM".
/// Same rules as Android's `util/NextRain.kt`.
enum NextRain: Equatable {
    case starting(epochSeconds: Int, snow: Bool)
    case stopping(epochSeconds: Int, snow: Bool)
    /// Falling now and for the whole 2 hours.
    case continuing(snow: Bool)

    private static let quarterHourSeconds = 15 * 60
    /// 2 hours ahead, in 15-minute steps.
    private static let quartersAhead = 8
    /// Fewer than this many quarters left (a forecast cached for hours) says too little to go on.
    private static let minQuarters = 4
    /// 0.1 mm in 15 minutes (0.4 mm an hour): drizzle you'd notice. Less is noise.
    private static let wetMm = 0.1

    /// The next 2 hours from the quarter in progress: when rain starts, or when it stops (dry for at
    /// least 30 minutes, so a short gap in a shower doesn't count), or that it keeps on. Nil when it's
    /// dry throughout, or when too little of the forecast is left.
    static func from(_ quarters: [QuarterHour], now: Date) -> NextRain? {
        let nowEpoch = Int(now.timeIntervalSince1970)
        let ahead = Array(quarters.filter { $0.epochSeconds + quarterHourSeconds > nowEpoch }.prefix(quartersAhead))
        guard ahead.count >= minQuarters else { return nil }
        func wet(_ index: Int) -> Bool { ahead.indices.contains(index) && ahead[index].precipitationMm >= wetMm }
        guard wet(0) else {
            guard let start = ahead.indices.first(where: wet) else { return nil }
            return .starting(epochSeconds: ahead[start].epochSeconds, snow: ahead[start].snowfallCm > 0)
        }
        let snow = ahead[0].snowfallCm > 0
        guard let stop = ahead.indices.dropFirst().first(where: { !wet($0) && !wet($0 + 1) }) else {
            return .continuing(snow: snow)
        }
        return .stopping(epochSeconds: ahead[stop].epochSeconds, snow: snow)
    }

    func line(timeZone: TimeZone) -> String {
        switch self {
        case let .starting(epoch, snow):
            let time = WeatherFormatting.epochTime(epoch, timeZone: timeZone)
            return snow
                ? String(localized: "Snow starting around \(time)", comment: "Next rain line. The argument is a time.")
                : String(localized: "Rain starting around \(time)", comment: "Next rain line. The argument is a time.")
        case let .stopping(epoch, snow):
            let time = WeatherFormatting.epochTime(epoch, timeZone: timeZone)
            return snow
                ? String(localized: "Snow stopping around \(time)", comment: "Next rain line. The argument is a time.")
                : String(localized: "Rain stopping around \(time)", comment: "Next rain line. The argument is a time.")
        case let .continuing(snow):
            return snow
                ? String(localized: "Snow for the next 2 hours", comment: "Next rain line")
                : String(localized: "Rain for the next 2 hours", comment: "Next rain line")
        }
    }

    var isSnow: Bool {
        switch self {
        case let .starting(_, snow), let .stopping(_, snow), let .continuing(snow): snow
        }
    }
}
