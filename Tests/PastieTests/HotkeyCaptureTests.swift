// Tests/PastieTests/HotkeyCaptureTests.swift
import XCTest
import AppKit
@testable import Pastie

final class HotkeyCaptureTests: XCTestCase {
    func testRejectsBareKeyWithNoModifiers() {
        XCTAssertFalse(HotkeyCapture.isValidBinding(modifiers: []))
    }

    func testAcceptsCommandModifier() {
        XCTAssertTrue(HotkeyCapture.isValidBinding(modifiers: [.command]))
    }

    func testAcceptsOptionCommandCombo() {
        XCTAssertTrue(HotkeyCapture.isValidBinding(modifiers: [.option, .command]))
    }

    func testIgnoresCapsLockAndFunctionFlags() {
        // capsLock/function are device flags, not modifiers a user deliberately chose —
        // a combo carrying only these should still be rejected.
        XCTAssertFalse(HotkeyCapture.isValidBinding(modifiers: [.capsLock, .function]))
    }
}
