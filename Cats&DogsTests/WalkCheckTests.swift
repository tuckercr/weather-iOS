import XCTest
@testable import Cats_Dogs

@MainActor
final class WalkCheckTests: XCTestCase {
    private let thresholds = PetWeatherThresholds.standard

    private func check(
        _ slot: HourlySlot,
        feelsLikeC: Double? = nil,
        conditionNow: String? = nil,
        windForceNow: Int? = nil,
        gustForceNow: Int? = nil,
        darkNow: Bool = false,
        hasDog: Bool = true,
        thresholds: PetWeatherThresholds? = nil
    ) -> WalkCheck {
        WalkConditions.check(
            slot,
            thresholds: thresholds ?? .standard,
            feelsLikeC: feelsLikeC,
            conditionNow: conditionNow,
            windForceNow: windForceNow,
            gustForceNow: gustForceNow,
            darkNow: darkNow,
            hasDog: hasDog
        )
    }

    // MARK: - The verdict

    func testAMildClearHourIsGreatWithNothingInTheWay() {
        let result = check(slot())
        XCTAssertEqual(result.level, .great)
        XCTAssertNil(result.reason)
        XCTAssertTrue(result.isWalkable)
    }

    func testWindClimbsTheScaleFromANearGaleToHurricaneForce() {
        // Metres per second in the middle of Beaufort 7, 8, 10 and 12.
        XCTAssertEqual(check(slot(wind: 15)).level, .wait)
        XCTAssertEqual(check(slot(wind: 19)).level, .pottyOnly)
        XCTAssertEqual(check(slot(wind: 26)).level, .stayIn)
        XCTAssertEqual(check(slot(wind: 35)).level, .danger)
        XCTAssertEqual(check(slot(wind: 35)).reason, .wind(force: 12))
        XCTAssertEqual(check(slot(wind: 8)).level, .great)
    }

    func testAirFollowsTheRemoteConfigBandAndNamesThePollutant() {
        XCTAssertEqual(check(slot(airBand: 1)).level, .great)
        XCTAssertEqual(check(slot(airBand: 2)).level, .fine)
        XCTAssertTrue(check(slot(airBand: 2)).isWalkable)
        let smoky = check(slot(airBand: 3, pollutant: .fineParticles))
        XCTAssertEqual(smoky.level, .pottyOnly)
        XCTAssertEqual(smoky.reason, .air(band: 3, pollutant: .fineParticles))
        XCTAssertEqual(check(slot(airBand: 5)).level, .stayIn)

        var laxer = PetWeatherThresholds.standard
        laxer.badAirBand = 4
        XCTAssertEqual(check(slot(airBand: 3), thresholds: laxer).level, .fine)
        XCTAssertEqual(check(slot(airBand: 4), thresholds: laxer).level, .pottyOnly)
    }

    func testPavementGoesFromAWaitToKeepingPetsInside() {
        XCTAssertEqual(check(slot(pavement: 43)).level, .wait)
        XCTAssertEqual(check(slot(pavement: 54)).level, .pottyOnly)
        XCTAssertEqual(check(slot(pavement: 60)).level, .stayIn)
        XCTAssertEqual(check(slot(pavement: 60)).reason, .pavement(.dangerous))
        XCTAssertEqual(check(slot(pavement: 35)).level, .great)
    }

    func testHeatAndColdAreAWaitOutsideTheComfortRangeAndPottyBreaksPastThePetLimits() {
        XCTAssertEqual(check(slot(), feelsLikeC: 28).level, .wait)
        XCTAssertEqual(check(slot(), feelsLikeC: 31).level, .pottyOnly)
        XCTAssertEqual(check(slot(), feelsLikeC: 2).level, .wait)
        XCTAssertEqual(check(slot(), feelsLikeC: -2).level, .pottyOnly)
        XCTAssertEqual(check(slot(), feelsLikeC: -2).reason, .cold)
    }

    func testThunderstormsNowKeepPetsInsideAndRainIsAWait() {
        XCTAssertEqual(check(slot(), conditionNow: "Thunderstorm").level, .stayIn)
        XCTAssertEqual(check(slot(), conditionNow: "Thunderstorm").reason, .storms(likely: true))
        XCTAssertEqual(check(slot(), conditionNow: "Drizzle").level, .wait)
        XCTAssertEqual(check(slot(rain: 70, icon: "11d")).level, .stayIn)
        XCTAssertEqual(check(slot(rain: 40, icon: "11d")).level, .wait)
    }

