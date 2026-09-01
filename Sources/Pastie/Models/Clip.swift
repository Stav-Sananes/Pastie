import Foundation
import GRDB

enum ClipType: String, Codable {
    case text
    case image
    case file
}

struct Clip: Identifiable, Equatable, Codable {
    var id: Int64?
    var type: ClipType
    var textContent: String?
    var imageData: Data?
    var filePath: String?
    var sourceApp: String?
    var timestamp: Date
    var pinned: Bool
    var sortOrder: Int64
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
