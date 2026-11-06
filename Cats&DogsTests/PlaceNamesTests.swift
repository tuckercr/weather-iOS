import XCTest
@testable import Cats_Dogs

@MainActor
final class PlaceNamesTests: XCTestCase {
    private var suite: ThrowawayDefaults!

    override func setUp() {
        super.setUp()
        suite = ThrowawayDefaults()
    }

    override func tearDown() {
        suite.destroy()
        super.tearDown()
    }

    func testRemembersTheNameUntilMyLocationMoves() async {
        let lookUps = LookUps(answers: ["Knoxville", "Farragut"])
        let names = DevicePlaceNames(defaults: suite.defaults, lookUp: { _, _ in await lookUps.next() })

        let first = await names.name(latitude: 35.9168, longitude: -83.9597)
        // About 500 m away: the same place, not looked up again.
        let nearby = await names.name(latitude: 35.9213, longitude: -83.9597)
        // About 2 km away: looked up.
        let moved = await names.name(latitude: 35.9348, longitude: -83.9597)

        XCTAssertEqual(first, "Knoxville")
        XCTAssertEqual(nearby, "Knoxville")
        XCTAssertEqual(moved, "Farragut")
        let count = await lookUps.count
        XCTAssertEqual(count, 2)
    }

    func testRemembersAcrossLaunches() async {
        let lookUps = LookUps(answers: ["Knoxville"])
        _ = await DevicePlaceNames(defaults: suite.defaults, lookUp: { _, _ in await lookUps.next() })
            .name(latitude: 35.9168, longitude: -83.9597)

        let again = await DevicePlaceNames(defaults: suite.defaults, lookUp: { _, _ in nil })
            .name(latitude: 35.9168, longitude: -83.9597)

        XCTAssertEqual(again, "Knoxville")
    }

    func testFailedOrBlankLookUpsGiveNoNameAndAreTriedAgain() async {
        let lookUps = LookUps(answers: [nil, "  ", "Knoxville"])
        let names = DevicePlaceNames(defaults: suite.defaults, lookUp: { _, _ in await lookUps.next() })

        let failed = await names.name(latitude: 35.9168, longitude: -83.9597)
        let blank = await names.name(latitude: 35.9168, longitude: -83.9597)
        let found = await names.name(latitude: 35.9168, longitude: -83.9597)

        XCTAssertNil(failed)
        XCTAssertNil(blank)
        XCTAssertEqual(found, "Knoxville")
    }
}

/// Answers lookups in order, counting them.
private actor LookUps {
    private var answers: [String?]
    private(set) var count = 0

    init(answers: [String?]) {
        self.answers = answers
    }

    func next() -> String? {
        count += 1
        return answers.isEmpty ? nil : answers.removeFirst()
    }
}