    func testTheRainRulesReadTheChanceAsTheHourlyStripShowsIt() {
        // 55% shows as 60%: "then rain". 54% shows as 50%: "then maybe rain".
        XCTAssertEqual(check(slot(rain: 55, icon: "10d")).reason, .rain(likely: true))
        XCTAssertEqual(check(slot(rain: 54, icon: "10d")).reason, .rain(likely: false))
        XCTAssertEqual(check(slot(rain: 55, icon: "11d")).level, .stayIn)
        XCTAssertEqual(check(slot(rain: 54, icon: "11d")).level, .wait)
        // With the walk limit at 30: 25% shows as 30% and counts, 24% shows as 20% and doesn't.
        XCTAssertEqual(thresholds.maxRainChance, 30)
        XCTAssertEqual(check(slot(rain: 25, icon: "10d")).reason, .rain(likely: false))
        XCTAssertEqual(check(slot(rain: 24, icon: "10d")).level, .great)
        // 5% isn't shown at all: no rain, even with no walk limit.
        var anyChance = PetWeatherThresholds.standard
        anyChance.maxRainChance = 1
        XCTAssertNil(check(slot(rain: 5, icon: "10d"), thresholds: anyChance).reason)
        XCTAssertEqual(check(slot(rain: 10, icon: "10d"), thresholds: anyChance).reason, .rain(likely: false))
    }

    func testShownRainChance() {
        XCTAssertEqual(WeatherFormatting.shownRainChance(5), 0)
        XCTAssertEqual(WeatherFormatting.shownRainChance(9), 0)
        XCTAssertEqual(WeatherFormatting.shownRainChance(24), 20)
        XCTAssertEqual(WeatherFormatting.shownRainChance(25), 30)
        XCTAssertEqual(WeatherFormatting.shownRainChance(54), 50)
        XCTAssertEqual(WeatherFormatting.shownRainChance(55), 60)
        XCTAssertEqual(WeatherFormatting.shownRainChance(100), 100)
    }

    func testDarkIsAWait() {
        XCTAssertEqual(check(slot(icon: "01n")).reason, .dark)
        XCTAssertEqual(check(slot(), darkNow: true).level, .wait)
    }

    func testRainComesBeforeWarmPavementAtTheSameLevel() {
        // Nairobi on 11-07: drizzle, and pavement getting hot in the sun between showers.
        XCTAssertEqual(check(slot(pavement: 43), conditionNow: "Drizzle").reason, .rain(likely: true))
    }

    func testTheWorstFactorLeadsAndHeatComesBeforeAirBeforeCold() {
        let result = check(slot(airBand: 3, wind: 15), feelsLikeC: 31)
        XCTAssertEqual(result.reason, .heat)
        XCTAssertEqual(result.air?.level, .pottyOnly)
        XCTAssertEqual(result.factors.map(\.level), [.pottyOnly, .pottyOnly, .wait])
        XCTAssertEqual(check(slot(airBand: 3, wind: 26)).reason, .wind(force: 10))
    }

    func testAirNames() {
        XCTAssertEqual(WalkReason.airName(.fineParticles), "Smoky air")
        XCTAssertEqual(WalkReason.airName(.coarseParticles), "Dusty air")
        XCTAssertEqual(WalkReason.airName(.ozone), "High ozone")
        XCTAssertNil(WalkReason.airName(.nitrogenDioxide))
        XCTAssertNil(WalkReason.airName(nil))
    }

    // MARK: - The walk card

    private func advice(_ slots: [HourlySlot], feelsLikeC: Double = 18, conditionNow: String? = nil) -> WalkAdvice? {
        WalkAdvisor.advice(currentFeelsLikeC: feelsLikeC, upcoming: slots, conditionNow: conditionNow)
    }

    func testTheRatingSaysWhyWhenItIsMoreThanAWait() {
        XCTAssertEqual(advice([slot(wind: 19), slot("4 PM")])?.rating, .windy)
        XCTAssertEqual(advice([slot(wind: 35), slot("4 PM")])?.rating, .danger)
        XCTAssertEqual(advice([slot(), slot("4 PM")], conditionNow: "Thunderstorm")?.rating, .stormy)
        XCTAssertEqual(advice([slot(wind: 15), slot("4 PM")])?.rating, .okay)
    }

