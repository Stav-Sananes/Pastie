// Sources/Pastie/Sync/PeerTransport.swift
import Foundation
import Network

/// One peer connection, viewed as "send bytes / receive whole messages".
/// SyncCoordinator talks only to this, never to Network.framework directly.
protocol PeerTransport: AnyObject {
    var peerID: String { get }
    var peerName: String { get }
    var onReceive: ((Data) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    func send(_ payload: Data)
    func close()
}

final class NWConnectionTransport: PeerTransport {
    let peerID: String
    let peerName: String
    var onReceive: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private let connection: NWConnection
    private let decoder = FrameDecoder()
    private let queue: DispatchQueue
    private var isClosed = false

    init(connection: NWConnection, peerID: String, peerName: String, queue: DispatchQueue) {
        self.connection = connection
        self.peerID = peerID
        self.peerName = peerName
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.closeOnQueue()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveLoop()
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                do {
                    for message in try self.decoder.append(data) {
                        self.onReceive?(message)
                    }
                } catch {
                    // A desynced or hostile stream: drop the connection rather than
                    // guess at resyncing the framing. Discovery will re-establish it.
                    NSLog("NWConnectionTransport: framing error from \(self.peerName): \(error)")
                    self.closeOnQueue()
                    return
                }
            }

            if isComplete || error != nil {
                self.closeOnQueue()
                return
            }
            self.receiveLoop()
        }
    }

    func send(_ payload: Data) {
        connection.send(content: MessageFraming.frame(payload), completion: .contentProcessed { error in
            if let error {
                NSLog("NWConnectionTransport: send failed: \(error)")
            }
        })
    }

    func close() {
        // Hop onto `queue` — the same serial queue NWConnection drives its own
        // stateUpdateHandler/receive callbacks on — so the isClosed check-and-set
        // below is never racing an internal teardown path. Captures self strongly
        // (not weak): a caller that calls close() and immediately drops its last
        // reference must still get exactly one onClose callback, not zero.
        queue.async {
            self.closeOnQueue()
        }
    }

    /// Must only be called while running on `queue`. Idempotent: onClose fires
    /// exactly once no matter how many teardown paths call this or how many
    /// times close() itself is called.
    private func closeOnQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !isClosed else { return }
        isClosed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose?()
    }
}
