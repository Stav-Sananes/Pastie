import XCTest
@testable import Pastie

final class MessageFramingTests: XCTestCase {
    func testFrameThenDecodeSingleMessage() throws {
        let payload = Data("hello".utf8)
        let decoder = FrameDecoder()

        let out = try decoder.append(MessageFraming.frame(payload))

        XCTAssertEqual(out, [payload])
    }

    func testTwoMessagesInOneChunk() throws {
        let a = Data("first".utf8)
        let b = Data("second".utf8)
        let decoder = FrameDecoder()

        let out = try decoder.append(MessageFraming.frame(a) + MessageFraming.frame(b))

        XCTAssertEqual(out, [a, b])
    }

    func testMessageSplitAcrossChunks() throws {
        let payload = Data("a reasonably long payload".utf8)
        let framed = MessageFraming.frame(payload)
        let decoder = FrameDecoder()

        // Split mid-payload.
        let firstHalf = framed.prefix(8)
        let secondHalf = framed.suffix(from: 8)

        XCTAssertEqual(try decoder.append(Data(firstHalf)), [], "incomplete message yields nothing yet")
        XCTAssertEqual(try decoder.append(Data(secondHalf)), [payload])
    }

    func testMessageSplitInsideLengthPrefix() throws {
        let payload = Data("x".utf8)
        let framed = MessageFraming.frame(payload)
        let decoder = FrameDecoder()

        XCTAssertEqual(try decoder.append(Data(framed.prefix(2))), [], "partial length prefix yields nothing")
        XCTAssertEqual(try decoder.append(Data(framed.suffix(from: 2))), [payload])
    }

    func testByteAtATimeDelivery() throws {
        let payload = Data("streamed".utf8)
        let framed = MessageFraming.frame(payload)
        let decoder = FrameDecoder()

        var collected: [Data] = []
        for byte in framed {
            collected += try decoder.append(Data([byte]))
        }

        XCTAssertEqual(collected, [payload])
    }

    func testOversizeMessageIsRejected() {
        let decoder = FrameDecoder()
        var header = Data()
        let huge = UInt32(MessageFraming.maxMessageBytes + 1)
        header.append(UInt8((huge >> 24) & 0xFF))
        header.append(UInt8((huge >> 16) & 0xFF))
        header.append(UInt8((huge >> 8) & 0xFF))
        header.append(UInt8(huge & 0xFF))

        XCTAssertThrowsError(try decoder.append(header))
    }
}
