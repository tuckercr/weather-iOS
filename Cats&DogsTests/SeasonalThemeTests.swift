import XCTest
@testable import Cats_Dogs

final class SeasonalThemeTests: XCTestCase {
    private func date(_ text: String, _ zone: String = "UTC") -> Date {
        let formatter = DateFormatter()
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

    func testTheShippedListHasHalloween() {
        XCTAssertEqual(SeasonalThemes.builtIn.map(\.id), ["halloween"])
        XCTAssertEqual(SeasonalThemes.builtIn.first?.decorations, [.bats, .witchHat, .bandana, .jackOLantern])
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

    func testTileHeadersFallBackToTheAccentWhenAThemeLeavesThemOut() throws {
        let theme = try XCTUnwrap(SeasonalThemes.parse(Data(halloweenJSON.utf8))?.first)
        XCTAssertNil(theme.colors.tileHeaderLight)
        XCTAssertEqual(SeasonalThemes.builtIn.first?.colors.tileHeaderLight?.rgb, 0xC25E00)
        XCTAssertEqual(SeasonalThemes.builtIn.first?.colors.tileHeaderDark?.rgb, 0xF5A94E)
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
