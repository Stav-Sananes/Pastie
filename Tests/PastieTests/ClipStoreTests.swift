// Tests/PastieTests/ClipStoreTests.swift
import XCTest
import GRDB
@testable import Pastie

final class ClipStoreTests: XCTestCase {
    func testClipContentEquality() {
        let now = Date()
        let a = Clip(id: nil, type: .text, textContent: "hello", imageData: nil, filePath: nil, sourceApp: nil, timestamp: now, saved: false, sortOrder: 0)
        let b = Clip(id: 99, type: .text, textContent: "hello", imageData: nil, filePath: nil, sourceApp: "other", timestamp: now.addingTimeInterval(10), saved: true, sortOrder: 5)
        let c = Clip(id: nil, type: .text, textContent: "different", imageData: nil, filePath: nil, sourceApp: nil, timestamp: now, saved: false, sortOrder: 0)

        XCTAssertTrue(a.hasSameContent(as: b))
        XCTAssertFalse(a.hasSameContent(as: c))
    }

    func makeStore(retentionCount: Int = 500) throws -> ClipStore {
        let dbQueue = try DatabaseQueue()
        return try ClipStore(dbQueue: dbQueue, retentionCount: retentionCount)
    }

    func testInsertAndFetchAll() throws {
        let store = try makeStore()
        let clip = Clip(id: nil, type: .text, textContent: "hello", imageData: nil, filePath: nil, sourceApp: "com.apple.Terminal", timestamp: Date(), saved: false, sortOrder: 0)

        _ = try store.insert(clip)
        let all = try store.fetchAll()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.textContent, "hello")
        XCTAssertNotNil(all.first?.id)
    }

    func testMostRecentReturnsLatestByTimestamp() throws {
        let store = try makeStore()
        let older = Clip(id: nil, type: .text, textContent: "old", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date().addingTimeInterval(-10), saved: false, sortOrder: 0)
        let newer = Clip(id: nil, type: .text, textContent: "new", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0)

        _ = try store.insert(older)
        _ = try store.insert(newer)

        XCTAssertEqual(try store.mostRecent()?.textContent, "new")
    }
}

extension ClipStoreTests {
    func testRetentionEvictsOldestUnsaved() throws {
        let store = try makeStore(retentionCount: 2)
        for i in 0..<3 {
            let clip = Clip(id: nil, type: .text, textContent: "clip\(i)", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date().addingTimeInterval(Double(i)), saved: false, sortOrder: 0)
            _ = try store.insert(clip)
        }
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertFalse(all.contains { $0.textContent == "clip0" })
    }

