import Foundation
import GRDB

enum ClipType: String, Codable {
    case text
    case image
    case file
}

struct Clip: Identifiable, Equatable, Codable {
    var id: Int64?
    /// Global identity, stable across machines. Basis for cross-peer dedup.
    var uuid: String = UUID().uuidString
    var type: ClipType
    var textContent: String?
    var imageData: Data?
    var filePath: String?
    var sourceApp: String?
    var timestamp: Date
    var pinned: Bool
    var sortOrder: Int64
    /// Device ID this clip arrived from; nil for locally-captured clips.
    /// Non-nil is the loop-prevention guard: such clips are never re-broadcast.
    var originDevice: String? = nil
}

extension Clip: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "clip"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Clip {
    func hasSameContent(as other: Clip) -> Bool {
        guard type == other.type else { return false }
        switch type {
        case .text: return textContent == other.textContent
        case .image: return imageData == other.imageData
        case .file: return filePath == other.filePath
        }
    }
}
