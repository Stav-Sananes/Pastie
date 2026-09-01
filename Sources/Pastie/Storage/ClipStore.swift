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
        migrator.registerMigration("addSyncColumns") { db in
            try db.alter(table: "clip") { t in
                t.add(column: "uuid", .text)
                t.add(column: "originDevice", .text)
            }
            let ids = try Int64.fetchAll(db, sql: "SELECT id FROM clip WHERE uuid IS NULL")
            for id in ids {
                try db.execute(
                    sql: "UPDATE clip SET uuid = ? WHERE id = ?",
                    arguments: [UUID().uuidString, id]
                )
            }
            try db.create(index: "clip_on_uuid", on: "clip", columns: ["uuid"], unique: true)
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
            let count = try Clip.filter(Column("pinned") == false).fetchCount(db)
            guard count > retentionCount else { return }
            let excess = count - retentionCount
            let toDelete = try Clip
                .filter(Column("pinned") == false)
                .order(Column("timestamp").asc)
                .limit(excess)
                .fetchAll(db)
            for clip in toDelete {
                try clip.delete(db)
            }
        }
    }

    func setPinned(_ pinned: Bool, id: Int64) throws {
        try dbQueue.write { db in
            if var clip = try Clip.fetchOne(db, key: id) {
                clip.pinned = pinned
                try clip.update(db)
            }
        }
    }

    func delete(id: Int64) throws {
        try dbQueue.write { db in
            _ = try Clip.deleteOne(db, key: id)
        }
    }

    func clearAll() throws {
        try dbQueue.write { db in
            _ = try Clip.filter(Column("pinned") == false).deleteAll(db)
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

    func clipExists(uuid: String) throws -> Bool {
        try dbQueue.read { db in
            try Clip.filter(Column("uuid") == uuid).fetchCount(db) > 0
        }
    }
}