    func testSavedItemsExemptFromEviction() throws {
        let store = try makeStore(retentionCount: 1)
        let savedClip = try store.insert(Clip(id: nil, type: .text, textContent: "keep", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date().addingTimeInterval(-100), saved: false, sortOrder: 0))
        try store.setSaved(true, id: savedClip.id!)
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "newer1", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "newer2", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date().addingTimeInterval(1), saved: false, sortOrder: 0))

        let all = try store.fetchAll()
        XCTAssertTrue(all.contains { $0.textContent == "keep" })
    }

    func testRetentionCountProviderIsReadLiveOnEachEviction() throws {
        var liveRetentionCount = 10
        let dbQueue = try DatabaseQueue()
        let store = try ClipStore(dbQueue: dbQueue, retentionCountProvider: { liveRetentionCount })

        for i in 0..<3 {
            _ = try store.insert(Clip(id: nil, type: .text, textContent: "clip\(i)", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date().addingTimeInterval(Double(i)), saved: false, sortOrder: 0))
        }
        XCTAssertEqual(try store.fetchAll().count, 3, "with a high retention count nothing should be evicted yet")

        // Simulate the user lowering the retention preference at runtime — no ClipStore recreation.
        liveRetentionCount = 1
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "clip3", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date().addingTimeInterval(3), saved: false, sortOrder: 0))

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1, "the new lower retention count should be honored immediately, without recreating ClipStore")
        XCTAssertEqual(all.first?.textContent, "clip3")
    }

    func testDeleteRemovesItem() throws {
        let store = try makeStore()
        let clip = try store.insert(Clip(id: nil, type: .text, textContent: "gone", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))
        try store.delete(id: clip.id!)
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testClearAllKeepsSaved() throws {
        let store = try makeStore()
        let savedClip = try store.insert(Clip(id: nil, type: .text, textContent: "saved", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))
        try store.setSaved(true, id: savedClip.id!)
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "unsaved", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))

        try store.clearAll()

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.textContent, "saved")
    }

    func testMigrationRenamesPinnedToSavedAndPreservesRows() throws {
        // Build a v1-shaped database by hand, then open it through ClipStore so migration 2 runs.
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "clip") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull()
                t.column("textContent", .text)
                t.column("imageData", .blob)
                t.column("filePath", .text)
                t.column("sourceApp", .text)
                t.column("timestamp", .datetime).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('createClip')")
            try db.execute(sql: """
                INSERT INTO clip (type, textContent, timestamp, pinned, sortOrder)
                VALUES ('text', 'kept me', ?, 1, 0)
                """, arguments: [Date()])
            try db.execute(sql: """
                INSERT INTO clip (type, textContent, timestamp, pinned, sortOrder)
                VALUES ('text', 'ordinary', ?, 0, 0)
                """, arguments: [Date()])
        }

        let store = try ClipStore(dbQueue: dbQueue, retentionCount: 500)
        let all = try store.fetchAll()

        XCTAssertEqual(all.count, 2, "migration must not lose rows")
        let kept = all.first { $0.textContent == "kept me" }
        let ordinary = all.first { $0.textContent == "ordinary" }
        XCTAssertEqual(kept?.saved, true, "a pinned v1 row becomes a Saved clip")
        XCTAssertEqual(ordinary?.saved, false)
        XCTAssertNil(kept?.rtfData)
        XCTAssertNil(kept?.slotIndex)
    }

    func testEvictionExemptsSavedClips() throws {
        let store = try makeStore(retentionCount: 2)
        let base = Date()
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "old-saved", imageData: nil, filePath: nil, sourceApp: nil, timestamp: base.addingTimeInterval(-100), saved: true, sortOrder: 0))
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "old-plain", imageData: nil, filePath: nil, sourceApp: nil, timestamp: base.addingTimeInterval(-50), saved: false, sortOrder: 0))
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "mid", imageData: nil, filePath: nil, sourceApp: nil, timestamp: base.addingTimeInterval(-10), saved: false, sortOrder: 0))
        _ = try store.insert(Clip(id: nil, type: .text, textContent: "new", imageData: nil, filePath: nil, sourceApp: nil, timestamp: base, saved: false, sortOrder: 0))

        let all = try store.fetchAll()
        let texts = Set(all.compactMap { $0.textContent })

        XCTAssertTrue(texts.contains("old-saved"), "Saved clips are never evicted")
        XCTAssertFalse(texts.contains("old-plain"), "the oldest unsaved clip is evicted past the cap")
        XCTAssertEqual(all.filter { !$0.saved }.count, 2, "the cap counts unsaved clips only")
    }

    func testRichAndPlainCopiesOfTheSameTextAreOneClip() throws {
        // Plain text is a clip's identity: the rich payload must not make a duplicate.
        let now = Date()
        let rich = Clip(id: nil, type: .text, textContent: "same words", imageData: nil, filePath: nil, sourceApp: nil, timestamp: now, saved: false, sortOrder: 0, rtfData: Data([0x7B, 0x5C, 0x72, 0x74, 0x66]))
        let plain = Clip(id: nil, type: .text, textContent: "same words", imageData: nil, filePath: nil, sourceApp: nil, timestamp: now, saved: false, sortOrder: 0)

        XCTAssertTrue(rich.hasSameContent(as: plain))
        XCTAssertTrue(plain.hasSameContent(as: rich))
    }

    func testSetSavedTogglesTheFlag() throws {
        let store = try makeStore()
        let inserted = try store.insert(Clip(id: nil, type: .text, textContent: "x", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))
        let id = try XCTUnwrap(inserted.id)

        try store.setSaved(true, id: id)
        XCTAssertEqual(try store.fetchAll().first?.saved, true)

        try store.setSaved(false, id: id)
        XCTAssertEqual(try store.fetchAll().first?.saved, false)
    }

    private func insertText(_ store: ClipStore, _ text: String, saved: Bool = false, at date: Date = Date()) throws -> Int64 {
        let clip = try store.insert(Clip(id: nil, type: .text, textContent: text, imageData: nil, filePath: nil, sourceApp: nil, timestamp: date, saved: saved, sortOrder: 0))
        return try XCTUnwrap(clip.id)
    }

    func testAssignSlotBindsAndFetchesBack() throws {
        let store = try makeStore()
        let id = try insertText(store, "hello", saved: true)

        try store.assignSlot(3, id: id)

        let found = try store.clipForSlot(3)
        XCTAssertEqual(found?.textContent, "hello")
        XCTAssertEqual(found?.slotIndex, 3)
    }

    func testAssigningAnOccupiedSlotMovesIt() throws {
        let store = try makeStore()
        let first = try insertText(store, "first", saved: true)
        let second = try insertText(store, "second", saved: true)

        try store.assignSlot(1, id: first)
        try store.assignSlot(1, id: second)

        XCTAssertEqual(try store.clipForSlot(1)?.textContent, "second")
        let firstClip = try store.fetchAll().first { $0.id == first }
        XCTAssertNil(firstClip?.slotIndex, "the previous holder is unbound, not duplicated")
    }

    func testAssigningASlotSavesTheClip() throws {
        let store = try makeStore()
        let id = try insertText(store, "not yet saved", saved: false)

        try store.assignSlot(5, id: id)

        let clip = try store.fetchAll().first { $0.id == id }
        XCTAssertEqual(clip?.saved, true, "a slot implies the clip is kept")
    }

    func testAssignNilClearsTheSlotButKeepsTheClipSaved() throws {
        let store = try makeStore()
        let id = try insertText(store, "bound", saved: true)
        try store.assignSlot(7, id: id)

        try store.assignSlot(nil, id: id)

        XCTAssertNil(try store.clipForSlot(7))
        XCTAssertEqual(try store.fetchAll().first?.saved, true)
    }

    func testDeletingASlotBoundClipFreesTheSlot() throws {
        let store = try makeStore()
        let id = try insertText(store, "doomed", saved: true)
        try store.assignSlot(2, id: id)

        try store.delete(id: id)

        XCTAssertNil(try store.clipForSlot(2))
    }

    func testSavedListsSlotBoundClipsFirstInSlotOrder() throws {
        let store = try makeStore()
        let base = Date()
        let a = try insertText(store, "a", saved: true, at: base.addingTimeInterval(-30))
        let b = try insertText(store, "b", saved: true, at: base.addingTimeInterval(-20))
        _ = try insertText(store, "c", saved: true, at: base.addingTimeInterval(-10))
        try store.assignSlot(2, id: a)
        try store.assignSlot(1, id: b)

        let saved = try store.saved()

        XCTAssertEqual(saved.compactMap { $0.textContent }, ["b", "a", "c"])
    }

    func testHistoryExcludesSavedClips() throws {
        let store = try makeStore()
        _ = try insertText(store, "kept", saved: true)
        _ = try insertText(store, "passing", saved: false)

        let history = try store.history()

        XCTAssertEqual(history.compactMap { $0.textContent }, ["passing"])
    }

    func testInsertPreservesUUIDAndOriginDevice() throws {
        let store = try makeStore()
        let clip = Clip(id: nil, uuid: "fixed-uuid-1", type: .text, textContent: "hi", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0, originDevice: "device-A")
        _ = try store.insert(clip)

        let all = try store.fetchAll()
        XCTAssertEqual(all.first?.uuid, "fixed-uuid-1")
        XCTAssertEqual(all.first?.originDevice, "device-A")
    }

    func testClipExistsByUUID() throws {
        let store = try makeStore()
        _ = try store.insert(Clip(id: nil, uuid: "known", type: .text, textContent: "x", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))

        XCTAssertTrue(try store.clipExists(uuid: "known"))
        XCTAssertFalse(try store.clipExists(uuid: "unknown"))
    }

    func testDefaultUUIDIsGeneratedAndUnique() throws {
        let store = try makeStore()
        let a = try store.insert(Clip(id: nil, type: .text, textContent: "a", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))
        let b = try store.insert(Clip(id: nil, type: .text, textContent: "b", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))

        XCTAssertFalse(a.uuid.isEmpty)
        XCTAssertNotEqual(a.uuid, b.uuid)
        XCTAssertNil(a.originDevice)
    }

    func testMigrationBackfillsUUIDOnPreExistingRows() throws {
        // Simulate a v1 database: create the v1 schema and insert a row with no uuid column,
        // then open it through ClipStore (which runs both migrations) and confirm backfill.
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "clip") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull()
                t.column("textContent", .text)
                t.column("imageData", .blob)
                t.column("filePath", .text)
                t.column("sourceApp", .text)
                t.column("timestamp", .datetime).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            // Mark migration 1 as already applied so ClipStore only runs migration 2.
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('createClip')")
            try db.execute(sql: """
                INSERT INTO clip (type, textContent, timestamp, pinned, sortOrder)
                VALUES ('text', 'legacy row', ?, 0, 0)
                """, arguments: [Date()])
        }

        let store = try ClipStore(dbQueue: dbQueue, retentionCount: 500)

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all[0].uuid.isEmpty, "migration must backfill a uuid on pre-existing rows")
        XCTAssertNil(all[0].originDevice)
    }
}
