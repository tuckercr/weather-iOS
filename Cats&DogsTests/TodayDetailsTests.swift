import XCTest
@testable import Cats_Dogs

@MainActor
final class TodayDetailsTests: XCTestCase {
    func testVisibilityBands() {
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 10_000), .excellent)
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 9_999), .good)
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 5_000), .good)
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 4_999), .moderate)
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 1_000), .moderate)
        XCTAssertEqual(TodayDetails.visibilityBand(meters: 999), .poor)
    }

    func testVisibilityAtThe10KmCapHasNoNumberSoItNeverReads6Point2Miles() {
        XCTAssertNil(TodayDetails.visibilityDistance(meters: 10_000, inMiles: true))
        XCTAssertNil(TodayDetails.visibilityDistance(meters: 10_000, inMiles: false))
    }

    func testVisibilityIsWholeMilesOrKilometresFrom1KmUp() {
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 6_500, inMiles: true), "4 mi")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 9_999, inMiles: true), "6 mi")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 1_000, inMiles: true), "1 mi")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 6_500, inMiles: false), "7 km")
    }

    func testUnder1KmVisibilityIsTenthsOfAMileOrMetresToTheNearest100() {
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 800, inMiles: true), "0.5 mi")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 20, inMiles: true), "0.1 mi")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 780, inMiles: false), "800 m")
        XCTAssertEqual(TodayDetails.visibilityDistance(meters: 20, inMiles: false), "100 m")
    }

    func testObscuredSkiesAreNamedForWhatsInTheAirTheRestByCloudCover() {
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Fog", cloudPercent: 100, iconCode: "50d"), .fog)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Mist", cloudPercent: 100, iconCode: "50d"), .mist)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Smoke", cloudPercent: 0, iconCode: "50d"), .smoke)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Sand", cloudPercent: 0, iconCode: "50d"), .dust)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clear", cloudPercent: 0, iconCode: "01d"), .clear)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clouds", cloudPercent: 10, iconCode: "02d"), .clear)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clouds", cloudPercent: 50, iconCode: "03d"), .partlyCloudy)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clouds", cloudPercent: 84, iconCode: "04d"), .mostlyCloudy)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Rain", cloudPercent: 100, iconCode: "10d"), .overcast)
    }

    func testWithoutACloudCoverTheIconDecides() {
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clear", cloudPercent: nil, iconCode: "01n"), .clear)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clouds", cloudPercent: nil, iconCode: "02d"), .partlyCloudy)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Clouds", cloudPercent: nil, iconCode: "03d"), .mostlyCloudy)
        XCTAssertEqual(TodayDetails.skyCondition(conditionMain: "Rain", cloudPercent: nil, iconCode: "10d"), .overcast)
    }

    func testPavementBandsSitOnFivePaws() {
        let steps: [(TodayDetails.PavementBand, Int)] = [
            (.icy, 0), (.freezing, 0), (.safe, 1), (.pavementOK, 1), (.warm, 2), (.tooHot, 3), (.dangerous, 4),
        ]
        for (band, step) in steps {
            XCTAssertEqual(band.pawScaleStep, step, "\(band)")
        }
    }

    func testPavementBandsFollowTheWalkThresholds() {
        let t = PetWeatherThresholds.standard
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 57.2, groundWet: false, feelsLikeC: 20, thresholds: t), .dangerous)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 57.1, groundWet: false, feelsLikeC: 20, thresholds: t), .tooHot)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 52, groundWet: false, feelsLikeC: 20, thresholds: t), .tooHot)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 51.9, groundWet: false, feelsLikeC: 20, thresholds: t), .warm)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 45, groundWet: false, feelsLikeC: 20, thresholds: t), .warm)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 44.9, groundWet: false, feelsLikeC: 20, thresholds: t), .safe)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 0, groundWet: true, feelsLikeC: 0.1, thresholds: t), .safe)
    }

    func testPavementIsOnlySafeForPawsWhenTheAirIsToo() {
        let t = PetWeatherThresholds.standard
        // A muggy night: the pavement has cooled, but it feels 31C, past the pets' 30C limit.
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 29, groundWet: false, feelsLikeC: 31, thresholds: t), .pavementOK)
        // Just above freezing, but -4C in the wind.
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 2, groundWet: false, feelsLikeC: -4, thresholds: t), .pavementOK)
        // Too-hot pavement still says so, whatever the air.
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: 53, groundWet: false, feelsLikeC: 31, thresholds: t), .tooHot)
    }

    func testFeelsLikeBandsMatchThePetsMoodsAndTheWalkComfortRange() {
        let t = PetWeatherThresholds.standard
        func band(_ c: Double) -> TodayDetails.FeelsLikeBand { TodayDetails.feelsLikeBand(feelsLikeC: c, thresholds: t) }
        XCTAssertEqual(band(-5), .cold)
        XCTAssertEqual(band(0), .cold)
        XCTAssertEqual(band(0.1), .chilly)
        XCTAssertEqual(band(2.9), .chilly)
        XCTAssertEqual(band(3), .mild)
        XCTAssertEqual(band(27), .mild)
        XCTAssertEqual(band(27.1), .warm)
        XCTAssertEqual(band(29.9), .warm)
        XCTAssertEqual(band(30), .hot)
        XCTAssertEqual(TodayDetails.FeelsLikeBand.allCases.map(\.name), ["Cold", "Chilly", "Mild", "Warm", "Hot"])
    }

    func testTheFeelsLikeMarkMovesAcrossFiveEqualBands() {
        let t = PetWeatherThresholds.standard
        func position(_ c: Double) -> Double { TodayDetails.feelsLikeBarPosition(feelsLikeC: c, thresholds: t) }
        XCTAssertEqual(position(-10), 0, accuracy: 0.001)
        XCTAssertEqual(position(-30), 0, accuracy: 0.001, "Stays at the end past -10 C")
        XCTAssertEqual(position(0), 0.2, accuracy: 0.001)
        XCTAssertEqual(position(1.5), 0.3, accuracy: 0.001)
        XCTAssertEqual(position(15), 0.5, accuracy: 0.001)
        XCTAssertEqual(position(27), 0.6, accuracy: 0.001)
        XCTAssertEqual(position(30), 0.8, accuracy: 0.001)
        // Singapore feeling 89 F.
        XCTAssertEqual(position(31.67), 0.833, accuracy: 0.001)
        XCTAssertEqual(position(40), 1, accuracy: 0.001)
        XCTAssertEqual(position(48), 1, accuracy: 0.001, "Stays at the end past 40 C")
    }

    func testTheFeelsLikeMarkKeepsInsideItsBandWhenTheComfortRangePassesThePetsLimits() {
        var t = PetWeatherThresholds.standard
        t.comfortC = -5 ... 35
        // Chilly and Warm are empty: the pets' limits come first.
        XCTAssertEqual(TodayDetails.feelsLikeBand(feelsLikeC: -2, thresholds: t), .cold)
        XCTAssertEqual(TodayDetails.feelsLikeBand(feelsLikeC: 1, thresholds: t), .mild)
        XCTAssertEqual(TodayDetails.feelsLikeBand(feelsLikeC: 32, thresholds: t), .hot)
        XCTAssertEqual(TodayDetails.feelsLikeBarPosition(feelsLikeC: -2, thresholds: t), 0.16, accuracy: 0.001)
        XCTAssertEqual(TodayDetails.feelsLikeBarPosition(feelsLikeC: 15, thresholds: t), 0.5, accuracy: 0.001)
        XCTAssertEqual(TodayDetails.feelsLikeBarPosition(feelsLikeC: 32, thresholds: t), 0.84, accuracy: 0.001)
    }

    func testTheFeelsLikeGapComparesTheTwoNumbersAsShown() {
        XCTAssertEqual(TodayDetails.feelsLikeGap(feelsLike: 89.4, temperature: 81.2), "8° warmer than it is")
        XCTAssertEqual(TodayDetails.feelsLikeGap(feelsLike: 28, temperature: 34), "6° cooler than it is")
        // 81.6 and 83.4 show as 82 and 83.
        XCTAssertEqual(TodayDetails.feelsLikeGap(feelsLike: 83.4, temperature: 81.6), "Same as it is")
        XCTAssertEqual(TodayDetails.feelsLikeGap(feelsLike: 20, temperature: 21), "Same as it is")
        XCTAssertEqual(TodayDetails.feelsLikeGap(feelsLike: 22, temperature: 20), "2° warmer than it is")
    }

    func testBelowFreezingThePavementIsOnlyIcyAfterRainOrSnow() {
        let t = PetWeatherThresholds.standard
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: -0.1, groundWet: true, feelsLikeC: -3, thresholds: t), .icy)
        XCTAssertEqual(TodayDetails.pavementBand(pavementC: -0.1, groundWet: false, feelsLikeC: -3, thresholds: t), .freezing)
    }

    func testDewPoint() throws {
        XCTAssertEqual(try XCTUnwrap(TodayDetails.dewPointC(temperatureC: 8.3, humidityPercent: 86)), 6.0, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(TodayDetails.dewPointC(temperatureC: 20, humidityPercent: 100)), 20, accuracy: 0.01)
        XCTAssertNil(TodayDetails.dewPointC(temperatureC: 20, humidityPercent: 0))
    }

    func testMistyFluffsUpAsTheDewPointRisesAndCracklesInDryAir() {
        func level(_ dewC: Double?, _ humidity: Int = 60) -> TodayDetails.FluffLevel {
            TodayDetails.fluffLevel(dewPointC: dewC, humidityPercent: humidity)
        }
        XCTAssertEqual(level(nil, 0), .dry)
        XCTAssertEqual(level(5, 34), .dry)
        XCTAssertEqual(level(5, 35), .comfy)
        XCTAssertEqual(level(15.9), .comfy)
        XCTAssertEqual(level(16), .sticky)
        XCTAssertEqual(level(18), .muggy)
        XCTAssertEqual(level(20.9), .muggy)
        XCTAssertEqual(level(21), .soupy)
        // Muggy wins over dry: 30% at 38 °C still has a dew point of about 18 °C.
        XCTAssertEqual(level(18.2, 30), .muggy)
        // 87% at 9.5 °C (London tonight) is damp, not dry: a dew point of about 7.5 °C.
        XCTAssertEqual(level(TodayDetails.dewPointC(temperatureC: 9.5, humidityPercent: 87), 87), .comfy)
        // 62% at 20 °C is a dew point of about 12.5 °C; 85% at 27 °C about 24 °C.
        XCTAssertEqual(level(TodayDetails.dewPointC(temperatureC: 20, humidityPercent: 62), 62), .comfy)
        XCTAssertEqual(level(TodayDetails.dewPointC(temperatureC: 27, humidityPercent: 85), 85), .soupy)
    }

    func testMistysLinesMentionPantingOnlyWithADog() {
        XCTAssertEqual(TodayDetails.fluffLine(.dry, hasDog: true), "Dry air, static fur")
        XCTAssertEqual(TodayDetails.fluffLine(.comfy, hasDog: true), "Misty's fur is behaving")
        XCTAssertEqual(TodayDetails.fluffLine(.muggy, hasDog: true), "Puffy fur, panting pup")
        XCTAssertEqual(TodayDetails.fluffLine(.muggy, hasDog: false), "Misty's getting puffy")
        XCTAssertEqual(TodayDetails.fluffLine(.soupy, hasDog: false), "Misty has gone full floof")
        for level in TodayDetails.FluffLevel.allCases {
            XCTAssertFalse(TodayDetails.fluffLine(level, hasDog: true).isEmpty)
        }
    }

    func testCompassPoints() {
        XCTAssertEqual(TodayDetails.compassPoint(0), "N")
        XCTAssertEqual(TodayDetails.compassPoint(22), "N")
        XCTAssertEqual(TodayDetails.compassPoint(23), "NE")
        XCTAssertEqual(TodayDetails.compassPoint(225), "SW")
        XCTAssertEqual(TodayDetails.compassPoint(359), "N")
    }

    func testTheWindsockLiftsWithTheWindUntilAStrongBreeze() {
        XCTAssertEqual(TodayDetails.windsockDroopDegrees(speed: 0, units: .metric), 75)
        XCTAssertEqual(TodayDetails.windsockDroopDegrees(speed: 5.4, units: .metric), 37.5, accuracy: 0.01)
        XCTAssertEqual(TodayDetails.windsockDroopDegrees(speed: 14, units: .imperial), 31.6, accuracy: 0.1)
        XCTAssertEqual(TodayDetails.windsockDroopDegrees(speed: 10.8, units: .metric), 0)
        XCTAssertEqual(TodayDetails.windsockDroopDegrees(speed: 40, units: .imperial), 0)
    }

    func testTheWindNoteGivesTheDirectionAndGustsThatStandOut() {
        XCTAssertEqual(TodayDetails.windNote(speed: 0.2, deg: 225, gust: 9, units: .imperial).text, "Calm")
        let breeze = TodayDetails.windNote(speed: 14, deg: 225, gust: 24, units: .imperial)
        XCTAssertEqual(breeze.text, "From the SW, gusts 24")
        XCTAssertEqual(breeze.spoken, "From the southwest, moderate breeze, gusts 24 mph")
        // 4 mph above the wind is nothing to mention; 5 is.
        XCTAssertEqual(TodayDetails.windNote(speed: 10, deg: 270, gust: 14, units: .imperial).text, "From the W")
        XCTAssertEqual(TodayDetails.windNote(speed: 10, deg: 270, gust: 15, units: .imperial).text, "From the W, gusts 15")
        XCTAssertEqual(TodayDetails.windNote(speed: 10, deg: 270, gust: nil, units: .imperial).text, "From the W")
        XCTAssertEqual(TodayDetails.windNote(speed: 3, deg: 0, gust: 6.4, units: .metric).text, "From the N, gusts 6.4")
        XCTAssertEqual(TodayDetails.windNote(speed: 3, deg: 0, gust: 5, units: .metric).text, "From the N")
    }

    func testWindForceUsesTheBeaufortScaleInEitherUnit() {
        XCTAssertEqual(TodayDetails.windForce(speed: 0.2, units: .metric), 0)
        XCTAssertEqual(TodayDetails.windForce(speed: 1, units: .imperial), 1)
        XCTAssertEqual(TodayDetails.windForce(speed: 1.5, units: .metric), 1)
        XCTAssertEqual(TodayDetails.windForce(speed: 1.6, units: .metric), 2)
        XCTAssertEqual(TodayDetails.windForce(speed: 10, units: .imperial), 3)
        XCTAssertEqual(TodayDetails.windForce(speed: 20, units: .metric), 8)
        XCTAssertEqual(TodayDetails.windForce(speed: 40, units: .metric), 12)
        XCTAssertEqual(TodayDetails.windForceNames[1], "Light wind")
        XCTAssertEqual(TodayDetails.windForceNames.count, 13)
    }

    func testDaylightBeforeSunriseDuringTheDayAndAfterSunset() {
        let sunrise = 1_000
        let sunset = 1_000 + 10 * 3600

        XCTAssertEqual(TodayDetails.daylight(now: sunrise - 600, sunrise: sunrise, sunset: sunset), .beforeSunrise(secondsUntil: 600))
        XCTAssertEqual(
            TodayDetails.daylight(now: sunset - 2 * 3600, sunrise: sunrise, sunset: sunset),
            .daytime(secondsLeft: 2 * 3600, fraction: 0.8)
        )
        XCTAssertEqual(TodayDetails.daylight(now: sunset, sunrise: sunrise, sunset: sunset), .afterSunset)
    }

    func testDurations() {
        XCTAssertEqual(TodayDetails.duration(seconds: 45 * 60), "45 min")
        XCTAssertEqual(TodayDetails.duration(seconds: 2 * 3600), "2 h")
        XCTAssertEqual(TodayDetails.duration(seconds: 2 * 3600 + 15 * 60 + 30), "2 h 15 min")
    }

    func testNumbersKeepTheirUnitsOnTheSameLine() {
        XCTAssertEqual(TodayDetails.keepUnitsTogether("Actual 56.3 °F"), "Actual 56.3\u{00A0}°F")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("3.4 mph"), "3.4\u{00A0}mph")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("5.0 m/s"), "5.0\u{00A0}m/s")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("Clear · Good visibility, 4 mi"), "Clear · Good visibility, 4\u{00A0}mi")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("800 m"), "800\u{00A0}m")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("6:45 PM"), "6:45\u{00A0}PM")
        XCTAssertEqual(TodayDetails.keepUnitsTogether("7:53\u{202F}AM"), "7:53\u{00A0}AM")
        // Words after numbers are left alone.
        XCTAssertEqual(TodayDetails.keepUnitsTogether("2 h 15 min left"), "2 h 15 min left")
    }

    func testCompassPointsAreSpokenAsWords() {
        XCTAssertEqual(TodayDetails.spokenCompassPoint(0), "north")
        XCTAssertEqual(TodayDetails.spokenCompassPoint(315), "northwest")
        XCTAssertEqual(TodayDetails.spokenCompassPoint(359), "north")
    }

    private func today(low: Double, high: Double) -> DayForecast {
        DayForecast(
            dateLabel: "Fri, Oct 30", conditionMain: "Clear", description: "clear", iconCode: "01d",
            temperature: 18, feelsLike: 18, tempMin: low, tempMax: high, units: .metric, hourlySlots: []
        )
    }

    func testHighAndLowComeFromTodaysForecastNotTheCurrentReading() async {
        let current = await makeCurrentWeather(temperature: 18)

        let highLow = TodayDetails.highLow(current: current, today: today(low: 12, high: 23))

        XCTAssertEqual(highLow.high, 23)
        XCTAssertEqual(highLow.low, 12)
    }

    func testHighAndLowTakeInTheTemperatureNow() async {
        let current = await makeCurrentWeather(temperature: 25)

        let highLow = TodayDetails.highLow(current: current, today: today(low: 12, high: 23))

        XCTAssertEqual(highLow.high, 25)
        XCTAssertEqual(highLow.low, 12)
    }

    func testWithoutTodaysForecastTheCurrentReadingIsUsed() async {
        let current = await makeCurrentWeather(temperature: 18)

        let highLow = TodayDetails.highLow(current: current, today: nil)

        XCTAssertEqual(highLow.high, current.tempMax)
        XCTAssertEqual(highLow.low, current.tempMin)
    }

    // MARK: - UV

    private func uvSlot(_ uv: Double, at epoch: Int) -> HourlySlot {
        HourlySlot(
            timeLabel: "1 PM",
            iconCode: "01d",
            description: "Clear sky",
            temperature: 25,
            feelsLike: 25,
            windSpeed: 2,
            windDeg: 0,
            humidity: 40,
            pressure: 1013,
            units: .metric,
            precipitationChance: 0,
            uvIndex: uv,
            epochSeconds: epoch
        )
    }

    func testTheUVTileSaysWhenTodaysPeakIsWhileItsAhead() {
        let peak = uvSlot(7.6, at: 13 * 3600)
        let line = TodayDetails.uvLine(peak: peak, now: Date(timeIntervalSince1970: 10 * 3600), hasDog: true)
        XCTAssertEqual(line.text, "Peak 8 at 1 PM")
        XCTAssertFalse(line.isPetLine)
    }

    func testFromAHighPeakOnTheUVTileMindsPaleNosesWithADog() {
        let peak = uvSlot(7, at: 13 * 3600)
        let during = Date(timeIntervalSince1970: 13 * 3600 + 600)
        let after = Date(timeIntervalSince1970: 16 * 3600)
        XCTAssertEqual(TodayDetails.uvLine(peak: peak, now: after, hasDog: true).text, "Shade for pale noses")
        XCTAssertTrue(TodayDetails.uvLine(peak: peak, now: after, hasDog: true).isPetLine)
        XCTAssertEqual(TodayDetails.uvLine(peak: peak, now: during, hasDog: false).text, "At today's peak")
        XCTAssertEqual(TodayDetails.uvLine(peak: peak, now: after, hasDog: false).text, "Easing off now")
        XCTAssertEqual(TodayDetails.uvLine(peak: uvSlot(4, at: 13 * 3600), now: after, hasDog: true).text, "Easing off now")
    }

    func testEveryTileShowsByDefaultExceptUV() {
        let switches = TodayTileSwitches()
        XCTAssertTrue(switches.feelsLike && switches.wind && switches.humidity && switches.pawCheck && switches.daylight && switches.sky)
        XCTAssertFalse(switches.uv)
    }
}
