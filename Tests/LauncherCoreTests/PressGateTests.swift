import XCTest
@testable import LauncherCore

final class PressGateTests: XCTestCase {
    func testHeldKeyActsOnce() {
        var gate = PressGate()
        XCTAssertTrue(gate.press())
        // Auto-repeat while held.
        XCTAssertFalse(gate.press())
        XCTAssertFalse(gate.press())
        gate.release()
        XCTAssertFalse(gate.isDown)
    }

    func testFastDoubleTapActsTwice() {
        var gate = PressGate()
        XCTAssertTrue(gate.press())
        gate.release()
        XCTAssertTrue(gate.press())
        gate.release()
    }
}
