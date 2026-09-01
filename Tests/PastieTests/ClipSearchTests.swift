// Tests/PastieTests/ClipSearchTests.swift
import XCTest
@testable import Pastie

final class ClipSearchTests: XCTestCase {
    private func clip(_ text: String) -> Clip {
        Clip(id: nil, type: .text, textContent: text, imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0)
    }

    func testEmptyQueryReturnsAll() {
        let clips = [clip("alpha"), clip("beta")]
        XCTAssertEqual(ClipSearch.filter(clips, query: "").count, 2)
    }

    func testQueryFiltersCaseInsensitively() {
        let clips = [clip("Hello World"), clip("Goodbye")]
        let result = ClipSearch.filter(clips, query: "hello")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.textContent, "Hello World")
    }

    func testQueryMatchesFilePath() {
        let fileClip = Clip(id: nil, type: .file, textContent: nil, imageData: nil, filePath: "/Users/me/report.pdf", sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0)
        XCTAssertEqual(ClipSearch.filter([fileClip], query: "report").count, 1)
    }

    func testQueryExcludesImageClips() {
        let imageClip = Clip(id: nil, type: .image, textContent: nil, imageData: Data([0x01]), filePath: nil, sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0)
        XCTAssertEqual(ClipSearch.filter([imageClip], query: "anything").count, 0)
    }
}
