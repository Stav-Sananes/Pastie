// Sources/Pastie/Sync/SyncCoordinator.swift
import Foundation

/// The bridge between the sync module and v1's storage.
///
/// Two invariants keep the mesh from eating itself:
///  - a clip with `originDevice != nil` is never broadcast (no ping-pong loops)
///  - a message whose `clipUUID` already exists is dropped (no double inserts
///    when the same clip reaches us by two paths)
final class SyncCoordinator {
    private let store: ClipStore
    private let fileStore: SyncedFileStore
    private let deviceID: String
    private let deviceName: String
    private let maxFileBytes: Int
    private let now: () -> Date

    /// Supplies the currently-connected peers. Set by SyncService; defaults to none.
    var transportsProvider: () -> [PeerTransport] = { [] }

    init(
        store: ClipStore,
        fileStore: SyncedFileStore,
        deviceID: String,
        deviceName: String,
        maxFileBytes: Int = 25 * 1024 * 1024,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.fileStore = fileStore
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.maxFileBytes = maxFileBytes
        self.now = now
    }

    // MARK: - Outbound

    func handleLocalClip(_ clip: Clip) {
        guard clip.originDevice == nil else { return }
        guard let message = makeMessage(for: clip) else { return }

        do {
            let payload = try message.encoded()
            // The wire framing itself rejects anything over this ceiling by tearing the
            // connection down (FrameDecoder.messageTooLarge) — catch it here instead so one
            // oversize clip (of any type, not just .file) can't take out a peer link.
            guard payload.count <= MessageFraming.maxMessageBytes else {
                NSLog("SyncCoordinator: encoded clip \(clip.uuid) is \(payload.count) bytes, over the \(MessageFraming.maxMessageBytes) framing ceiling — not synced")
                return
            }
            for transport in transportsProvider() {
                transport.send(payload)
            }
        } catch {
            NSLog("SyncCoordinator: failed to encode clip \(clip.uuid): \(error)")
        }
    }

    private func makeMessage(for clip: Clip) -> SyncMessage? {
        var fileName: String?
        var fileData: Data?

        if clip.type == .file {
            guard let path = clip.filePath else { return nil }
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url) else {
                NSLog("SyncCoordinator: could not read file clip at \(path)")
                return nil
            }
            guard data.count <= maxFileBytes else {
                NSLog("SyncCoordinator: file clip \(url.lastPathComponent) is \(data.count) bytes, over the \(maxFileBytes) ceiling — not synced")
                return nil
            }
            fileName = url.lastPathComponent
            fileData = data
        }

        return SyncMessage(
            clipUUID: clip.uuid,
            type: clip.type,
            textContent: clip.textContent,
            imageData: clip.imageData,
            fileName: fileName,
            fileData: fileData,
            timestamp: clip.timestamp,
            originDeviceID: deviceID,
            originDeviceName: deviceName
        )
    }

    // MARK: - Inbound

    func handleIncoming(_ data: Data, fromPeer peerID: String) {
        let message: SyncMessage
        do {
            message = try SyncMessage.decode(data)
        } catch {
            NSLog("SyncCoordinator: undecodable message from \(peerID): \(error)")
            return
        }

        do {
            guard try !store.clipExists(uuid: message.clipUUID) else { return }
        } catch {
            NSLog("SyncCoordinator: dedup lookup failed: \(error)")
            return
        }

        var filePath: String?
        if message.type == .file {
            guard let bytes = message.fileData, let name = message.fileName else { return }
            do {
                filePath = try fileStore.write(data: bytes, clipUUID: message.clipUUID, fileName: name)
            } catch {
                NSLog("SyncCoordinator: could not store received file: \(error)")
                return
            }
        }

        // A peer with a fast clock would otherwise pin its clips to the top of the list.
        let timestamp = min(message.timestamp, now())

        let clip = Clip(
            id: nil,
            uuid: message.clipUUID,
            type: message.type,
            textContent: message.textContent,
            imageData: message.imageData,
            filePath: filePath,
            sourceApp: message.originDeviceName,
            timestamp: timestamp,
            pinned: false,
            sortOrder: 0,
            originDevice: message.originDeviceID
        )

        do {
            _ = try store.insert(clip)
        } catch {
            NSLog("SyncCoordinator: failed to insert received clip: \(error)")
        }
    }
}
