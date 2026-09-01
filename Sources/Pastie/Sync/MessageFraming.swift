import Foundation

enum FramingError: Error {
    case messageTooLarge(Int)
}

enum MessageFraming {
    /// Generous ceiling: the largest legitimate message is a 25MB file plus overhead.
    /// Anything past this is a desynced stream or a hostile peer, not a real clip.
    static let maxMessageBytes = 32 * 1024 * 1024

    static func frame(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        var out = Data(capacity: 4 + payload.count)
        out.append(UInt8((length >> 24) & 0xFF))
        out.append(UInt8((length >> 16) & 0xFF))
        out.append(UInt8((length >> 8) & 0xFF))
        out.append(UInt8(length & 0xFF))
        out.append(payload)
        return out
    }
}

/// Accumulates bytes off a stream and hands back complete payloads as they arrive.
final class FrameDecoder {
    private var buffer = Data()

    func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var messages: [Data] = []

        while true {
            guard buffer.count >= 4 else { break }

            let length = Int(buffer[buffer.startIndex]) << 24
                | Int(buffer[buffer.startIndex + 1]) << 16
                | Int(buffer[buffer.startIndex + 2]) << 8
                | Int(buffer[buffer.startIndex + 3])

            guard length <= MessageFraming.maxMessageBytes else {
                throw FramingError.messageTooLarge(length)
            }
            guard buffer.count >= 4 + length else { break }

            let payloadStart = buffer.startIndex + 4
            let payload = Data(buffer[payloadStart..<(payloadStart + length)])
            messages.append(payload)
            buffer = Data(buffer[(payloadStart + length)...])
        }

        return messages
    }
}
