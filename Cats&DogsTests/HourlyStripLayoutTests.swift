import SwiftUI
import XCTest
@testable import Cats_Dogs

/// The hourly card is the same height whether no hour, every hour or only an hour off screen shows
/// a rain chance, at the default text size and the largest. Same cases as Android's
/// `HourlyStripPreview`.
@MainActor
final class HourlyStripLayoutTests: XCTestCase {
    private let dayStart = 1_700_000_000 - 1_700_000_000 % 86400

    private func slot(_ hour: Int, chance: Int) -> HourlySlot {
        var slot = HourlySlot(
            timeLabel: "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")", iconCode: chance > 0 ? "10d" : "02d",
            description: "Cloudy", temperature: 18, feelsLike: 18, windSpeed: 2, windDeg: 0, humidity: 60,
            pressure: 1010, units: .metric, epochSeconds: dayStart + hour * 3600
        )
        slot.precipitationChance = chance
        return slot
    }

    /// 9 AM to 8 PM with a sunset between 5 and 6 PM.
    private func strip(chance: (Int) -> Int) -> [HourlyStripItem] {
        let slots = (9...20).map { slot($0, chance: chance($0)) }
        let sunset = SunEvent(kind: .sunset, epochSeconds: dayStart + 17 * 3600 + 49 * 60)
        return HourlyStripItem.strip(slots, events: [sunset], now: Date(timeIntervalSince1970: TimeInterval(dayStart + 9 * 3600)))
    }

    private var cases: [(name: String, items: [HourlyStripItem])] {
        [
            ("dry", strip { _ in 0 }),
            ("rain-every-hour", strip { 30 + $0 }),
            ("rain-only-off-screen", strip { $0 >= 19 ? 80 : 0 }),
            // From 3 PM, with the sunset marker beside an hour with rain.
            ("sunset-beside-rain", Array(strip { $0 == 18 ? 60 : 0 }.dropFirst(6))),
        ]
    }

    private func height(_ items: [HourlyStripItem], size: DynamicTypeSize) -> CGFloat {
        let view = HourlyStrip(items: items, timeZone: TimeZone(identifier: "UTC")!)
            .environment(\.dynamicTypeSize, size)
            .frame(width: 390)
        return UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 390, height: 2000)).height
    }

    func testTheCardIsTheSameHeightWithOrWithoutRain() {
        for size in [DynamicTypeSize.large, .accessibility5] {
            let heights = cases.map { height($0.items, size: size) }
            XCTAssertEqual(Set(heights).count, 1, "\(size): \(heights)")
        }
    }
}
