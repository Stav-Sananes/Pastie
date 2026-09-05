// Tests/PastieTests/SyncCoordinatorTests.swift
import XCTest
import GRDB
@testable import Pastie

final class FakeTransport: PeerTransport {
    let peerID: String
    let peerName: String
    var onReceive: ((Data) -> Void)?
    var onClose: (() -> Void)?
    private(set) var sent: [Data] = []

    init(peerID: String = "peer-1", peerName: String = "Peer One") {
        self.peerID = peerID
        self.peerName = peerName
    }

    func send(_ payload: Data) { sent.append(payload) }
    func close() {}
}

final class SyncCoordinatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pastie-coord-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeCoordinator(
        transports: [PeerTransport],
        now: @escaping () -> Date = Date.init
    ) throws -> (SyncCoordinator, ClipStore) {
        let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
        let coordinator = SyncCoordinator(
            store: store,
            fileStore: SyncedFileStore(directory: tempDir),
            deviceID: "this-device",
            deviceName: "This Mac",
            now: now
        )
        coordinator.transportsProvider = { transports }
        return (coordinator, store)
    }

    func testLocalTextClipIsBroadcastToEveryPeer() throws {
        let a = FakeTransport(peerID: "a", peerName: "A")
        let b = FakeTransport(peerID: "b", peerName: "B")
        let (coordinator, _) = try makeCoordinator(transports: [a, b])

        coordinator.handleLocalClip(Clip(id: 1, uuid: "clip-1", type: .text, textContent: "shared", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0))

        XCTAssertEqual(a.sent.count, 1)
        XCTAssertEqual(b.sent.count, 1)
        let message = try SyncMessage.decode(a.sent[0])
        XCTAssertEqual(message.clipUUID, "clip-1")
        XCTAssertEqual(message.textContent, "shared")
        XCTAssertEqual(message.originDeviceID, "this-device")
    }

    func testRemoteClipIsNeverRebroadcast() throws {
        let peer = FakeTransport()
        let (coordinator, _) = try makeCoordinator(transports: [peer])

        // A clip that arrived from another machine: originDevice is set.
        coordinator.handleLocalClip(Clip(id: 1, uuid: "clip-2", type: .text, textContent: "echo", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0, originDevice: "other-device"))

        XCTAssertTrue(peer.sent.isEmpty, "re-broadcasting a received clip would loop forever")
    }

    func testIncomingClipIsInsertedWithOriginDevice() throws {
        let (coordinator, store) = try makeCoordinator(transports: [])
        let message = SyncMessage(clipUUID: "remote-1", type: .text, textContent: "from afar", imageData: nil, fileName: nil, fileData: nil, timestamp: Date(), originDeviceID: "device-B", originDeviceName: "Mac mini")

        coordinator.handleIncoming(try message.encoded(), fromPeer: "device-B")

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].uuid, "remote-1")
        XCTAssertEqual(all[0].textContent, "from afar")
        XCTAssertEqual(all[0].originDevice, "device-B")
    }

    func testDuplicateUUIDIsDropped() throws {
        let (coordinator, store) = try makeCoordinator(transports: [])
        let message = SyncMessage(clipUUID: "dup", type: .text, textContent: "once", imageData: nil, fileName: nil, fileData: nil, timestamp: Date(), originDeviceID: "device-B", originDeviceName: "Mac mini")

        coordinator.handleIncoming(try message.encoded(), fromPeer: "device-B")
        coordinator.handleIncoming(try message.encoded(), fromPeer: "device-C")

        XCTAssertEqual(try store.fetchAll().count, 1, "same clip arriving twice must insert once")
    }

    func testFutureTimestampIsClampedToNow() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let (coordinator, store) = try makeCoordinator(transports: [], now: { fixedNow })
        let message = SyncMessage(clipUUID: "future", type: .text, textContent: "fast clock", imageData: nil, fileName: nil, fileData: nil, timestamp: fixedNow.addingTimeInterval(86_400), originDeviceID: "device-B", originDeviceName: "Mac mini")

        coordinator.handleIncoming(try message.encoded(), fromPeer: "device-B")

        XCTAssertEqual(try store.fetchAll()[0].timestamp, fixedNow, "a peer with a fast clock must not pin its clips to the top forever")
    }

    func testPastTimestampIsPreserved() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = fixedNow.addingTimeInterval(-3600)
        let (coordinator, store) = try makeCoordinator(transports: [], now: { fixedNow })
        let message = SyncMessage(clipUUID: "past", type: .text, textContent: "older", imageData: nil, fileName: nil, fileData: nil, timestamp: earlier, originDeviceID: "device-B", originDeviceName: "Mac mini")

        coordinator.handleIncoming(try message.encoded(), fromPeer: "device-B")

        XCTAssertEqual(try store.fetchAll()[0].timestamp, earlier)
    }

    func testIncomingFileClipWritesBytesAndPointsAtThem() throws {
        let (coordinator, store) = try makeCoordinator(transports: [])
        let bytes = Data("the actual file".utf8)
        let message = SyncMessage(clipUUID: "file-1", type: .file, textContent: nil, imageData: nil, fileName: "notes.txt", fileData: bytes, timestamp: Date(), originDeviceID: "device-B", originDeviceName: "Mac mini")

        coordinator.handleIncoming(try message.encoded(), fromPeer: "device-B")

        let clip = try XCTUnwrap(try store.fetchAll().first)
        let path = try XCTUnwrap(clip.filePath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), bytes)
    }

    func testOversizeFileClipIsNotBroadcast() throws {
        let peer = FakeTransport()
        let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
        let coordinator = SyncCoordinator(
            store: store,
            fileStore: SyncedFileStore(directory: tempDir),
            deviceID: "this-device",
            deviceName: "This Mac",
            maxFileBytes: 10
        )
        coordinator.transportsProvider = { [peer] }

        // Write an 11-byte file: over the 10-byte ceiling set above.
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let bigFile = tempDir.appendingPathComponent("big.bin")
        try Data(repeating: 0x01, count: 11).write(to: bigFile)

        coordinator.handleLocalClip(Clip(id: 1, uuid: "big", type: .file, textContent: nil, imageData: nil, filePath: bigFile.path, sourceApp: nil, timestamp: Date(), pinned: false, sortOrder: 0))

        XCTAssertTrue(peer.sent.isEmpty, "files over the ceiling are not synced")
    }

    func testMalformedIncomingDataIsIgnored() throws {
        let (coordinator, store) = try makeCoordinator(transports: [])

        coordinator.handleIncoming(Data("garbage".utf8), fromPeer: "device-B")

        XCTAssertTrue(try store.fetchAll().isEmpty)
    }
}
