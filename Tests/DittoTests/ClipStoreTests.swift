// Tests/DittoTests/ClipStoreTests.swift
import XCTest
import GRDB
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

    func makeStore(retentionCount: Int = 500) throws -> ClipStore {
        let dbQueue = try DatabaseQueue()
        return try ClipStore(dbQueue: dbQueue, retentionCount: retentionCount)
    }

    func testInsertAndFetchAll() throws {
        let store = try makeStore()
        let clip = Clip(id: nil, type: .text, textContent: "hello", imageData: nil, filePath: nil, sourceApp: "com.apple.Terminal", timestamp: Date(), pinned: false, sortOrder: 0)

        _ = try store.insert(clip)
        let all = try store.fetchAll()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.textContent, "hello")
        XCTAssertNotNil(all.first?.id)
    }

    func testMostRecentReturnsLatestByTimestamp() throws {
        let store = try makeStore()
        let older = Clip(id: nil, type: .text, textContent: "old", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date().addingTimeInterval(-10), pinned: false, sortOrder: 0)
        let newer = Clip(id: nil, type: .text, textContent: "new", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0)

        _ = try store.insert(older)
        _ = try store.insert(newer)

        XCTAssertEqual(try store.mostRecent()?.textContent, "new")
    }
}
