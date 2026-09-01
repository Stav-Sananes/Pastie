// Tests/PastieTests/SyncMessageTests.swift
import XCTest
@testable import Pastie

final class SyncMessageTests: XCTestCase {
    func testTextMessageRoundTrips() throws {
        let message = SyncMessage(clipUUID: "u1", type: .text, textContent: "hello world", imageData: nil, fileName: nil, fileData: nil, timestamp: Date(timeIntervalSince1970: 1_700_000_000), originDeviceID: "dev-1", originDeviceName: "MacBook Pro")

        let decoded = try SyncMessage.decode(try message.encoded())

        XCTAssertEqual(decoded, message)
    }

    func testImageMessageRoundTrips() throws {
        let bytes = Data((0..<2048).map { UInt8($0 % 256) })
        let message = SyncMessage(clipUUID: "u2", type: .image, textContent: nil, imageData: bytes, fileName: nil, fileData: nil, timestamp: Date(timeIntervalSince1970: 1_700_000_001), originDeviceID: "dev-1", originDeviceName: "MacBook Pro")

        let decoded = try SyncMessage.decode(try message.encoded())

        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded.imageData, bytes)
    }

    func testFileMessageRoundTrips() throws {
        let bytes = Data("file contents here".utf8)
        let message = SyncMessage(clipUUID: "u3", type: .file, textContent: nil, imageData: nil, fileName: "report.pdf", fileData: bytes, timestamp: Date(timeIntervalSince1970: 1_700_000_002), originDeviceID: "dev-2", originDeviceName: "Mac mini")

        let decoded = try SyncMessage.decode(try message.encoded())

        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded.fileName, "report.pdf")
    }

    func testEncodingDoesNotBase64InflateBinaryPayloads() throws {
        // A binary plist stores Data natively; JSON's base64 would be ~4/3 the size.
        let bytes = Data(repeating: 0xAB, count: 60_000)
        let message = SyncMessage(clipUUID: "u4", type: .image, textContent: nil, imageData: bytes, fileName: nil, fileData: nil, timestamp: Date(), originDeviceID: "d", originDeviceName: "n")

        let encoded = try message.encoded()

        XCTAssertLessThan(encoded.count, 70_000, "payload should not be base64-inflated")
    }

    func testDecodeRejectsGarbage() {
        XCTAssertThrowsError(try SyncMessage.decode(Data("not a plist".utf8)))
    }
}