    func testTheCardCaptionNamesThePollutant() {
        XCTAssertEqual(caption([slot(airBand: 3, pollutant: .fineParticles), slot("4 PM")]), "Smoky air. Potty breaks only.")
        XCTAssertEqual(caption([slot(airBand: 3, pollutant: .ozone), slot("4 PM")]), "High ozone. Potty breaks only.")
        XCTAssertEqual(caption([slot(airBand: 4, pollutant: .nitrogenDioxide), slot("4 PM")]), "Bad air. Potty breaks only.")
        XCTAssertEqual(
            caption([slot(airBand: 5, pollutant: .coarseParticles), slot("4 PM")]),
            "Dusty air. Stay in. Potty breaks only."
        )
    }

    func testTheCardCaptionForWindAndStorms() {
        XCTAssertEqual(caption([slot(wind: 19), slot("4 PM")]), "Gale force winds. Potty breaks only.")
        XCTAssertEqual(caption([slot(wind: 26), slot("4 PM")]), "Storm force winds. Keep pets inside.")
        XCTAssertEqual(caption([slot(wind: 35), slot("4 PM")]), "Stay inside, away from the windows.")
        XCTAssertNil(caption([slot(wind: 15), slot("4 PM")]))
        XCTAssertEqual(caption([slot(), slot("4 PM")], conditionNow: "Thunderstorm"), "Thunderstorms. Keep pets inside.")
    }

    func testThePavementNoteSaysItIsAboutNowAndNeverStandsInForRain() {
        XCTAssertEqual(caption([slot(pavement: 43), slot("6 PM", pavement: 30)]), "Paw check: about 43° now. Getting hot.")
        XCTAssertNil(caption([slot(pavement: 43), slot("6 PM", pavement: 30)], conditionNow: "Drizzle"))
    }

    private func caption(_ slots: [HourlySlot], conditionNow: String? = nil) -> String? {
        advice(slots, conditionNow: conditionNow).flatMap(WalkCardContent.caption)
    }

    // MARK: - The hero's caption

    private let noon = Date(timeIntervalSince1970: 1_762_516_800) // 7 Nov 2025, 12:00 UTC
    private let evening = Date(timeIntervalSince1970: 1_762_545_600) // 7 Nov 2025, 20:00 UTC
    private let utc = TimeZone(identifier: "UTC")!

    func testBadAirGivesTheHeroAReasonCaptionNamingThePollutant() {
        let smoky = check(slot(airBand: 3, pollutant: .fineParticles))
        let caption = PetMood.walkCaption(smoky, hasDog: true, on: noon, timeZone: utc)
        XCTAssertNotNil(caption)
        XCTAssertTrue(PetMood.walkCaptions(smoky, hasDog: true)?.contains(caption ?? "") == true)
        XCTAssertEqual(
            PetMood.walkCaptions(smoky, hasDog: true)?.first,
            "Smoky air today. Quick potty breaks, then back on the sofa."
        )
        XCTAssertEqual(
            PetMood.walkCaptions(check(slot(airBand: 3)), hasDog: false)?.first,
            "Poor air today. Misty's keeping the windows shut."
        )
    }

    func testWindAndPavementGetReasonCaptionsButAWaitDoesNot() {
        XCTAssertEqual(
            PetMood.walkCaptions(check(slot(wind: 35)), hasDog: false),
            ["Hurricane force winds! Everyone inside, away from the windows."]
        )
        XCTAssertNotNil(PetMood.walkCaptions(check(slot(wind: 19)), hasDog: true))
        XCTAssertNotNil(PetMood.walkCaptions(check(slot(pavement: 54)), hasDog: true))
        XCTAssertNil(PetMood.walkCaptions(check(slot(pavement: 54), hasDog: false), hasDog: false))
        XCTAssertNil(PetMood.walkCaptions(check(slot(wind: 15)), hasDog: true))
        XCTAssertNil(PetMood.walkCaptions(check(slot(airBand: 2)), hasDog: true))
        // Heat is the scene's to show: the hot mood's captions already say so.
        XCTAssertNil(PetMood.walkCaptions(check(slot(), feelsLikeC: 31), hasDog: true))
    }

