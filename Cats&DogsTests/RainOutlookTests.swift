import XCTest
@testable import Cats_Dogs

@MainActor
final class RainOutlookTests: XCTestCase {
    /// Hourly slots from 3 PM with these chances, and amounts when given.
    private func slots(_ chances: [Int], mm: [Double?] = []) -> [HourlySlot] {
        chances.enumerated().map { i, chance in
            let hour = (15 + i) % 24
            var slot = HourlySlot(
                timeLabel: "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")",
                iconCode: "10d", description: "Light rain", temperature: 15, feelsLike: 14,
                windSpeed: 3, windDeg: 180, humidity: 80, pressure: 1012, units: .metric
            )
            slot.precipitationChance = chance
            slot.precipitationMm = mm.indices.contains(i) ? mm[i] : nil
            slot.epochSeconds = fixtureDayStart + (15 + i) * 3600
            return slot
        }
    }

    private func outlook(
        _ slots: [HourlySlot],
        enabled: Bool = true,
        hours: Int = 10,
        minChance: Int = 20,
        units: WeatherUnits = .metric,
        nextRainLine: String? = nil
    ) -> RainOutlook? {
        RainOutlook.from(slots, enabled: enabled, hours: hours, minChance: minChance, units: units, nextRainLine: nextRainLine)
    }

    // MARK: - When it shows

    func testHiddenWhenNoHourReachesTheMinimumChance() {
        XCTAssertNil(outlook(slots([10, 14, 5, 0, 0, 0, 0, 0, 0, 0])))
        XCTAssertNotNil(outlook(slots([10, 20, 5, 0, 0, 0, 0, 0, 0, 0])))
        XCTAssertNil(outlook(slots([10, 20, 5]), minChance: 21))
    }

    func testHiddenWhenSwitchedOff() {
        XCTAssertNil(outlook(slots([80, 90, 70]), enabled: false))
    }

    func testHiddenWithNoHours() {
        XCTAssertNil(outlook([]))
    }

    func testOnlyTheChartedHoursCount() {
        // Rain in the 11th hour doesn't show a 10-hour chart, but does an 11-hour one.
        let chances = Array(repeating: 0, count: 10) + [80]

        XCTAssertNil(outlook(slots(chances), hours: 10))
        XCTAssertEqual(outlook(slots(chances), hours: 11)?.bars.count, 11)
    }

    func testTheChartCoversTheRemoteConfigHoursOrAsManyAsThereAre() {
        let day = slots(Array(repeating: 40, count: 24))

        XCTAssertEqual(outlook(day, hours: 6)?.bars.map(\.hour), ["3 PM", "4 PM", "5 PM", "6 PM", "7 PM", "8 PM"])
        XCTAssertEqual(outlook(day, hours: 12)?.bars.count, 12)
        XCTAssertEqual(outlook(slots([40, 40, 40]), hours: 10)?.bars.count, 3)
    }

    // MARK: - Headline

    func testRainLikelyNowWhenTheFirstHourIsThePeak() {
        XCTAssertEqual(outlook(slots([70, 50, 30]))?.headline, "Rain likely now")
    }

    func testRainLikelyAroundTheFirstHourWithTheHighestChance() {
        XCTAssertEqual(outlook(slots([20, 40, 70, 70, 30]))?.headline, "Rain likely around 5 PM")
        // 50% counts as likely.
        XCTAssertEqual(outlook(slots([20, 50, 30]))?.headline, "Rain likely around 4 PM")
    }

    func testAChanceOfRainBelowFifty() {
        XCTAssertEqual(outlook(slots([40, 30, 20]))?.headline, "A chance of rain now")
        XCTAssertEqual(outlook(slots([30, 44, 20]))?.headline, "A chance of rain around 4 PM")
    }

    func testTheNextRainLineBecomesTheHeadline() {
        let shown = outlook(slots([20, 40, 70]), nextRainLine: "Rain starting around 3:15 PM")

        XCTAssertEqual(shown?.headline, "Rain starting around 3:15 PM")
    }

    // MARK: - The chance as the hourly strip shows it

    func testTheMinimumChanceWeighsTheChanceAsShown() {
        // 25% shows as 30%, so it reaches a 30% minimum; 24% shows as 20% and doesn't.
        XCTAssertNotNil(outlook(slots([25, 0, 0]), minChance: 30))
        XCTAssertNil(outlook(slots([24, 0, 0]), minChance: 30))
        XCTAssertEqual(outlook(slots([60, 25, 24]), minChance: 30)?.detail, "Drying out after 4 PM.")
    }

    func testRainIsLikelyAtTheChanceAsShown() {
        // 45% shows as 50%; 44% shows as 40%.
        XCTAssertEqual(outlook(slots([20, 45, 30]))?.headline, "Rain likely around 4 PM")
        XCTAssertEqual(outlook(slots([20, 44, 30]))?.headline, "A chance of rain around 4 PM")
    }

    func testThePeakIsTheFirstHourAtTheHighestChanceAsShown() {
        // 65% and 70% both show as 70%, so the earlier hour is the peak.
        XCTAssertEqual(outlook(slots([20, 65, 70]))?.headline, "Rain likely around 4 PM")
    }

    func testABarShowsTheChanceAsTheHourlyStripDoes() {
        let bars = outlook(slots([55, 5, 100, 94], mm: [2.46, nil, nil, nil]))?.bars

        XCTAssertEqual(bars?.map(\.chance), [60, 0, 100, 90])
        XCTAssertEqual(bars?.first?.label, "3 PM · 60% · 2.5 mm")
        XCTAssertEqual(bars?.first?.accessibilityLabel, "3 PM, 60% chance of rain, about 2.5 mm")
        XCTAssertEqual(bars?[1].label, "4 PM · 0%")
        // The amount is the forecast's, unrounded.
        XCTAssertEqual(bars?.first?.amountMm, 2.46)
    }

    // MARK: - Detail

    func testDryingOutAfterTheLastHourAtTheMinimumChance() {
        XCTAssertEqual(outlook(slots([60, 40, 20, 10, 50, 0]), hours: 6)?.detail, "Drying out after 7 PM.")
        XCTAssertEqual(outlook(slots([60, 40, 20, 10, 0, 0]), hours: 6)?.detail, "Drying out after 5 PM.")
    }

    func testTheChanceStaysUpPastTheLastHourCharted() {
        XCTAssertEqual(outlook(slots([0, 0, 0, 0, 0, 30]), hours: 6)?.detail, "The chance stays up past 8 PM.")
        // Past the last hour there is, when there are fewer than the chart's hours.
        XCTAssertEqual(outlook(slots([10, 40]), hours: 10)?.detail, "The chance stays up past 4 PM.")
    }

    func testTheAmountSentenceFollowsTheWetSentence() {
        let shown = outlook(slots([60, 40, 10], mm: [1.2, 1.3, nil]))

        XCTAssertEqual(shown?.detail, "Drying out after 4 PM. About 2.5 mm in all.")
    }

    func testOnlyTheChartedHoursAmountsAreAdded() {
        let shown = outlook(slots([60, 40, 10, 0, 0, 0, 0], mm: [1, 1, 0, 0, 0, 0, 5]), hours: 6)

        XCTAssertEqual(shown?.detail, "Drying out after 4 PM. About 2.0 mm in all.")
    }

    func testNoAmountSentenceWhenTheAmountsAreUnknown() {
        XCTAssertEqual(outlook(slots([60, 40, 10]))?.detail, "Drying out after 4 PM.")
    }

    func testMetricAmountFromHalfAMillimetreWithOneDecimalBelowTen() {
        XCTAssertNil(RainOutlook.amountSentence(totalMm: 0.49, units: .metric))
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 0.5, units: .metric), "About 0.5 mm in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 2.46, units: .metric), "About 2.5 mm in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 2.25, units: .metric), "About 2.3 mm in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 9.9, units: .metric), "About 9.9 mm in all.")
    }

    func testMetricAmountInWholeMillimetresFromTen() {
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 10, units: .metric), "About 10 mm in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 12.4, units: .metric), "About 12 mm in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 12.5, units: .metric), "About 13 mm in all.")
    }

    func testImperialAmountFromAHundredthOfAnInchWithoutTrailingZeros() {
        XCTAssertNil(RainOutlook.amountSentence(totalMm: 0.2, units: .imperial)) // 0.008 in
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 0.3, units: .imperial), "About 0.01 inches in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 2.54, units: .imperial), "About 0.1 inches in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 6.35, units: .imperial), "About 0.25 inches in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 38.1, units: .imperial), "About 1.5 inches in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 50.8, units: .imperial), "About 2 inches in all.")
    }

    func testOneInchIsSingularWhenItRoundsToExactlyOne() {
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 25.4, units: .imperial), "About 1 inch in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 25.3, units: .imperial), "About 1 inch in all.") // 0.996 in
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 25, units: .imperial), "About 0.98 inches in all.")
        XCTAssertEqual(RainOutlook.amountSentence(totalMm: 25.7, units: .imperial), "About 1.01 inches in all.")
    }

    func testImperialDetailUsesInches() {
        let shown = outlook(slots([60, 40, 10], mm: [3.2, 3.15, 0]), units: .imperial)

        XCTAssertEqual(shown?.detail, "Drying out after 4 PM. About 0.25 inches in all.")
    }

    // MARK: - Bars

    func testABarForEachHourWithItsChanceAndAmount() {
        let bars = outlook(slots([20, 70, 0], mm: [0.05, 2.46, nil]))?.bars

        XCTAssertEqual(bars?.map(\.hour), ["3 PM", "4 PM", "5 PM"])
        XCTAssertEqual(bars?.map(\.chance), [20, 70, 0])
        XCTAssertEqual(bars?.map(\.amountMm), [0.05, 2.46, nil])
        XCTAssertEqual(bars?.map(\.compactHour), ["3PM", "4PM", "5PM"])
    }

    func testTheBarLabelShowsTheAmountFromATenthOfAMillimetre() {
        let bars = outlook(slots([20, 70, 40, 30], mm: [0.05, 2.46, 0.1, nil]))?.bars

        XCTAssertEqual(bars?.map(\.label), ["3 PM · 20%", "4 PM · 70% · 2.5 mm", "5 PM · 40% · 0.1 mm", "6 PM · 30%"])
    }

    func testTheBarLabelShowsTheAmountFromAHundredthOfAnInch() {
        let bars = outlook(slots([20, 70, 40], mm: [0.2, 2.54, 6.35]), units: .imperial)?.bars

        XCTAssertEqual(bars?.map(\.label), ["3 PM · 20%", "4 PM · 70% · 0.1 in", "5 PM · 40% · 0.25 in"])
    }

    func testEachBarIsReadAsItsHourChanceAndAmount() {
        let bars = outlook(slots([20, 70], mm: [0, 2.46]))?.bars

        XCTAssertEqual(bars?.map(\.accessibilityLabel), [
            "3 PM, 20% chance of rain",
            "4 PM, 70% chance of rain, about 2.5 mm",
        ])
    }
}
