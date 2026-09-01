// Tests/PastieTests/ClipStoreTests.swift
import XCTest
import GRDB
@testable import Pastie

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

extension ClipStoreTests {
    func testRetentionEvictsOldestUnpinned() throws {
        let store = try makeStore(retentionCount: 2)
        for i in 0..<3 {
            let clip = Clip(id: nil, type: .text, textContent: "clip\(i)", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date().addingTimeInterval(Double(i)), pinned: false, sortOrder: 0)
            _ = try store.insert(clip)
        }
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertFalse(all.contains { $0.textContent == "clip0" })
    }

    func testPinnedItemsExemptFromEviction() throws {
        let store = try makeStore(retentionCount: 1)
        let pinned = try store.insert(Clip(id: nil, type: .text, textContent: "keep", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date().addingTimeInterval(-100), pinned: false, sortOrder: 0))
        try store.setPinned(true, id: pinned.id!)
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "newer1", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0))
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "newer2", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date().addingTimeInterval(1), pinned: false, sortOrder: 0))

        let all = try store.fetchAll()
        XCTAssertTrue(all.contains { $0.textContent == "keep" })
    }

    func testDeleteRemovesItem() throws {
        let store = try makeStore()
        let clip = try store.insert(Clip(id: nil, type: .text, textContent: "gone", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0))
        try store.delete(id: clip.id!)
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testClearAllKeepsPinned() throws {
        let store = try makeStore()
        let pinned = try store.insert(Clip(id: nil, type: .text, textContent: "pinned", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0))
        try store.setPinned(true, id: pinned.id!)
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "unpinned", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0))

        try store.clearAll()

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.textContent, "pinned")
    }
}