    func testCaptionsThatSuggestAWalkAreLeftOutWhenNowIsNotTheTime() {
        let chilly = check(slot(), feelsLikeC: 2)
        for day in 0 ..< 3 {
            let date = noon.addingTimeInterval(Double(day) * 86400)
            for mood in [PetMood.fair, .cloudy] {
                let caption = mood.caption(on: date, timeZone: utc, hasDog: true, walk: chilly)
                XCTAssertFalse(PetMood.walkSuggestions.contains(caption), caption)
            }
        }
        // With a walk now, the walk captions are back in the rotation.
        let walkable = check(slot())
        let fair = (0 ..< 3).map { PetMood.fair.caption(on: noon.addingTimeInterval(Double($0) * 86400), timeZone: utc, walk: walkable) }
        XCTAssertTrue(fair.contains("Perfect walkies weather! Off we go."))
    }

    func testThePartlyCloudyWalkCaptionsAreLeftOutWhenNowIsNotTheTime() {
        let chilly = check(slot(), feelsLikeC: 2)
        for day in 0 ..< 3 {
            let date = noon.addingTimeInterval(Double(day) * 86400)
            XCTAssertEqual(
                PetMood.cloudy.caption(on: date, timeZone: utc, hasDog: true, walk: chilly, partlyCloudy: true),
                "Misty has found the one sunny spot on the floor."
            )
        }
        let walkable = check(slot())
        let captions = (0 ..< 3).map {
            PetMood.cloudy.caption(on: noon.addingTimeInterval(Double($0) * 86400), timeZone: utc, walk: walkable, partlyCloudy: true)
        }
        XCTAssertTrue(captions.contains("Bit of sun, bit of cloud. Good sniffing weather."))
        XCTAssertTrue(captions.contains("Sun in, sun out. Sunny is ready either way."))
    }

    func testAnEveningWithRainUsesTheEveningCaptionsWithoutAWalkButDarkAloneKeepsThem() {
        let rainyNight = check(slot(icon: "10n"), conditionNow: "Rain")
        let caption = PetMood.night.caption(on: evening, timeZone: utc, hasDog: true, walk: rainyNight)
        XCTAssertTrue(PetMood.night.captions(nightPart: .evening, hasDog: false).contains(caption), caption)
        let darkOnly = check(slot(icon: "01n"))
        let walkCaption = PetMood.night.caption(on: evening, timeZone: utc, hasDog: true, walk: darkOnly)
        XCTAssertTrue(PetMood.walkSuggestions.contains(walkCaption), walkCaption)
    }

    func testTheAirQualityTileFollowsTheWalkRules() {
        let unhealthy = AirQuality(index: 172, scale: .us, mainPollutant: nil)
        XCTAssertEqual(unhealthy.line(hasDog: true), "Potty breaks only today")
        var laxer = PetWeatherThresholds.standard
        laxer.badAirBand = 4
        XCTAssertEqual(unhealthy.line(hasDog: true, thresholds: laxer), "Short walks for older and flat-faced dogs")
        XCTAssertEqual(AirQuality(index: 320, scale: .us, mainPollutant: nil).line(hasDog: true), "Stay in. Potty breaks only")
    }

    // MARK: - Fixes from the 11-07 review

    func testNowsWindComesFromTheCurrentReadingNotTheForecastHour() {
        // The Wind tile shows the reading: a hurricane under a calmer hour, and calm under a gale.
        XCTAssertEqual(check(slot(wind: 26), windForceNow: 12).level, .danger)
        XCTAssertEqual(check(slot(wind: 19), windForceNow: 3).level, .great)
        XCTAssertEqual(
            WalkAdvisor.advice(currentFeelsLikeC: 18, upcoming: [slot(wind: 26)], windForceNow: 12)?.rating,
            .danger
        )
    }

    func testHurricaneForceGustsAreADanger() {
        XCTAssertEqual(check(slot(wind: 19), gustForceNow: 12).level, .danger)
        XCTAssertEqual(check(slot(wind: 19), gustForceNow: 12).reason, .wind(force: 12))
        // Lesser gusts are left to the Wind tile.
        XCTAssertEqual(check(slot(wind: 19), gustForceNow: 10).level, .pottyOnly)
    }

    // MARK: - Warnings about later

    private let start = 1_762_516_800

