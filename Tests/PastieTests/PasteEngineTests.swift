// Tests/PastieTests/PasteEngineTests.swift
import XCTest
import AppKit
@testable import Pastie

final class PasteEngineTests: XCTestCase {
    private func makeRTF(_ text: String) -> Data {
        let attributed = NSAttributedString(string: text)
        return attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])!
    }

    private func makeBoard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("PastieTests.paste.\(UUID().uuidString)"))
    }

    private func richClip() -> Clip {
        Clip(id: 1, type: .text, textContent: "styled", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0, rtfData: makeRTF("styled"))
    }

    func testRichPasteWritesBothRepresentations() {
        let engine = PasteEngine()
        let board = makeBoard()

        engine.writeToPasteboard(richClip(), plain: false, pasteboard: board)

        XCTAssertNotNil(board.data(forType: .rtf), "rich paste publishes RTF")
        XCTAssertEqual(board.string(forType: .string), "styled", "and plain text beside it")
    }

    func testPlainPasteOmitsRTF() {
        let engine = PasteEngine()
        let board = makeBoard()

        engine.writeToPasteboard(richClip(), plain: true, pasteboard: board)

        XCTAssertNil(board.data(forType: .rtf), "plain paste publishes no RTF")
        XCTAssertEqual(board.string(forType: .string), "styled")
    }

    func testClipWithoutRTFWritesPlainTextEitherWay() {
        let engine = PasteEngine()
        let clip = Clip(id: 1, type: .text, textContent: "bare", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0)

        let rich = makeBoard()
        engine.writeToPasteboard(clip, plain: false, pasteboard: rich)
        XCTAssertNil(rich.data(forType: .rtf))
        XCTAssertEqual(rich.string(forType: .string), "bare")

        let plain = makeBoard()
        engine.writeToPasteboard(clip, plain: true, pasteboard: plain)
        XCTAssertEqual(plain.string(forType: .string), "bare")
    }

    func testFileClipWritesAFileURL() {
        let engine = PasteEngine()
        let board = makeBoard()
        let clip = Clip(id: 1, type: .file, textContent: nil, imageData: nil, filePath: "/tmp/example.txt", sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0)

        engine.writeToPasteboard(clip, plain: false, pasteboard: board)

        let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(urls?.first?.path, "/tmp/example.txt")
    }
}
