// Sources/Pastie/Sync/SyncService.swift
import Foundation
import Network

struct SyncPeerStatus: Identifiable, Equatable {
    enum State: Equatable {
        case connected
        case authenticationFailed
        case disconnected
    }

    let id: String
    let name: String
    let state: State
}

/// Owns the Bonjour listener, the browser, and every live peer connection.
///
/// Authentication and encryption both come from TLS with a pre-shared key derived
/// from the user's passphrase: a peer that doesn't know it fails the handshake and
/// never reaches application code.
final class SyncService {
    static let serviceType = "_pastie._tcp"

    private let coordinator: SyncCoordinator
    private let deviceID: String
    private let deviceName: String
    private let passphrase: String
    private let requestedPort: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.stav.pastie.sync")

    private var listener: NWListener?
    private var browser: NWBrowser?

    /// Guards `transports`, `_peers`, and `generation`, which are mutated on `queue` but read
    /// from arbitrary threads (`transportsProvider`, the public `peers` getter). Never call
    /// `onPeersChanged` while holding this — it can run arbitrary UI code.
    private let lock = NSLock()
    private var transports: [String: NWConnectionTransport] = [:]
    private var _peers: [SyncPeerStatus] = []

    /// Bumped by both `start()` and `stop()`. `adopt()` captures the current value at entry;
    /// every later callback that would mutate `transports`/`_peers` for that connection
    /// (registration, `.ready`, `.failed`/`.cancelled` teardown, `onClose`) re-checks it against
    /// the live value and backs out if they no longer match.
    ///
    /// This is what makes `stop()` actually stop: `listener.newConnectionHandler` and
    /// `browseResultsChangedHandler` run on `queue`, while `stop()` runs on the caller's thread,
    /// so a callback already in flight when `stop()` returns can still reach `adopt()` afterward.
    /// Without this check it would find `transports` freshly emptied, register itself as if
    /// nothing had happened, and run forever uncounted — sync would keep working after the user
    /// turned it off. It also means a stale `onClose` from a session `stop()` already tore down
    /// can never touch a later session's state, so there's no separate stop()-then-start() race
    /// to guard against on top of this.
    private var generation: UInt64 = 0

    /// Peer IDs whose most recent connection attempt failed the TLS-PSK handshake.
    /// Consulted and cleared by `removeTransport` so a wrong-passphrase failure isn't
    /// overwritten by the plain `disconnected` that follows from tearing the
    /// connection down. Only ever touched from `queue`, so it needs no lock of its own.
    private var authFailedPeerIDs: Set<String> = []

    var onPeersChanged: (([SyncPeerStatus]) -> Void)?

    var peers: [SyncPeerStatus] {
        lock.lock()
        defer { lock.unlock() }
        return _peers
    }

    var listeningPort: NWEndpoint.Port? { listener?.port }

    init(
        coordinator: SyncCoordinator,
        deviceID: String,
        deviceName: String,
        passphrase: String,
        port: NWEndpoint.Port = .any
    ) {
        self.coordinator = coordinator
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.passphrase = passphrase
        self.requestedPort = port
        coordinator.transportsProvider = { [weak self] in
            guard let self else { return [] }
            self.lock.lock()
            defer { self.lock.unlock() }
            return Array(self.transports.values)
        }
    }

    // MARK: - Parameters

    /// TLS with a pre-shared key derived from the passphrase. Apple's TLS stack does
    /// the authentication and encryption; we supply the key and never touch crypto
    /// primitives ourselves.
    private func makeParameters() -> NWParameters {
        let key = SyncKeyDerivation.deriveKey(passphrase: passphrase)
        let tlsOptions = NWProtocolTLS.Options()

        let keyData = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = Data("pastie-sync".utf8).withUnsafeBytes { DispatchData(bytes: $0) }

        sec_protocol_options_add_pre_shared_key(
            tlsOptions.securityProtocolOptions,
            keyData as __DispatchData,
            identityData as __DispatchData
        )
        sec_protocol_options_append_tls_ciphersuite(
            tlsOptions.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        )

        let parameters = NWParameters(tls: tlsOptions)
        parameters.includePeerToPeer = true
        return parameters
    }

    // MARK: - Lifecycle

    func start() throws {
        // Calling start() again while already running would otherwise overwrite `listener`/
        // `browser` without cancelling the previous pair, leaking them. Treat a second start()
        // as a no-op rather than guessing the caller meant to restart.
        guard listener == nil else { return }

        lock.lock()
        generation &+= 1
        lock.unlock()

        let parameters = makeParameters()

        let listener = try NWListener(using: parameters, on: requestedPort)
        listener.service = NWListener.Service(name: deviceName, type: Self.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            self?.adopt(connection: connection, peerName: connection.endpoint.debugDescription)
        }
        listener.start(queue: queue)
        self.listener = listener

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                if case let .service(name, _, _, _) = result.endpoint, name == self.deviceName {
                    continue // don't dial ourselves
                }
                self.connect(to: result.endpoint)
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil

        lock.lock()
        generation &+= 1
        let closingTransports = Array(transports.values)
        transports.removeAll()
        _peers = []
        let snapshot = _peers
        lock.unlock()

        for transport in closingTransports {
            transport.close()
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPeersChanged?(snapshot)
        }
    }

