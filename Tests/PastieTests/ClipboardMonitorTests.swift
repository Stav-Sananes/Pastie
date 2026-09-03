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

    func testIgnoreNextChangeSkipsSelfWriteButResumesCapturingAfter() throws {
        let (monitor, store) = try makeMonitor()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("baseline \(UUID())", forType: .string)
        monitor.tick()
        XCTAssertEqual(try store.fetchAll().count, 1, "baseline copy should be captured normally")

        // Simulate PasteEngine writing the just-pasted clip back to the pasteboard —
        // PopupWindowController calls ignoreNextChange() right before this write happens.
        monitor.ignoreNextChange()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("self-pasted content \(UUID())", forType: .string)
        monitor.tick()

        XCTAssertEqual(try store.fetchAll().count, 1, "the self-write triggered by our own paste should NOT be captured as a new clip")

        // A subsequent genuine external copy should still be captured normally —
        // ignoreNextChange() only suppresses the one change immediately following it.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("external copy \(UUID())", forType: .string)
        monitor.tick()

        XCTAssertEqual(try store.fetchAll().count, 2, "external changes after the ignored one should resume being captured")
    }

    func testTickSkipsImageWhenCaptureImagesDisabled() throws {
        let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
        let prefs = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-monitor-tests-\(UUID())")!)
        prefs.captureImages = false
        let monitor = ClipboardMonitor(store: store, preferences: prefs)

        NSPasteboard.general.clearContents()
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.set()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        NSPasteboard.general.writeObjects([image])

        monitor.tick()

        XCTAssertEqual(try store.fetchAll().count, 0)
    }

    func testTickCapturesImageWhenCaptureImagesEnabled() throws {
        let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
        let prefs = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-monitor-tests-\(UUID())")!)
        let monitor = ClipboardMonitor(store: store, preferences: prefs)

        NSPasteboard.general.clearContents()
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.blue.set()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        NSPasteboard.general.writeObjects([image])

        monitor.tick()

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.type, .image)
    }
}
