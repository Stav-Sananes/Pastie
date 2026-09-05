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

    private func makeRTF(_ text: String) -> Data {
        let attributed = NSAttributedString(string: text)
        return attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])!
    }

    private func makeMonitor(defaults: UserDefaults) -> ClipboardMonitor {
        let dbQueue = try! DatabaseQueue()
        let store = try! ClipStore(dbQueue: dbQueue, retentionCount: 500)
        return ClipboardMonitor(store: store, preferences: PreferencesStore(defaults: defaults))
    }

    func testCapturesRTFAlongsidePlainText() {
        let defaults = UserDefaults(suiteName: "PastieTests.capture.\(UUID().uuidString)")!
        let monitor = makeMonitor(defaults: defaults)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastieTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(makeRTF("styled"), forType: .rtf)
        pasteboard.setString("styled", forType: .string)

        let clip = monitor.makeClip(from: pasteboard, sourceApp: nil)

        XCTAssertEqual(clip?.type, .text)
        XCTAssertEqual(clip?.textContent, "styled")
        XCTAssertNotNil(clip?.rtfData, "RTF on the pasteboard is kept alongside the plain string")
    }

    func testPlainOnlyPasteboardStoresNoRTF() {
        let defaults = UserDefaults(suiteName: "PastieTests.capture.\(UUID().uuidString)")!
        let monitor = makeMonitor(defaults: defaults)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastieTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("just words", forType: .string)

        let clip = monitor.makeClip(from: pasteboard, sourceApp: nil)

        XCTAssertEqual(clip?.textContent, "just words")
        XCTAssertNil(clip?.rtfData)
    }

    func testRTFOverTheCapIsDroppedAndPlainTextSurvives() {
        let defaults = UserDefaults(suiteName: "PastieTests.capture.\(UUID().uuidString)")!
        let preferences = PreferencesStore(defaults: defaults)
        preferences.rtfSizeCapBytes = 16
        let dbQueue = try! DatabaseQueue()
        let store = try! ClipStore(dbQueue: dbQueue, retentionCount: 500)
        let monitor = ClipboardMonitor(store: store, preferences: preferences)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastieTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(makeRTF("a long styled run of text"), forType: .rtf)
        pasteboard.setString("a long styled run of text", forType: .string)

        let clip = monitor.makeClip(from: pasteboard, sourceApp: nil)

        XCTAssertEqual(clip?.textContent, "a long styled run of text", "the clip still works")
        XCTAssertNil(clip?.rtfData, "oversized RTF is dropped, not stored")
    }

    func testRTFCaptureDisabledStoresNoRTF() {
        let defaults = UserDefaults(suiteName: "PastieTests.capture.\(UUID().uuidString)")!
        let preferences = PreferencesStore(defaults: defaults)
        preferences.rtfCaptureEnabled = false
        let dbQueue = try! DatabaseQueue()
        let store = try! ClipStore(dbQueue: dbQueue, retentionCount: 500)
        let monitor = ClipboardMonitor(store: store, preferences: preferences)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastieTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(makeRTF("styled"), forType: .rtf)
        pasteboard.setString("styled", forType: .string)

        let clip = monitor.makeClip(from: pasteboard, sourceApp: nil)

        XCTAssertNil(clip?.rtfData)
    }

    func testTextWinsWhenTheSourceDeclaresItFirst() {
        // Terminal and other text apps put a small placeholder image on the pasteboard beside the
        // string. Declaring the string first is the source saying which one it means.
        let defaults = UserDefaults(suiteName: "PastieTests.precedence.\(UUID().uuidString)")!
        let monitor = makeMonitor(defaults: defaults)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastieTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .tiff], owner: nil)
        pasteboard.setString("the words I copied", forType: .string)
        pasteboard.setData(tinyTIFF(), forType: .tiff)

        let clip = monitor.makeClip(from: pasteboard, sourceApp: nil)

        XCTAssertEqual(clip?.type, .text, "a text copy must not become a 4x4 pixel image")
        XCTAssertEqual(clip?.textContent, "the words I copied")
    }

    func testImageWinsWhenTheSourceDeclaresItFirst() {
        // Copying an actual image: the image type leads, and any string beside it is incidental.
        let defaults = UserDefaults(suiteName: "PastieTests.precedence.\(UUID().uuidString)")!
        let monitor = makeMonitor(defaults: defaults)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastieTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.declareTypes([.tiff, .string], owner: nil)
        pasteboard.setData(tinyTIFF(), forType: .tiff)
        pasteboard.setString("https://example.com/cat.png", forType: .string)

        let clip = monitor.makeClip(from: pasteboard, sourceApp: nil)

        XCTAssertEqual(clip?.type, .image)
    }

    func testImageOnlyPasteboardIsStillAnImage() {
        let defaults = UserDefaults(suiteName: "PastieTests.precedence.\(UUID().uuidString)")!
        let monitor = makeMonitor(defaults: defaults)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PastieTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.declareTypes([.tiff], owner: nil)
        pasteboard.setData(tinyTIFF(), forType: .tiff)

        let clip = monitor.makeClip(from: pasteboard, sourceApp: nil)

        XCTAssertEqual(clip?.type, .image)
    }

    private func tinyTIFF() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        return image.tiffRepresentation!
    }
}
