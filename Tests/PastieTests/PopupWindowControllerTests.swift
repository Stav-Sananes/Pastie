// Tests/PastieTests/PopupWindowControllerTests.swift
import XCTest
@testable import Pastie

final class PopupWindowControllerTests: XCTestCase {
    func testPanelHeightGrowsWithRowCount() {
        let four = PopupWindowController.panelHeight(forRows: 4)
        let eight = PopupWindowController.panelHeight(forRows: 8)
        XCTAssertGreaterThan(eight, four)
    }

    func testPanelHeightClampsBelowOneRow() {
        XCTAssertEqual(PopupWindowController.panelHeight(forRows: 0), PopupWindowController.panelHeight(forRows: 1))
    }
}
