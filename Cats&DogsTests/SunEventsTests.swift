import XCTest
@testable import Cats_Dogs

/// Same cases as Android's `SunEventsTest`.
@MainActor
final class SunEventsTests: XCTestCase {
    /// Midnight UTC; the slots and sun times here are in UTC.
    private let dayStart = fixtureDayStart
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func at(_ hour: Int, _ minute: Int = 0) -> Int { dayStart + hour * 3600 + minute * 60 }

    private func slot(_ epoch: Int) -> HourlySlot {
        HourlySlot(
            timeLabel: String(epoch), iconCode: "01d", description: "Clear", temperature: 20, feelsLike: 20,
            windSpeed: 2, windDeg: 0, humidity: 60, pressure: 1010, units: .metric, epochSeconds: epoch
        )
    }

    private func slots(_ hours: ClosedRange<Int>) -> [HourlySlot] { hours.map { slot(at($0)) } }

    private func ids(_ items: [HourlyStripItem]) -> [String] {
        items.map { item in
            switch item {
            case let .hour(slot): "\((slot.epochSeconds! - dayStart) / 3600)"
            case let .sun(event): event.kind == .sunrise ? "sunrise" : "sunset"
            }
        }
    }

    private func day(sunrise: Int?, sunset: Int?) -> DayForecast {
        DayForecast(
            dateLabel: "day", conditionMain: "Clear", description: "Clear", iconCode: "01d", temperature: 20,
            feelsLike: 20, tempMin: 10, tempMax: 25, units: .metric, hourlySlots: [],
            sunriseEpoch: sunrise, sunsetEpoch: sunset
        )
    }

    private func reading(sunrise: Int?, sunset: Int?) -> CurrentWeather {
        CurrentWeather(
            cityName: "Here", conditionMain: "Clear", description: "Clear", iconCode: "01d", temperature: 20,
            feelsLike: 20, tempMin: 10, tempMax: 25, humidityPercent: 60, pressureHpa: 1010, windSpeed: 2,
            windDeg: 0, visibilityMeters: nil, cloudPercent: 0, units: .metric, sunriseEpoch: sunrise,
            sunsetEpoch: sunset, timezoneOffsetSeconds: 0
        )
    }

    func testASunsetSitsBetweenTheHoursItFallsBetween() {
        let items = HourlyStripItem.strip(
            slots(17...20),
            events: [SunEvent(kind: .sunset, epochSeconds: at(18, 50))],
            now: Date(timeIntervalSince1970: TimeInterval(at(17, 20)))
        )

        XCTAssertEqual(ids(items), ["17", "18", "sunset", "19", "20"])
    }

    func testOneOnTheHourGoesBeforeThatHour() {
        let items = HourlyStripItem.strip(
            slots(5...8),
            events: [SunEvent(kind: .sunrise, epochSeconds: at(7))],
            now: Date(timeIntervalSince1970: TimeInterval(at(5)))
        )

        XCTAssertEqual(ids(items), ["5", "6", "sunrise", "7", "8"])
    }

    func testOnesAlreadyPastOrBeyondTheLastHourAreLeftOut() {
        let items = HourlyStripItem.strip(
            slots(18...22),
            events: [
                // Ten minutes ago, though its hour is still on the strip.
                SunEvent(kind: .sunset, epochSeconds: at(18, 10)),
                // After the last hour starts, so not between two of them.
                SunEvent(kind: .sunrise, epochSeconds: at(22, 30)),
            ],
            now: Date(timeIntervalSince1970: TimeInterval(at(18, 20)))
        )

        XCTAssertEqual(ids(items), ["18", "19", "20", "21", "22"])
    }

    func testTheEveningsStripHasTonightsSunsetAndTomorrowsSunrise() {
        let forecast = [
            day(sunrise: at(7, 2), sunset: at(16, 40)),
            day(sunrise: at(24 + 7, 3), sunset: at(24 + 16, 41)),
        ]
        let events = SunEvent.all(forecast: forecast, weather: reading(sunrise: at(7), sunset: at(16)))
        let items = HourlyStripItem.strip(
            slots(15...32),
            events: events,
            now: Date(timeIntervalSince1970: TimeInterval(at(15, 30)))
        )

        XCTAssertEqual(events.map(\.epochSeconds), [at(7, 2), at(16, 40), at(31, 3), at(40, 41)])
        XCTAssertEqual(ids(items).filter { !$0.allSatisfy(\.isNumber) }, ["sunset", "sunrise"])
        XCTAssertEqual(ids(items)[1...3], ["16", "sunset", "17"])
        XCTAssertEqual(ids(items)[17...19], ["31", "sunrise", "32"])
    }

    func testWithoutTheForecastsSunTimesTheReadingsAreUsed() {
        let events = SunEvent.all(forecast: [day(sunrise: nil, sunset: nil)], weather: reading(sunrise: at(7), sunset: at(16)))

        XCTAssertEqual(events, [SunEvent(kind: .sunrise, epochSeconds: at(7)), SunEvent(kind: .sunset, epochSeconds: at(16))])
        // A sunrise that isn't before the sunset isn't a day.
        XCTAssertEqual(SunEvent.all(forecast: [], weather: reading(sunrise: at(16), sunset: at(16))), [])
        XCTAssertEqual(SunEvent.all(forecast: [], weather: reading(sunrise: nil, sunset: nil)), [])
    }

    func testTheTimeIsShortOnTheStripAndInFullForVoiceOver() {
        let sunset = SunEvent(kind: .sunset, epochSeconds: at(18, 50))

        XCTAssertEqual(sunset.shortTime(timeZone: utc), "6:50")
        XCTAssertEqual(sunset.spoken(timeZone: utc), "Sunset, 6:50 PM")
        XCTAssertEqual(SunEvent(kind: .sunrise, epochSeconds: at(6, 5)).spoken(timeZone: utc), "Sunrise, 6:05 AM")
    }
}