    /// Now (a clear 3 PM unless told otherwise), then `later` hours each an hour apart.
    private func advice(
        now: HourlySlot? = nil,
        later: [HourlySlot],
        feelsLikeC: Double = 18,
        conditionNow: String? = nil,
        hasDog: Bool = true
    ) -> WalkAdvice? {
        WalkAdvisor.advice(
            currentFeelsLikeC: feelsLikeC,
            upcoming: [now ?? slot(epoch: start)] + later,
            now: Date(timeIntervalSince1970: TimeInterval(start)),
            conditionNow: conditionNow,
            hasDog: hasDog
        )
    }

    private func hour(_ hours: Int, _ label: String, wind: Double = 1, rain: Int = 0, icon: String = "01d") -> HourlySlot {
        slot(label, rain: rain, icon: icon, wind: wind, epoch: start + hours * 3600)
    }

    func testHurricaneForceWindAheadIsAWarningAndLeavesNowAlone() {
        let ahead = advice(later: [hour(1, "4 PM"), hour(3, "6 PM", wind: 35), hour(4, "7 PM", wind: 35)])
        XCTAssertEqual(ahead?.warning, .hurricane(from: "6 PM"))
        XCTAssertEqual(ahead?.rating, .great)
        XCTAssertEqual(ahead?.now.level, .great)
        XCTAssertFalse(ahead?.now.factors.contains { $0.level == .danger } ?? true)
        XCTAssertEqual(ahead?.isDanger, true)
        // Further out than 6 hours, or an hour without a time, isn't soon.
        XCTAssertNil(advice(later: [hour(9, "12 AM", wind: 35)])?.warning)
        XCTAssertNil(advice(later: [slot("4 PM", wind: 35)])?.warning)
    }

    func testHurricaneForceWindNowGivesNoWarning() {
        let now = advice(now: slot(wind: 35, epoch: start), later: [hour(2, "5 PM", wind: 35)])
        XCTAssertEqual(now?.rating, .danger)
        XCTAssertNil(now?.warning)
        XCTAssertEqual(now?.isDanger, true)
        // Nor storms ahead: hurricane force now already says to stay inside.
        let stormsLater = advice(now: slot(wind: 35, epoch: start), later: [hour(1, "4 PM", rain: 80, icon: "11d")])
        XCTAssertEqual(stormsLater?.rating, .danger)
        XCTAssertNil(stormsLater?.warning)
    }

    func testLikelyStormsAheadAreAWarningUnlessItIsStormingNow() {
        let storms = hour(1, "4 PM", rain: 80, icon: "11d")
        XCTAssertEqual(advice(later: [storms])?.warning, .storms(from: "4 PM"))
        XCTAssertEqual(advice(later: [storms])?.isDanger, false)
        XCTAssertNil(advice(later: [storms], conditionNow: "Thunderstorm")?.warning)
        XCTAssertNil(advice(now: slot(rain: 80, icon: "11d", epoch: start), later: [storms])?.warning)
        // Maybe storms (a chance under 60%) aren't worth the warning.
        XCTAssertNil(advice(later: [hour(1, "4 PM", rain: 40, icon: "11d")])?.warning)
    }

    func testHurricaneForceWindWinsOverStorms() {
        let later = [hour(1, "4 PM", rain: 80, icon: "11d"), hour(3, "6 PM", wind: 35)]
        XCTAssertEqual(advice(later: later)?.warning, .hurricane(from: "6 PM"))
    }

    func testTheCardForHurricaneForceWindNowAndAhead() {
        let now = WalkCardContent(advice: advice(now: slot(wind: 35, epoch: start), later: [hour(1, "4 PM")])!)
        XCTAssertEqual(now.title, "Danger")
        XCTAssertEqual(now.headline, "Hurricane force winds")
        XCTAssertEqual(now.caption, "Stay inside, away from the windows.")
        XCTAssertTrue(now.isDanger)

        let ahead = advice(later: [hour(1, "4 PM"), hour(3, "6 PM", wind: 35)], hasDog: false)!
        let card = WalkCardContent(advice: ahead)
        XCTAssertEqual(card.title, "Danger")
        XCTAssertEqual(card.headline, "Hurricane force winds from 6 PM")
        XCTAssertEqual(card.caption, "Get everyone inside before then.")
        XCTAssertTrue(card.isDanger)
        XCTAssertTrue(ahead.showsCard(hasDog: false, cardEnabled: false))
    }

