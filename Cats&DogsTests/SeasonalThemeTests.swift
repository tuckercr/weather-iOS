import XCTest
@testable import Cats_Dogs

@MainActor
final class SeasonalThemeTests: XCTestCase {
    private func date(_ text: String, _ zone: String = "UTC") -> Date {
        let formatter = DateFormatter()
        // Fixed, so the test reads the same on a device set to another calendar or locale.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: zone)
        return formatter.date(from: text)!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let halloweenJSON = """
    [{"id": "halloween", "dates": {"type": "fixed", "month": 10, "day": 31},
      "colors": {"heroDay": "#F5A94E", "heroNight": "#26215C", "inkDay": "#412402", "inkNight": "#EEEDFE",
                 "cardLight": "#FCE9D2", "cardDark": "#3A2A1A", "accentLight": "#A34F0B", "accentDark": "#F5A94E"},
      "captions": {"day": ["Day"], "night": ["Night"]},
      "decorations": ["bats", "witchHat", "turkey"]}]
    """

    func testTheShippedListHasHalloweenThenThanksgiving() {
        XCTAssertEqual(SeasonalThemes.builtIn.map(\.id), ["halloween", "thanksgiving"])
        XCTAssertEqual(SeasonalThemes.builtIn.first?.decorations, [.bats, .witchHat, .bandana, .jackOLantern])
        let thanksgiving = SeasonalThemes.builtIn.last
        XCTAssertEqual(thanksgiving?.decorations, [.autumnLeaves, .pie])
        XCTAssertEqual(thanksgiving?.colors.tileHeaderLight?.rgb, 0x8F3E0E)
        XCTAssertEqual(thanksgiving?.colors.tileHeaderDark?.rgb, 0xF2B27A)
        XCTAssertEqual(thanksgiving?.captions.day, ["Sunny is on crumb patrol under the table."])
        XCTAssertEqual(thanksgiving?.captions.night, ["Too full to move. Misty is napping on the coats."])
    }

    func testThanksgivingIsTheFourthThursdayOfNovember() {
        let themes = SeasonalThemes.builtIn
        let newYork = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(SeasonalThemes.theme(on: date("2026-11-26 09:00", "America/New_York"), timeZone: newYork, in: themes)?.id, "thanksgiving")
        XCTAssertEqual(SeasonalThemes.theme(on: date("2027-11-25 21:00", "America/New_York"), timeZone: newYork, in: themes)?.id, "thanksgiving")
        XCTAssertNil(SeasonalThemes.theme(on: date("2026-11-19 12:00", "America/New_York"), timeZone: newYork, in: themes))
        XCTAssertNil(SeasonalThemes.theme(on: date("2026-11-27 00:00", "America/New_York"), timeZone: newYork, in: themes))
    }

    func testHalloweenIsTheCitysOwn31OctoberAndEndsWithIt() {
        let themes = SeasonalThemes.builtIn
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let la = TimeZone(identifier: "America/Los_Angeles")!
        // 10 AM on 31 October in Los Angeles is already 1 November in Tokyo.
        let instant = date("2026-10-31 10:00", "America/Los_Angeles")
        XCTAssertEqual(SeasonalThemes.theme(on: instant, timeZone: la, in: themes)?.id, "halloween")
        XCTAssertNil(SeasonalThemes.theme(on: instant, timeZone: tokyo, in: themes))
        XCTAssertNil(SeasonalThemes.theme(on: date("2026-11-01 00:00", "America/Los_Angeles"), timeZone: la, in: themes))
        XCTAssertEqual(SeasonalThemes.theme(on: date("2026-10-31 23:59", "America/Los_Angeles"), timeZone: la, in: themes)?.id, "halloween")
    }

    func testARangeIncludesBothEndsAndCanCrossNewYear() {
        let rule = SeasonalTheme.DateRule.range(fromMonth: 12, fromDay: 24, throughMonth: 1, throughDay: 1)
        XCTAssertTrue(rule.contains(date("2026-12-24 08:00"), in: utcCalendar()))
        XCTAssertTrue(rule.contains(date("2027-01-01 08:00"), in: utcCalendar()))
        XCTAssertFalse(rule.contains(date("2026-12-23 08:00"), in: utcCalendar()))
        XCTAssertFalse(rule.contains(date("2027-01-02 08:00"), in: utcCalendar()))
    }

    func testTheNthWeekdayFindsThanksgivingAndTheLastMondayOfMay() {
        let thanksgiving = SeasonalTheme.DateRule.nthWeekday(month: 11, weekday: 5, n: 4)
        XCTAssertTrue(thanksgiving.contains(date("2026-11-26 12:00"), in: utcCalendar()))
        XCTAssertFalse(thanksgiving.contains(date("2026-11-19 12:00"), in: utcCalendar()))
        let memorialDay = SeasonalTheme.DateRule.nthWeekday(month: 5, weekday: 2, n: -1)
        XCTAssertTrue(memorialDay.contains(date("2026-05-25 12:00"), in: utcCalendar()))
        XCTAssertFalse(memorialDay.contains(date("2026-05-18 12:00"), in: utcCalendar()))
    }

    func testAThemeFromRemoteConfigSkipsDecorationsThisVersionCantDraw() throws {
        let theme = try XCTUnwrap(SeasonalThemes.parse(Data(halloweenJSON.utf8))?.first)
        XCTAssertEqual(theme.decorations, [.bats, .witchHat])
        XCTAssertEqual(theme.caption(night: true, on: date("2026-10-31 22:00"), calendar: utcCalendar()), "Night")
    }

    func testAnUnknownDecorationKeepsTheRestOfTheThemeAndTheList() throws {
        let thanksgiving = """
        {"id": "thanksgiving", "dates": {"type": "nthWeekday", "month": 11, "weekday": 5, "n": 4},
         "colors": {"heroDay": "#8C3F14", "heroNight": "#2E1A12", "inkDay": "#FFF2E2", "inkNight": "#F6E3CF",
                    "cardLight": "#F7E6D2", "cardDark": "#3A2416"},
         "captions": {"day": ["Day"], "night": ["Night"]},
         "decorations": ["turkey", "autumnLeaves", "pie", "pilgrimHat"]}
        """
        let list = "[\(halloweenJSON.dropFirst().dropLast()), \(thanksgiving)]"
        let themes = try XCTUnwrap(SeasonalThemes.parse(Data(list.utf8)))
        XCTAssertEqual(themes.map(\.id), ["halloween", "thanksgiving"])
        XCTAssertEqual(themes.last?.decorations, [.autumnLeaves, .pie])
        XCTAssertEqual(themes.last?.captions.day, ["Day"])
        // Nothing this version can draw still leaves the colours and captions.
        let none = thanksgiving.replacingOccurrences(of: #""autumnLeaves", "pie", "#, with: "")
        XCTAssertEqual(try XCTUnwrap(SeasonalThemes.parse(Data("[\(none)]".utf8))?.first).decorations, [])
    }

    // MARK: - What the pets wear

    func testACostumeOnlyReplacesWhatItCovers() {
        let halloween: Set<SceneDecoration> = [.bats, .witchHat, .bandana, .jackOLantern]
        // Sunny keeps his sunglasses beside the witch; the bandana goes round his neck.
        XCTAssertEqual(PetOutfit.accessories(mood: .sunny, decorations: halloween, dark: false), [.sunglasses, .witchHat, .bandana])
        // In the cold the bandana takes Sunny's scarf's place; Misty keeps hers under the hat.
        XCTAssertEqual(PetOutfit.accessories(mood: .cold, decorations: halloween, dark: false), [.catScarf, .witchHat, .bandana])
        // A theme with only the hat leaves Sunny's scarf alone.
        XCTAssertEqual(PetOutfit.accessories(mood: .snow, decorations: [.witchHat], dark: false), [.dogScarf, .catScarf, .witchHat])
        // The umbrella stays over the costumes.
        XCTAssertEqual(PetOutfit.accessories(mood: .rain, decorations: halloween, dark: false), [.umbrella, .witchHat, .bandana])
    }

    func testCostumesComeOffAfterDarkWhateverTheWeather() {
        let halloween: Set<SceneDecoration> = [.bats, .witchHat, .bandana, .jackOLantern]
        XCTAssertEqual(PetOutfit.accessories(mood: .rain, decorations: halloween, dark: true), [.umbrella])
        XCTAssertEqual(PetOutfit.accessories(mood: .cold, decorations: halloween, dark: true), [.dogScarf, .catScarf])
        XCTAssertEqual(PetOutfit.accessories(mood: .night, decorations: halloween, dark: true), [])
        // Thanksgiving has no costumes: the weather's props as on any day.
        XCTAssertEqual(PetOutfit.accessories(mood: .sunny, decorations: [.autumnLeaves, .pie], dark: false), [.sunglasses])
        XCTAssertEqual(PetOutfit.accessories(mood: .fair, decorations: [], dark: false), [])
    }

    func testTilesKeepTheBrandColourWhenAThemeLeavesTheirsOut() throws {
        // This theme still carries the old accent colours, which are ignored.
        let theme = try XCTUnwrap(SeasonalThemes.parse(Data(halloweenJSON.utf8))?.first)
        XCTAssertNil(theme.colors.tileHeaderLight)
        XCTAssertNil(theme.tileHeader)
        XCTAssertNotNil(SeasonalThemes.builtIn.first?.tileHeader)
        XCTAssertEqual(SeasonalThemes.builtIn.first?.colors.tileHeaderLight?.rgb, 0xC25E00)
        XCTAssertEqual(SeasonalThemes.builtIn.first?.colors.tileHeaderDark?.rgb, 0xF5A94E)
    }

    func testAThemeWithCaptionsForOnlyTheDayOrTheNightStillParses() throws {
        let dayOnly = halloweenJSON.replacingOccurrences(of: #""night": ["Night"]"#, with: #""other": []"#)
        let theme = try XCTUnwrap(SeasonalThemes.parse(Data(dayOnly.utf8))?.first)
        XCTAssertEqual(theme.captions, SeasonalTheme.Captions(day: ["Day"], night: []))

        let nightOnly = halloweenJSON.replacingOccurrences(of: #""day": ["Day"], "#, with: "")
        XCTAssertEqual(try XCTUnwrap(SeasonalThemes.parse(Data(nightOnly.utf8))?.first).captions.night, ["Night"])
    }

    func testAThemeThisVersionCantReadIsSkippedAndTheOthersKept() throws {
        let easter = halloweenJSON
            .replacingOccurrences(of: "\"halloween\"", with: "\"easter\"")
            .replacingOccurrences(of: "\"fixed\"", with: "\"easterSunday\"")
            .dropFirst().dropLast()
        let list = "[\(easter), \(halloweenJSON.dropFirst().dropLast())]"

        XCTAssertEqual(try XCTUnwrap(SeasonalThemes.parse(Data(list.utf8))).map(\.id), ["halloween"])
        XCTAssertEqual(SeasonalThemes.parse(Data("[]".utf8)), [])
    }

    func testBadJSONIsRejectedSoTheShippedListStays() {
        XCTAssertNil(SeasonalThemes.parse(Data("{\"id\": 1}".utf8)))
        XCTAssertNil(SeasonalThemes.parse(Data(halloweenJSON.replacingOccurrences(of: "#F5A94E", with: "orange").utf8)))
        XCTAssertNil(SeasonalThemes.parse(Data(halloweenJSON.replacingOccurrences(of: "\"fixed\"", with: "\"easter\"").utf8)))
    }

    func testWhenTwoThemesShareADayTheEarlierWins() throws {
        let one = try XCTUnwrap(SeasonalThemes.parse(Data(halloweenJSON.utf8))?.first)
        let other = SeasonalTheme(id: "autumn", dates: .range(fromMonth: 10, fromDay: 1, throughMonth: 11, throughDay: 30),
                                  colors: one.colors, captions: one.captions, decorations: [])
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(SeasonalThemes.theme(on: date("2026-10-31 12:00"), timeZone: utc, in: [one, other])?.id, "halloween")
        XCTAssertEqual(SeasonalThemes.theme(on: date("2026-10-30 12:00"), timeZone: utc, in: [one, other])?.id, "autumn")
    }
}
