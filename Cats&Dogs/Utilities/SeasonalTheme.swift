import SwiftUI

/// A look for a day or a stretch of days: the pets' props, the hero card's colours and caption, and
/// a warmer tint on the cards below. Themes are data, not code: the app ships them in
/// SeasonalThemes.json and Remote Config's `seasonal_themes` can replace the whole list, so a new
/// theme (Thanksgiving, say) needs no app update as long as it uses decorations the app can draw.
/// `seasonal_themes_enabled` switches them all off. Today's theme comes from the city's own date,
/// so it ends by itself when its day does. Same format and rules as Android's `SeasonalTheme`.
struct SeasonalTheme: Decodable, Equatable, Identifiable {
    /// Stable, lowercase ("halloween"); the debug override refers to it.
    let id: String
    let dates: DateRule
    let colors: Colors
    let captions: Captions
    /// What the pet scene adds. Names this version can't draw are dropped, so a newer theme still
    /// shows its colours and captions here.
    let decorations: Set<SceneDecoration>

    struct Colors: Decodable, Equatable {
        let heroDay: HexColor
        let heroNight: HexColor
        let inkDay: HexColor
        let inkNight: HexColor
        /// The cards below the hero, in light and dark mode.
        let cardLight: HexColor
        let cardDark: HexColor
        /// Section headers ("HOURLY", "TODAY").
        let accentLight: HexColor
        let accentDark: HexColor
        /// Each tile's icon and label ("Feels like"), in place of the brand blue. Optional: without
        /// them the tiles take `accent`.
        let tileHeaderLight: HexColor?
        let tileHeaderDark: HexColor?
    }

    struct Captions: Decodable, Equatable {
        let day: [String]
        let night: [String]
    }

    /// When a theme applies, in the city's own calendar. JSON: `{"type": "fixed", "month": 10,
    /// "day": 31}`, `{"type": "range", "from": [12, 24], "through": [1, 1]}` or
    /// `{"type": "nthWeekday", "month": 11, "weekday": 5, "n": 4}` (Thanksgiving; weekday 1 is
    /// Sunday, n -1 is the last).
    enum DateRule: Decodable, Equatable {
        case fixed(month: Int, day: Int)
        /// Both ends included; may cross New Year.
        case range(fromMonth: Int, fromDay: Int, throughMonth: Int, throughDay: Int)
        case nthWeekday(month: Int, weekday: Int, n: Int)