    func testTheCardAddsStormsAheadToItsCaption() {
        let great = advice(later: [hour(1, "4 PM", rain: 80, icon: "11d")])
        XCTAssertEqual(great?.rating, .great)
        // The outlook already says storms are coming: left as it is.
        XCTAssertEqual(great.map(WalkCardContent.init)?.caption, "Good until 4 PM, then storms.")
        // Too hot now, the best time later: the reason, then the storms.
        let hot = advice(later: [hour(1, "4 PM"), hour(2, "5 PM", rain: 80, icon: "11d")], feelsLikeC: 31)!
        let hotCard = WalkCardContent(advice: hot)
        XCTAssertEqual(hotCard.headline, "Around 4 PM")
        XCTAssertEqual(hotCard.caption, "Too hot for paws. Storms from 5 PM.")
        XCTAssertEqual(hotCard.title, "Best Walk Time")
        XCTAssertFalse(hotCard.isDanger)
        XCTAssertFalse(hot.showsCard(hasDog: false, cardEnabled: true))
        // No caption of its own: just the storms.
        let wait = advice(now: slot(wind: 15, epoch: start), later: [hour(1, "4 PM"), hour(2, "5 PM", rain: 80, icon: "11d")])!
        XCTAssertEqual(WalkCardContent(advice: wait).caption, "Storms from 5 PM.")
        // A walk now whose outlook is something else: the outlook, then the storms.
        let rainFirst = WalkAdvice(
            rating: .great, bestTimeLabel: nil,
            outlook: .until(time: "4 PM", change: .rain), warning: .storms(from: "5 PM")
        )
        XCTAssertEqual(WalkCardContent(advice: rainFirst).caption, "Good until 4 PM, then rain. Storms from 5 PM.")
        let maybe = WalkAdvice(
            rating: .great, bestTimeLabel: nil,
            outlook: .until(time: "4 PM", change: .maybeStorms), warning: .storms(from: "5 PM")
        )
        XCTAssertEqual(WalkCardContent(advice: maybe).caption, "Good until 4 PM, then maybe storms.")
        let plain = WalkAdvice(rating: .great, bestTimeLabel: nil, warning: .storms(from: "5 PM"))
        XCTAssertEqual(WalkCardContent(advice: plain).caption, "Storms from 5 PM.")
        XCTAssertEqual(WalkCardContent(advice: plain).headline, "Now is a great time")
    }

    func testDrizzleNowUnderAnHourOfLikelyThunderstormsIsStorms() {
        let result = check(slot(rain: 80, icon: "11d"), conditionNow: "Drizzle")
        XCTAssertEqual(result.reason, .storms(likely: true))
        XCTAssertEqual(result.level, .stayIn)
        // A wetter forecast that's no worse leaves what's happening now.
        XCTAssertEqual(check(slot(rain: 80, icon: "10d"), conditionNow: "Drizzle").reason, .rain(likely: true))
    }

    func testWithoutADogThePavementIsNotWeighed() {
        // Dangerously hot pavement under smoky air: it leads with a dog, and isn't there without one.
        let hot = slot(pavement: 60, airBand: 3, pollutant: .fineParticles)
        XCTAssertEqual(check(hot).reason, .pavement(.dangerous))
        XCTAssertNil(check(hot, hasDog: false).pavement)
        XCTAssertEqual(check(hot, hasDog: false).reason, .air(band: 3, pollutant: .fineParticles))
        XCTAssertEqual(
            PetMood.walkCaptions(check(hot, hasDog: false), hasDog: false)?.first,
            "Smoky air today. Misty's keeping the windows shut."
        )
        XCTAssertEqual(PetMood.walkCaptions(check(hot), hasDog: true)?.first, "Hot pavement! Sunny's sticking to the grass today.")
        // The advice for now leaves it out too.
        let advice = WalkAdvisor.advice(currentFeelsLikeC: 18, upcoming: [slot(pavement: 60)], hasDog: false)
        XCTAssertNil(advice?.now.pavement)
        XCTAssertEqual(advice?.rating, .great)
    }

    func testAirQualitySwitchedOffLeavesTheAirOut() {
        var off = PetWeatherThresholds.standard
        off.airQualityEnabled = false
        let smoky = slot(airBand: 4, pollutant: .fineParticles)
        XCTAssertNil(check(smoky, thresholds: off).air)
        XCTAssertEqual(check(smoky, thresholds: off).level, .great)
        XCTAssertFalse(WalkAdvisor.hasBadAirForWalking(smoky, off))
        XCTAssertTrue(WalkAdvisor.hasBadAirForWalking(smoky, .standard))
    }

