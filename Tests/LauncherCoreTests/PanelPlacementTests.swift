import CoreGraphics
import XCTest
@testable import LauncherCore

final class PanelPlacementTests: XCTestCase {
    /// A 1440 × 900 screen with a 25 pt menu bar.
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func drag(_ midX: CGFloat, _ top: CGFloat, in visible: CGRect? = nil) -> (placement: PanelPlacement, snapped: PanelPlacement.Guides) {
        PanelPlacement.dragged(midX: midX, top: top, in: visible ?? self.visible, width: 560, tallest: 340)
    }

    func testStandardIsCentredAThirdOfTheWayDown() {
        let (midX, top) = PanelPlacement.standard.resolve(in: visible, width: 560, tallest: 340)
        XCTAssertEqual(midX, 720)
        XCTAssertEqual(top, (875 - 875.0 / 3).rounded())
    }

    func testNearTheStandardSpotSnapsToItExactly() {
        let (_, top) = PanelPlacement.standard.resolve(in: visible, width: 560, tallest: 340)
        let near = drag(729, top - 11)
        XCTAssertEqual(near.placement, .standard)
        XCTAssertEqual(near.snapped, [.centerX, .standardTop])
    }

    func testEachGuideSnapsOnItsOwn() {
        let (_, top) = PanelPlacement.standard.resolve(in: visible, width: 560, tallest: 340)
        let onCentre = drag(715, 400)
        XCTAssertEqual(onCentre.snapped, [.centerX])
        XCTAssertEqual(onCentre.placement.centerX, 0.5)
        XCTAssertEqual(onCentre.placement.resolve(in: visible, width: 560, tallest: 340).top, 400)

        let onTopLine = drag(400, top + 5)
        XCTAssertEqual(onTopLine.snapped, [.standardTop])
        XCTAssertEqual(onTopLine.placement.top, PanelPlacement.standard.top)
        XCTAssertEqual(onTopLine.placement.resolve(in: visible, width: 560, tallest: 340).midX, 400)
    }

    func testFarFromTheGuidesStaysPut() {
        let away = drag(1000, 700)
        XCTAssertEqual(away.snapped, [])
        let (midX, top) = away.placement.resolve(in: visible, width: 560, tallest: 340)
        XCTAssertEqual(midX, 1000)
        XCTAssertEqual(top, 700)
    }

    func testKeepsTheWholePanelOnScreen() {
        let (midX, top) = drag(5000, 5000).placement.resolve(in: visible, width: 560, tallest: 340)
        XCTAssertEqual(midX, 1440 - 280)
        XCTAssertEqual(top, 875)
        let low = drag(-50, 10).placement.resolve(in: visible, width: 560, tallest: 340)
        XCTAssertEqual(low.midX, 280)
        XCTAssertEqual(low.top, 340, "room left below for the tallest tray")
    }

    func testCarriesOverToAScreenOfAnotherSize() {
        let placed = drag(1080, 600).placement
        let big = CGRect(x: 1440, y: -200, width: 2560, height: 1415)
        let (midX, top) = placed.resolve(in: big, width: 560, tallest: 340)
        XCTAssertEqual(midX, 1440 + 2560 * 0.75)
        XCTAssertEqual(top, (1215 - 1415 * (275.0 / 875)).rounded())
    }

    func testStandardStaysStandardOnEveryScreen() {
        let big = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let (midX, top) = drag(-960, (1055 - 1055.0 / 3).rounded(), in: big).placement.resolve(in: big, width: 560, tallest: 340)
        XCTAssertEqual(midX, -960)
        XCTAssertEqual(top, (1055 - 1055.0 / 3).rounded())
    }

    func testSurvivesARoundTripThroughJSON() throws {
        let placed = drag(1000, 700).placement
        let decoded = try JSONDecoder().decode(PanelPlacement.self, from: JSONEncoder().encode(placed))
        XCTAssertEqual(decoded, placed)
    }
}
