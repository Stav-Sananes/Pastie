import Foundation
import GRDB

final class ClipStore {
    private let dbQueue: DatabaseQueue
    private let retentionCountProvider: () -> Int

    /// Designated initializer: reads the retention limit fresh on every eviction check via
    /// the provider closure, so a live preference change takes effect immediately.
    init(dbQueue: DatabaseQueue, retentionCountProvider: @escaping () -> Int) throws {
        self.dbQueue = dbQueue
        self.retentionCountProvider = retentionCountProvider
        try Self.migrate(dbQueue)
    }

    /// Convenience initializer for callers (and tests) that just want a fixed retention count.
    convenience init(dbQueue: DatabaseQueue, retentionCount: Int = 500) throws {
        try self.init(dbQueue: dbQueue, retentionCountProvider: { retentionCount })
    }

    private static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createClip") { db in
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
        }
        migrator.registerMigration("savedAndRichPayload") { db in
            try db.alter(table: "clip") { t in
                t.rename(column: "pinned", to: "saved")
                t.add(column: "rtfData", .blob)
                t.add(column: "slotIndex", .integer)
            }
            // Partial unique index: many clips may have no slot, but a slot belongs to one clip.
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS clip_on_slotIndex
                ON clip(slotIndex) WHERE slotIndex IS NOT NULL
                """)
        }
        try migrator.migrate(dbQueue)
    }

    @discardableResult
    func insert(_ clip: Clip) throws -> Clip {
        var clip = clip
        try dbQueue.write { db in
            try clip.insert(db)
        }
        try evictIfNeeded()
        return clip
    }

    private func evictIfNeeded() throws {
        let retentionCount = retentionCountProvider()
        try dbQueue.write { db in
            let count = try Clip.filter(Column("saved") == false).fetchCount(db)
            guard count > retentionCount else { return }
            let excess = count - retentionCount
            let toDelete = try Clip
                .filter(Column("saved") == false)
                .order(Column("timestamp").asc)
                .limit(excess)
                .fetchAll(db)
            for clip in toDelete {
                try clip.delete(db)
            }
        }
    }

    func setSaved(_ saved: Bool, id: Int64) throws {
        try dbQueue.write { db in
            if var clip = try Clip.fetchOne(db, key: id) {
                clip.saved = saved
                try clip.update(db)
            }
        }
    }

    /// Valid quick-paste slots. Slot numbers outside this range are ignored.
    static let slotRange = 1...9

    /// Binds `id` to `slot`, or unbinds it when `slot` is nil. If another clip already holds the
    /// slot, that clip is unbound first — assigning an occupied slot moves it. A clip given a slot
    /// is saved in the same write, because a slot only means anything on a Saved clip.
    func assignSlot(_ slot: Int?, id: Int64) throws {
        if let slot, !Self.slotRange.contains(slot) {
            NSLog("ClipStore: ignoring out-of-range slot \(slot)")
            return
        }
        try dbQueue.write { db in
            if let slot {
                if var previous = try Clip.filter(Column("slotIndex") == slot).fetchOne(db), previous.id != id {
                    previous.slotIndex = nil
                    try previous.update(db)
                }
            }
            guard var clip = try Clip.fetchOne(db, key: id) else { return }
            clip.slotIndex = slot
            if slot != nil { clip.saved = true }
            try clip.update(db)
        }
    }

    func clipForSlot(_ slot: Int) throws -> Clip? {
        try dbQueue.read { db in
            try Clip.filter(Column("slotIndex") == slot).fetchOne(db)
        }
    }

    /// Saved clips for the popup's Saved section: slot-bound clips first in slot order, then the
    /// unbound ones newest-first.
    func saved() throws -> [Clip] {
        try dbQueue.read { db in
            let all = try Clip.filter(Column("saved") == true).fetchAll(db)
            let bound = all.filter { $0.slotIndex != nil }.sorted { ($0.slotIndex ?? 0) < ($1.slotIndex ?? 0) }
            let unbound = all.filter { $0.slotIndex == nil }.sorted { $0.timestamp > $1.timestamp }
            return bound + unbound
        }
    }

    /// The evicting stream: everything the user has not kept, newest first.
    func history() throws -> [Clip] {
        try dbQueue.read { db in
            try Clip.filter(Column("saved") == false).order(Column("timestamp").desc).fetchAll(db)
        }
    }

    func delete(id: Int64) throws {
        try dbQueue.write { db in
            _ = try Clip.deleteOne(db, key: id)
        }
    }

    func clearAll() throws {
        try dbQueue.write { db in
            _ = try Clip.filter(Column("saved") == false).deleteAll(db)
        }
    }

    func fetchAll() throws -> [Clip] {
        try dbQueue.read { db in
            try Clip.order(Column("timestamp").desc).fetchAll(db)
        }
    }

    func mostRecent() throws -> Clip? {
        try dbQueue.read { db in
            try Clip.order(Column("timestamp").desc).fetchOne(db)
        }
    }
}
