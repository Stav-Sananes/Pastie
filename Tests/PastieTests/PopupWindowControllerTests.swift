// Tests/PastieTests/PopupWindowControllerTests.swift
import XCTest
import GRDB
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

    // Regression test for the window-frame-vs-content-frame bug: show() must set the
    // panel's CONTENT height to panelHeight(forRows:), not the window frame height
    // (which includes the ~32pt title bar for this panel's style mask).
    func testShowSetsContentHeightToPanelHeightForConfiguredRowCount() throws {
        let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
        let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-popup-tests-\(UUID())")!)
        preferences.popupRowCount = 5
        let pasteEngine = PasteEngine()
        let controller = PopupWindowController(store: store, pasteEngine: pasteEngine, preferences: preferences)

        controller.show()

        XCTAssertEqual(
            controller.currentContentHeightForTesting ?? -1,
            PopupWindowController.panelHeight(forRows: 5),
            accuracy: 0.5
        )

        controller.hide()
    }

    // Regression test: panelHeight(forRows:) assumes rowHeight (24pt) per row, but the
    // table view was never told to actually use that row height — it kept AppKit's
    // default (~17pt), so a configured row count never matched what actually fit.
    func testTableViewRowHeightMatchesPanelHeightAssumption() throws {
        let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
        let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-popup-tests-\(UUID())")!)
        let controller = PopupWindowController(store: store, pasteEngine: PasteEngine(), preferences: preferences)

        XCTAssertEqual(controller.tableRowHeightForTesting, PopupWindowController.rowHeight)
    }
}
