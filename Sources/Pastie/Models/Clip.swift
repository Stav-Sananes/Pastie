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
    /// Kept deliberately by the user: exempt from retention eviction, shown in the popup's
    /// Saved section, and the only kind of Clip that may hold a quick-paste slot.
    /// Renamed from v1's `pinned` — see docs/adr/0003-saved-replaces-pinned.md.
    var saved: Bool
    var sortOrder: Int64
    /// public.rtf bytes captured alongside `textContent`, when the source offered them and they
    /// fit under the configured cap. See docs/adr/0002-store-rtf-only-as-rich-payload.md.
    var rtfData: Data? = nil
    /// Quick-paste slot 1–9, or nil. Only Saved clips hold one; unique across the table.
    var slotIndex: Int? = nil
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
