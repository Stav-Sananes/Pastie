// Sources/Pastie/Sync/SyncMessage.swift
import Foundation

/// One clip on the wire. Deliberately flat and self-contained: peers never
/// negotiate schema, they just decode this.
struct SyncMessage: Codable, Equatable {
    let clipUUID: String
    let type: ClipType
    let textContent: String?
    let imageData: Data?
    let fileName: String?
    let fileData: Data?
    let timestamp: Date
    let originDeviceID: String
    let originDeviceName: String

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SyncMessage {
        try PropertyListDecoder().decode(SyncMessage.self, from: data)
    }
}
