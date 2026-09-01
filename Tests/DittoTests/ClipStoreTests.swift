// Tests/DittoTests/ClipStoreTests.swift
import XCTest
@testable import Ditto

final class ClipStoreTests: XCTestCase {
    func testClipContentEquality() {
        let now = Date()
        let a = Clip(id: nil, type: .text, textContent: "hello", imageData: nil, filePath: nil, sourceApp: nil, timestamp: now, pinned: false, sortOrder: 0)
        let b = Clip(id: 99, type: .text, textContent: "hello", imageData: nil, filePath: nil, sourceApp: "other", timestamp: now.addingTimeInterval(10), pinned: true, sortOrder: 5)
        let c = Clip(id: nil, type: .text, textContent: "different", imageData: nil, filePath: nil, sourceApp: nil, timestamp: now, pinned: false, sortOrder: 0)

        XCTAssertTrue(a.hasSameContent(as: b))
        XCTAssertFalse(a.hasSameContent(as: c))
    }
}