    func testIsWalkableAgreesWithTheCheck() {
        for hour in [slot(), slot(airBand: 2), slot(pavement: 49), slot(wind: 15), slot(rain: 40), slot(icon: "01n")] {
            XCTAssertEqual(WalkConditions.isWalkable(hour, thresholds), check(hour).isWalkable)
        }
    }

    func testAdviceForAReadingTakesNowFromTheReading() {
        // A hurricane in the reading, under a calm forecast hour: the reading is what's happening.
        let reading = CurrentWeather(
            cityName: "Austin", conditionMain: "Clear", description: "Clear sky", iconCode: "01d",
            temperature: 18, feelsLike: 18, tempMin: 10, tempMax: 20, humidityPercent: 50, pressureHpa: 1013,
            windSpeed: 35, windDeg: 90, visibilityMeters: 10_000, cloudPercent: 0, units: .metric,
            sunriseEpoch: nil, sunsetEpoch: nil
        )
        let start = Int(noon.timeIntervalSince1970)
        let day = DayForecast(
            dateLabel: "Fri, Nov 7", conditionMain: "Clear", description: "clear", iconCode: "01d",
            temperature: 18, feelsLike: 18, tempMin: 10, tempMax: 20, units: .metric,
            hourlySlots: [slot(epoch: start), slot("4 PM", epoch: start + 3600)]
        )
        let advice = WalkAdvisor.advice(for: reading, forecast: [day], at: noon, thresholds: thresholds, hasDog: true)
        XCTAssertEqual(advice?.rating, .danger)
        XCTAssertNil(WalkAdvisor.advice(for: reading, forecast: [], at: noon, thresholds: thresholds, hasDog: true))
    }

    func testTheWalkCardShowsWithADogAndADangerWarningForEveryone() {
        let okay = WalkAdvice(rating: .okay, bestTimeLabel: "4 PM")
        let danger = WalkAdvice(rating: .danger, bestTimeLabel: nil)
        XCTAssertTrue(okay.showsCard(hasDog: true, cardEnabled: true))
        XCTAssertFalse(okay.showsCard(hasDog: false, cardEnabled: true))
        XCTAssertFalse(okay.showsCard(hasDog: true, cardEnabled: false))
        XCTAssertTrue(danger.showsCard(hasDog: false, cardEnabled: false))
    }

    func testTheWalksReasonComesBeforeASeasonalThemesCaption() {
        let theme = "Happy Halloween from Sunny and Misty!"
        let smoky = check(slot(airBand: 3, pollutant: .fineParticles))
        let caption = PetMood.heroCaption(walk: smoky, hasDog: true, themeCaption: theme, mood: .fair, on: noon, timeZone: utc)
        XCTAssertTrue(PetMood.walkCaptions(smoky, hasDog: true)?.contains(caption) == true, caption)
        // Without a reason to give, the theme's caption stands.
        XCTAssertEqual(
            PetMood.heroCaption(walk: check(slot()), hasDog: true, themeCaption: theme, mood: .fair, on: noon, timeZone: utc),
            theme
        )
    }

    // MARK: - Helpers

    /// A metric hour at 3 PM, 18C, clear and calm unless told otherwise.
    private func slot(
        _ label: String = "3 PM",
        rain: Int = 0,
        icon: String = "01d",
        pavement: Double? = nil,
        airBand: Int? = nil,
        pollutant: AirQuality.Pollutant? = nil,
        wind: Double = 1,
        epoch: Int? = nil
    ) -> HourlySlot {
        var slot = HourlySlot(
            timeLabel: label,
            iconCode: icon,
            description: "clear",
            temperature: 18,
            feelsLike: 18,
            windSpeed: wind,
            windDeg: 0,
            humidity: 50,
            pressure: 1013,
            units: .metric,
            precipitationChance: rain,
            pavementTemperature: pavement,
            localHour: label == "3 PM" ? 15 : 16,
            epochSeconds: epoch
        )
        // The lowest US index in the band.
        slot.airQuality = airBand.map {
            AirQuality(index: Int(AirQuality.Scale.us.bandEdges[$0]) + ($0 == 0 ? 0 : 1), scale: .us, mainPollutant: pollutant)
        }
        return slot
    }
}
