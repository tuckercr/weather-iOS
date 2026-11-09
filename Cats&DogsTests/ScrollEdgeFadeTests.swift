import XCTest
@testable import Cats_Dogs

@MainActor
final class ScrollEdgeFadeTests: XCTestCase {
    private func fade(_ offset: CGFloat, content: CGFloat = 1000, viewport: CGFloat = 400) -> ScrollEdgeFade {
        ScrollEdgeFade.forScroll(offset: offset, contentWidth: content, viewportWidth: viewport)
    }

    func testAtTheStartOnlyTheTrailingEdgeFades() {
        XCTAssertEqual(fade(0), ScrollEdgeFade(leading: false, trailing: true))
    }

    func testPartwayBothEdgesFade() {
        XCTAssertEqual(fade(300), ScrollEdgeFade(leading: true, trailing: true))
    }

    func testAtTheEndOnlyTheLeadingEdgeFades() {
        XCTAssertEqual(fade(600), ScrollEdgeFade(leading: true, trailing: false))
    }

    func testWithinAPointOfAnEndCountsAsAtIt() {
        XCTAssertEqual(fade(0.5), ScrollEdgeFade(leading: false, trailing: true))
        XCTAssertEqual(fade(599.5), ScrollEdgeFade(leading: true, trailing: false))
    }

    func testBouncingPastEitherEndKeepsThatSideCrisp() {
        XCTAssertEqual(fade(-30), ScrollEdgeFade(leading: false, trailing: true))
        XCTAssertEqual(fade(640), ScrollEdgeFade(leading: true, trailing: false))
    }

    func testWhenEverythingFitsNeitherEdgeFades() {
        XCTAssertEqual(fade(0, content: 400), .none)
        XCTAssertEqual(fade(0, content: 300), .none)
        XCTAssertEqual(fade(0, content: 400.5), .none)
    }

    func testBeforeLayoutNeitherEdgeFades() {
        XCTAssertEqual(fade(0, content: 0, viewport: 0), .none)
        XCTAssertEqual(fade(0, content: 1000, viewport: 0), .none)
    }
}
