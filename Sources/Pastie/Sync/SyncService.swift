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
    private var transports: [String: NWConnectionTransport] = [:]
    private(set) var peers: [SyncPeerStatus] = []

    var onPeersChanged: (([SyncPeerStatus]) -> Void)?

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
        for transport in transports.values {
            transport.close()
        }
        transports.removeAll()
        peers = []
        onPeersChanged?(peers)
    }

    // MARK: - Connections

    func connect(to endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: makeParameters())
        adopt(connection: connection, peerName: endpoint.debugDescription)
    }

    private func adopt(connection: NWConnection, peerName: String) {
        let peerID = peerName
        guard transports[peerID] == nil else { return }

        let transport = NWConnectionTransport(connection: connection, peerID: peerID, peerName: peerName, queue: queue)
        transport.onReceive = { [weak self] data in
            self?.coordinator.handleIncoming(data, fromPeer: peerID)
        }
        transport.onClose = { [weak self] in
            self?.removeTransport(peerID: peerID, name: peerName, failedAuth: false)
        }

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.updatePeer(SyncPeerStatus(id: peerID, name: peerName, state: .connected))
            case let .failed(error):
                // A wrong passphrase surfaces here as a TLS handshake failure. This must
                // be visible in the UI: a mistyped passphrase is the likeliest failure in
                // this whole feature, and silence is the worst possible response to it.
                NSLog("SyncService: connection to \(peerName) failed: \(error)")
                self.removeTransport(peerID: peerID, name: peerName, failedAuth: true)
            case .cancelled:
                self.removeTransport(peerID: peerID, name: peerName, failedAuth: false)
            default:
                break
            }
        }

        transports[peerID] = transport
        transport.start()
    }

    private func removeTransport(peerID: String, name: String, failedAuth: Bool) {
        transports[peerID] = nil
        updatePeer(SyncPeerStatus(id: peerID, name: name, state: failedAuth ? .authenticationFailed : .disconnected))
    }

    private func updatePeer(_ status: SyncPeerStatus) {
        if let index = peers.firstIndex(where: { $0.id == status.id }) {
            peers[index] = status
        } else {
            peers.append(status)
        }
        let snapshot = peers
        DispatchQueue.main.async { [weak self] in
            self?.onPeersChanged?(snapshot)
        }
    }
}
