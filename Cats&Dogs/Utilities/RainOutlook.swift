import Foundation

/// The Rain outlook card under the hourly strip: the chance of rain hour by hour from the hour in
/// progress, with a headline, when it dries out and how much falls. The hourly icon is the best
/// model's call and the chance is the ensemble's, so they can disagree; the chart shows the chance.
/// Every chance is read as the hourly strip shows it (`WeatherFormatting.shownRainChance`: to the
/// nearest 10%, 0 under 10%), so a bar never says 55% under an hour the strip shows as 60%, and
/// `minChance` and `likelyChance` weigh the same number. Same rules as Android's `RainOutlook`.
struct RainOutlook: Equatable {
    struct Bar: Equatable {
        /// As in the hourly strip: "3 PM".
        let hour: String
        /// Chance of rain as the hourly strip shows it: 0, or 10...100 in steps of 10.
        let chance: Int
        /// The hour's rain and snow in mm of water; nil when the source doesn't say.
        let amountMm: Double?
        let units: WeatherUnits

        /// Under every other bar, where "3 PM" would crowd its neighbours: "3PM".
        var compactHour: String { hour.replacingOccurrences(of: " ", with: "") }

        /// The amount, from 0.1 mm or 0.01 in: "2.5 mm", "0.1 in". Nil for less, or when unknown.
        var amountText: String? {
            guard let amountMm else { return nil }
            switch units {
            case .metric:
                return amountMm >= 0.1 ? String(localized: "\(RainOutlook.oneDecimal(amountMm)) mm", comment: "Rain amount with its unit") : nil
            case .imperial:
                let inches = amountMm / RainOutlook.mmPerInch
                return inches >= 0.01 ? String(localized: "\(RainOutlook.hundredths(inches)) in", comment: "Rain amount with its unit") : nil
            }
        }

        /// Shown above the bar when it's tapped: "3 PM · 70%", or "3 PM · 70% · 2.5 mm".
        var label: String {
            guard let amountText else { return String(localized: "\(hour) · \(chance)%", comment: "Rain outlook bar label: hour, chance of rain and amount") }
            return String(localized: "\(hour) · \(chance)% · \(amountText)", comment: "Rain outlook bar label: hour, chance of rain and amount")
        }

        /// "3 PM, 70% chance of rain, about 2.5 mm".
        var accessibilityLabel: String {
            if let amountText {
                return String(localized: "\(hour), \(chance)% chance of rain, about \(amountText)", comment: "Rain outlook bar, spoken by VoiceOver: hour, chance of rain and amount")
            }
            return String(localized: "\(hour), \(chance)% chance of rain", comment: "Rain outlook bar, spoken by VoiceOver: hour and chance of rain")
        }
    }

    let headline: String
    let detail: String
    let bars: [Bar]

    /// From this chance the headline says rain is likely rather than a chance.
    static let likelyChance = 50
    /// Less rain than this over the whole chart isn't worth a sentence.
    static let minTotalMm = 0.5
    static let minTotalInches = 0.01
    static let mmPerInch = 25.4

    /// Nil when switched off, with no hours, or when no hour in the chart reaches `minChance`.
    /// - Parameters:
    ///   - slots: the upcoming hours from the one in progress, as the hourly strip shows them.
    ///   - hours: how many of them to chart.
    ///   - nextRainLine: "Rain starting around 3:15 PM" when that line would show. The card takes
    ///     its place, so it becomes the headline.
    static func from(
        _ slots: [HourlySlot],
        enabled: Bool,
        hours: Int,
        minChance: Int,
        units: WeatherUnits,
        nextRainLine: String?
    ) -> RainOutlook? {
        let window = Array(slots.prefix(max(hours, 0)))
        guard enabled, !window.isEmpty else { return nil }
        let chances = window.map { WeatherFormatting.shownRainChance(min(max($0.precipitationChance, 0), 100)) }
        guard let lastWet = chances.lastIndex(where: { $0 >= minChance }),
              let highest = chances.max(),
              let peak = chances.firstIndex(of: highest) else { return nil }

        let headline: String
        if let nextRainLine {
            headline = nextRainLine
        } else {
            let likely = highest >= likelyChance
            let time = window[peak].timeLabel
            headline = switch (likely, peak == 0) {
            case (true, true): String(localized: "Rain likely now", comment: "Rain outlook headline")
            case (true, false): String(localized: "Rain likely around \(time)", comment: "Rain outlook headline. The argument is an hour.")
            case (false, true): String(localized: "A chance of rain now", comment: "Rain outlook headline")
            case (false, false): String(localized: "A chance of rain around \(time)", comment: "Rain outlook headline. The argument is an hour.")
            }
        }

        var sentences = [
            lastWet == window.count - 1
                ? String(localized: "The chance stays up past \(window[lastWet].timeLabel).", comment: "Rain outlook: when the rain ends. The argument is an hour.")
                : String(localized: "Drying out after \(window[lastWet].timeLabel).", comment: "Rain outlook: when the rain ends. The argument is an hour."),
        ]
        let totalMm = window.reduce(0) { $0 + ($1.precipitationMm ?? 0) }
        if let amount = amountSentence(totalMm: totalMm, units: units) {
            sentences.append(amount)
        }

        return RainOutlook(
            headline: headline,
            detail: sentences.joined(separator: " "),
            bars: zip(window, chances).map { slot, chance in
                Bar(hour: slot.timeLabel, chance: chance, amountMm: slot.precipitationMm, units: units)
            }
        )
    }

    /// "About 2.5 mm in all." (one decimal below 10 mm, whole from 10), "About 0.25 inches in all."
    /// or "About 1 inch in all."; nil below 0.5 mm or 0.01 in.
    static func amountSentence(totalMm: Double, units: WeatherUnits) -> String? {
        switch units {
        case .metric:
            guard totalMm >= minTotalMm else { return nil }
            let shown = totalMm < 10 ? oneDecimal(totalMm) : String(Int(totalMm.rounded()))
            return String(localized: "About \(shown) mm in all.", comment: "Rain outlook: how much rain falls in all")
        case .imperial:
            let inches = totalMm / mmPerInch
            guard inches >= minTotalInches else { return nil }
            let shown = hundredths(inches)
            return shown == "1"
                ? String(localized: "About 1 inch in all.", comment: "Rain outlook: how much rain falls in all")
                : String(localized: "About \(shown) inches in all.", comment: "Rain outlook: how much rain falls in all. The argument is a decimal number of inches.")
        }
    }

    /// "2.5". Rounded before formatting, so a half always rounds up (`%.1f` alone rounds to even).
    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", (value * 10).rounded() / 10)
    }

    /// Up to two decimals, without trailing zeros: "0.25", "0.1", "1".
    static func hundredths(_ value: Double) -> String {
        let hundredths = Int((value * 100).rounded())
        let whole = hundredths / 100
        let fraction = hundredths % 100
        if fraction == 0 { return "\(whole)" }
        if fraction.isMultiple(of: 10) { return "\(whole).\(fraction / 10)" }
        return String(format: "%d.%02d", whole, fraction)
    }
}
