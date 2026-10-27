import XCTest
@testable import LauncherCore

final class PanelKeysTests: XCTestCase {
    func key(_ code: Int, command: Bool = false, _ chars: String? = nil, empty: Bool) -> PanelKey {
        PanelKey.decide(keyCode: code, commandOnly: command, characters: chars, queryIsEmpty: empty)
    }

    func testEscClosesAnEmptyFieldWithOrWithoutCommandHeld() {
        XCTAssertEqual(key(53, empty: true), .close)
        XCTAssertEqual(key(53, command: true, empty: true), .close, "⌘ still down from ⌘Space")
    }

    func testEscClearsTextFirstWithOrWithoutCommandHeld() {
        XCTAssertEqual(key(53, empty: false), .clear)
        XCTAssertEqual(key(53, command: true, empty: false), .clear)
    }

    func testReturnAndCommandReturn() {
        XCTAssertEqual(key(36, empty: false), .activate(reveal: false))
        XCTAssertEqual(key(36, command: true, empty: false), .activate(reveal: true))
        XCTAssertEqual(key(76, empty: true), .activate(reveal: false))
    }

    func testCommandDigitsOnlyOnAnEmptyField() {
        XCTAssertEqual(key(18, command: true, "1", empty: true), .openRecent(1))
        XCTAssertEqual(key(23, command: true, "5", empty: true), .openRecent(5))
        XCTAssertEqual(key(22, command: true, "6", empty: true), .pass)
        XCTAssertEqual(key(18, command: true, "1", empty: false), .pass)
    }

    func testLettersGoToTheField() {
        XCTAssertEqual(key(0, "a", empty: true), .pass)
        XCTAssertEqual(key(8, command: true, "c", empty: false), .copy)
        XCTAssertEqual(key(9, command: true, "v", empty: true), .pass, "⌘V pastes into the field")
    }

    func testArrowsAndTab() {
        XCTAssertEqual(key(125, empty: false), .moveDown)
        XCTAssertEqual(key(126, empty: false), .moveUp)
        XCTAssertEqual(key(48, empty: false), .acceptCompletion)
    }
}
