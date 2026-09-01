import Foundation
import GRDB

final class ClipStore {
    private let dbQueue: DatabaseQueue
    private let retentionCount: Int

    init(dbQueue: DatabaseQueue, retentionCount: Int = 500) throws {
        self.dbQueue = dbQueue
        self.retentionCount = retentionCount
        try Self.migrate(dbQueue)
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
        try migrator.migrate(dbQueue)
    }

    @discardableResult
    func insert(_ clip: Clip) throws -> Clip {
        var clip = clip
        try dbQueue.write { db in
            try clip.insert(db)
        }
        return clip
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