    // MARK: - Connections

    func connect(to endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: makeParameters())
        adopt(connection: connection, peerName: endpoint.debugDescription)
    }

    private func adopt(connection: NWConnection, peerName: String) {
        let peerID = peerName

        lock.lock()
        let capturedGeneration = generation
        lock.unlock()

        let transport = NWConnectionTransport(connection: connection, peerID: peerID, peerName: peerName, queue: queue)
        transport.onReceive = { [weak self] data in
            self?.coordinator.handleIncoming(data, fromPeer: peerID)
        }
        transport.onClose = { [weak self] in
            self?.removeTransport(peerID: peerID, name: peerName, generation: capturedGeneration)
        }

        lock.lock()
        guard generation == capturedGeneration, transports[peerID] == nil else {
            lock.unlock()
            // Either a stop()/start() happened between this connection being handed to us and
            // now, or we already have a live transport for this peer — either way, this
            // connection was never registered anywhere, so nothing else will ever cancel it.
            connection.cancel()
            return
        }
        transports[peerID] = transport
        lock.unlock()

        // Start the transport first, then install our own state handler: NWConnectionTransport.start()
        // sets connection.stateUpdateHandler itself (to drive its own teardown-on-failure), and whichever
        // handler is assigned last is the one that survives. Installing ours second means we see
        // .ready/.failed/.cancelled directly, and we take over driving teardown ourselves below.
        transport.start()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.updatePeer(SyncPeerStatus(id: peerID, name: peerName, state: .connected), generation: capturedGeneration)
            case let .failed(error):
                // A wrong passphrase surfaces here as a TLS handshake failure. This must
                // be visible in the UI: a mistyped passphrase is the likeliest failure in
                // this whole feature, and silence is the worst possible response to it.
                NSLog("SyncService: connection to \(peerName) failed: \(error)")
                self.authFailedPeerIDs.insert(peerID)
                self.closeTransport(for: peerID, generation: capturedGeneration)
            case .cancelled:
                self.closeTransport(for: peerID, generation: capturedGeneration)
            default:
                break
            }
        }
    }

    /// Looks up the still-registered transport for `peerID` and closes it, but only if
    /// `capturedGeneration` (from the connection's `adopt()` call) still matches the live
    /// session — otherwise a stale event from an old session could reach into a new session's
    /// `transports` and close a transport that happens to share the same peer ID. Since we now
    /// own `connection.stateUpdateHandler` (see `adopt`), we're responsible for driving teardown
    /// on `.failed`/`.cancelled` ourselves rather than relying on NWConnectionTransport's own
    /// (now-overwritten) handler. `close()` is idempotent and its `onClose` callback — which
    /// calls `removeTransport` — fires exactly once regardless of how teardown was triggered.
    private func closeTransport(for peerID: String, generation capturedGeneration: UInt64) {
        lock.lock()
        guard generation == capturedGeneration else {
            lock.unlock()
            return
        }
        let transport = transports[peerID]
        lock.unlock()
        transport?.close()
    }

    private func removeTransport(peerID: String, name: String, generation capturedGeneration: UInt64) {
        lock.lock()
        guard generation == capturedGeneration else {
            lock.unlock()
            return
        }
        transports[peerID] = nil
        lock.unlock()

        let wasAuthFailure = authFailedPeerIDs.remove(peerID) != nil
        let state: SyncPeerStatus.State = wasAuthFailure ? .authenticationFailed : .disconnected
        updatePeer(SyncPeerStatus(id: peerID, name: name, state: state), generation: capturedGeneration)
    }

    /// The single place `_peers` is mutated and `onPeersChanged` is scheduled. Guarded by
    /// `capturedGeneration` so a connection event that no longer belongs to the live session
    /// (superseded by a `stop()` or `start()` in between) can't re-populate `_peers`.
    private func updatePeer(_ status: SyncPeerStatus, generation capturedGeneration: UInt64) {
        lock.lock()
        guard generation == capturedGeneration else {
            lock.unlock()
            return
        }
        if let index = _peers.firstIndex(where: { $0.id == status.id }) {
            _peers[index] = status
        } else {
            _peers.append(status)
        }
        let snapshot = _peers
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.onPeersChanged?(snapshot)
        }
    }
}
