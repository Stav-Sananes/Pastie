import CommonCrypto
import Foundation
import Security

/// Turns the user's shared passphrase into the 32-byte TLS pre-shared key.
///
/// PBKDF2 rather than HKDF on purpose: HKDF assumes high-entropy input, and a
/// human-chosen passphrase is not. Without a password-hardening KDF, anyone who
/// captures a single handshake could brute-force a weak passphrase offline.
enum SyncKeyDerivation {
    static let iterations = 200_000
    static let keyLength = 32
    private static let salt = Data("com.stav.pastie.sync.v1".utf8)

    static func deriveKey(passphrase: String) -> Data {
        let passphraseBytes = Array(passphrase.utf8)
        let saltBytes = [UInt8](salt)
        var derived = [UInt8](repeating: 0, count: keyLength)

        let status = derived.withUnsafeMutableBytes { derivedBytes -> Int32 in
            saltBytes.withUnsafeBufferPointer { saltPtr in
                passphraseBytes.withUnsafeBufferPointer { passphrasePtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passphrasePtr.baseAddress?.withMemoryRebound(to: Int8.self, capacity: passphraseBytes.count) { $0 },
                        passphraseBytes.count,
                        saltPtr.baseAddress,
                        saltBytes.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            NSLog("SyncKeyDerivation: PBKDF2 failed with status \(status)")
            return Data(repeating: 0, count: keyLength)
        }
        return Data(derived)
    }
}

protocol SecretStore: AnyObject {
    func passphrase() -> String?
    func setPassphrase(_ value: String?)
}

/// Stores the sync passphrase in the login Keychain. Never UserDefaults —
/// that is a plist readable by anything running as this user.
final class KeychainSecretStore: SecretStore {
    private let service: String
    private let account = "sync-passphrase"

    init(service: String = "com.stav.pastie") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func passphrase() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setPassphrase(_ value: String?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let value, !value.isEmpty else { return }

        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("KeychainSecretStore: failed to store passphrase, status \(status)")
        }
    }
}

final class InMemorySecretStore: SecretStore {
    private var value: String?

    init(passphrase: String? = nil) {
        self.value = passphrase
    }

    func passphrase() -> String? { value }

    func setPassphrase(_ value: String?) { self.value = value }
}
