import XCTest
import AppKit
import GRDB
@testable import Pastie

final class ClipboardMonitorTests: XCTestCase {
    func makeMonitor() throws -> (ClipboardMonitor, ClipStore) {
        let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
        let prefs = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-monitor-tests-\(UUID())")!)
        let monitor = ClipboardMonitor(store: store, preferences: prefs)
        return (monitor, store)
    }

    func testTickCapturesNewTextFromPasteboard() throws {
        let (monitor, store) = try makeMonitor()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("captured text \(UUID())", forType: .string)

        monitor.tick()

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.type, .text)
    }

    func testTickIgnoresUnchangedPasteboard() throws {
        let (monitor, store) = try makeMonitor()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("stable text", forType: .string)

        monitor.tick()
        monitor.tick()

        XCTAssertEqual(try store.fetchAll().count, 1)
    }
}
