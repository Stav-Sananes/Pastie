import XCTest
@testable import Pastie

final class SyncCryptoTests: XCTestCase {
    func testDerivationIsDeterministic() {
        let a = SyncKeyDerivation.deriveKey(passphrase: "correct horse battery staple")
        let b = SyncKeyDerivation.deriveKey(passphrase: "correct horse battery staple")

        XCTAssertEqual(a, b)
    }

    func testDerivationProduces32Bytes() {
        XCTAssertEqual(SyncKeyDerivation.deriveKey(passphrase: "whatever").count, 32)
    }

    func testDifferentPassphrasesProduceDifferentKeys() {
        let a = SyncKeyDerivation.deriveKey(passphrase: "passphrase one")
        let b = SyncKeyDerivation.deriveKey(passphrase: "passphrase two")

        XCTAssertNotEqual(a, b)
    }

    func testEmptyPassphraseStillDerives() {
        XCTAssertEqual(SyncKeyDerivation.deriveKey(passphrase: "").count, 32)
    }

    func testInMemorySecretStoreRoundTrips() {
        let store = InMemorySecretStore()
        XCTAssertNil(store.passphrase())

        store.setPassphrase("hunter2")
        XCTAssertEqual(store.passphrase(), "hunter2")

        store.setPassphrase(nil)
        XCTAssertNil(store.passphrase())
    }
}