        private enum CodingKeys: String, CodingKey { case type, month, day, from, through, weekday, n }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "fixed":
                self = try .fixed(month: c.decode(Int.self, forKey: .month), day: c.decode(Int.self, forKey: .day))
            case "range":
                let from = try c.decode([Int].self, forKey: .from)
                let through = try c.decode([Int].self, forKey: .through)
                guard from.count == 2, through.count == 2 else {
                    throw DecodingError.dataCorruptedError(forKey: .from, in: c, debugDescription: "[month, day]")
                }
                self = .range(fromMonth: from[0], fromDay: from[1], throughMonth: through[0], throughDay: through[1])
            case "nthWeekday":
                self = try .nthWeekday(
                    month: c.decode(Int.self, forKey: .month),
                    weekday: c.decode(Int.self, forKey: .weekday),
                    n: c.decode(Int.self, forKey: .n)
                )
            case let other:
                throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown rule \(other)")
            }
        }

        func contains(_ date: Date, in calendar: Calendar) -> Bool {
            let parts = calendar.dateComponents([.month, .day, .weekday], from: date)
            guard let month = parts.month, let day = parts.day else { return false }
            switch self {
            case let .fixed(m, d):
                return month == m && day == d
            case let .range(fromMonth, fromDay, throughMonth, throughDay):
                let today = month * 100 + day
                let start = fromMonth * 100 + fromDay
                let end = throughMonth * 100 + throughDay
                return start <= end ? (start ... end).contains(today) : today >= start || today <= end
            case let .nthWeekday(m, weekday, n):
                guard month == m, parts.weekday == weekday else { return false }
                if n > 0 { return (day - 1) / 7 + 1 == n }
                // The last one: a week later is next month.
                let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
                return day + 7 > days
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case id, dates, colors, captions, decorations }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        dates = try c.decode(DateRule.self, forKey: .dates)
        colors = try c.decode(Colors.self, forKey: .colors)
        captions = try c.decodeIfPresent(Captions.self, forKey: .captions) ?? Captions(day: [], night: [])
        let names = try c.decodeIfPresent([String].self, forKey: .decorations) ?? []
        decorations = Set(names.compactMap(SceneDecoration.init(rawValue:)))
    }

    init(id: String, dates: DateRule, colors: Colors, captions: Captions, decorations: Set<SceneDecoration>) {
        self.id = id
        self.dates = dates
        self.colors = colors
        self.captions = captions
        self.decorations = decorations
    }

    #if DEBUG
    /// The same theme on every day of the year, for the debug override.
    var everyDay: SeasonalTheme {
        SeasonalTheme(
            id: id,
            dates: .range(fromMonth: 1, fromDay: 1, throughMonth: 12, throughDay: 31),
            colors: colors,
            captions: captions,
            decorations: decorations
        )
    }
    #endif

    func heroBackground(night: Bool) -> Color { (night ? colors.heroNight : colors.heroDay).color }

    func heroInk(night: Bool) -> Color { (night ? colors.inkNight : colors.inkDay).color }

    /// One caption per day, picked by the city's date; nil when the theme has none, so the
    /// weather's own caption shows.
    func caption(night: Bool, on date: Date, calendar: Calendar) -> String? {
        let options = night ? captions.night : captions.day
        guard !options.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        return options[day % options.count]
    }

    var cardBackground: Color { HexColor.adaptive(light: colors.cardLight, dark: colors.cardDark) }

    var accent: Color { HexColor.adaptive(light: colors.accentLight, dark: colors.accentDark) }

    var tileHeader: Color {
        HexColor.adaptive(
            light: colors.tileHeaderLight ?? colors.accentLight,
            dark: colors.tileHeaderDark ?? colors.accentDark
        )
    }
}

/// The extras a theme can ask the pet scene for. Adding one means drawing it in `PetScene` (and
/// Android's); a theme naming one this version doesn't know just goes without it.
enum SceneDecoration: String, CaseIterable, Decodable {
    /// Bats by day; bats and stars after dark.
    case bats
    /// Misty's witch hat, by day.
    case witchHat
    /// Sunny's bandana, by day.
    case bandana
    /// A jack-o'-lantern on Misty's side, lit after dark.
    case jackOLantern
}

/// "#F5A94E" in JSON.
struct HexColor: Decodable, Equatable {
    let rgb: UInt32

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not #RRGGBB: \(text)"))
        }
        rgb = value
    }

    var color: Color { Color(hex: rgb) }

    static func adaptive(light: HexColor, dark: HexColor) -> Color {
        Color(UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark.rgb : light.rgb
            return UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

enum SeasonalThemes {
    /// The list shipped in the app, used until Remote Config has a valid one of its own.
    static let builtIn: [SeasonalTheme] = {
        guard let url = Bundle.main.url(forResource: "SeasonalThemes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return parse(data) ?? []
    }()

    /// Nil when the JSON isn't a list of themes, so a bad Remote Config value falls back to the
    /// built-in list rather than switching every theme off.
    static func parse(_ data: Data) -> [SeasonalTheme]? {
        try? JSONDecoder().decode([SeasonalTheme].self, from: data)
    }

    /// Today's theme in the city's own calendar; nil on an ordinary day. When two cover the same
    /// day, the earlier in the list wins.
    static func theme(on date: Date, timeZone: TimeZone, in themes: [SeasonalTheme]) -> SeasonalTheme? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return themes.first { $0.dates.contains(date, in: calendar) }
    }
}

private struct SeasonalThemeKey: EnvironmentKey {
    static let defaultValue: SeasonalTheme? = nil
}

extension EnvironmentValues {
    /// Today's theme for the city on screen, or nil. Set by `CurrentWeatherView`.
    var seasonalTheme: SeasonalTheme? {
        get { self[SeasonalThemeKey.self] }
        set { self[SeasonalThemeKey.self] = newValue }
    }
}

extension Color {
    /// A card's background, warmed by today's theme when there is one.
    static func card(_ theme: SeasonalTheme?) -> Color { theme?.cardBackground ?? .surfaceVariant }
}
