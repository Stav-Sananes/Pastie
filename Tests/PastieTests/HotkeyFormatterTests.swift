import XCTest
import AppKit
@testable import Pastie

final class HotkeyFormatterTests: XCTestCase {
    func testDisplayStringForOptionCommandV() {
        let modifiers = UInt32(NSEvent.ModifierFlags([.option, .command]).rawValue)
        XCTAssertEqual(HotkeyFormatter.displayString(keyCode: 9, modifiers: modifiers), "⌥⌘V")
    }

    func testDisplayStringForControlShiftC() {
        let modifiers = UInt32(NSEvent.ModifierFlags([.control, .shift]).rawValue)
        XCTAssertEqual(HotkeyFormatter.displayString(keyCode: 8, modifiers: modifiers), "⌃⇧C")
    }
}
