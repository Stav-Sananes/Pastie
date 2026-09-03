# Pastie v2 — Multi-Machine Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A clip copied on one Mac appears in another Mac's Pastie history within seconds, over the LAN, with no server and no account.

**Architecture:** A new isolated `Sync/` module. `NWListener`/`NWBrowser` handle Bonjour advertise/discover; `NWProtocolTLS` takes a passphrase-derived pre-shared key so authentication and encryption come from Apple's TLS stack. `SyncCoordinator` bridges sync to v1's storage: it broadcasts locally-captured clips and inserts received ones (history only — it never writes the pasteboard). When sync is disabled (the default), none of it starts and v1 behavior is unchanged.

**Tech Stack:** Swift 5.9, Network.framework (`NWListener`/`NWBrowser`/`NWConnection`/`NWProtocolTLS`), CommonCrypto (PBKDF2), Security framework (Keychain), GRDB (existing store), SwiftUI, XCTest.

**Spec:** `/Users/stavnsananes/Applications/Pastie/docs/superpowers/specs/2026-09-02-pastie-sync-design.md`

> **Ordering note (added 2026-09-04):** this plan is now the *last* of three. The
> menu/Settings redesign and Pastie v3 both land before it, and v3 changes two
> things this plan depended on:
>
> - **Migration numbering.** v3 claims migration 2 (renaming `pinned` → `saved`,
>   adding `rtfData` and `slotIndex`). Sync's `addSyncColumns` is therefore
>   **migration 3**, registered after v3's. The migration-backfill test below
>   seeds a v1-shaped schema and lets both later migrations run.
> - **`Clip.pinned` no longer exists.** Every `Clip(...)` literal in this plan now
>   passes `saved:`. v3 gives `rtfData` and `slotIndex` default values, so call
>   sites that omit them still compile.
>
> If v3 has *not* landed when you execute this, stop and re-check both points
> rather than adapting the code to a schema that is about to change underneath it.

## Global Constraints

- Platform floor: macOS 13.0 (unchanged from v1).
- Mac ↔ Mac only. No Windows/iOS peers, no cloud or relay transport.
- Bonjour service type: `_pastie._tcp`.
- Key derivation: PBKDF2-SHA256, **200,000 iterations**, fixed app salt, 32-byte output. Never HKDF — the input is a human passphrase.
- Passphrase lives in the **Keychain**, never `UserDefaults`.
- File clip transfer ceiling: **25MB**. Over that, the clip is not synced (logged, stays local).
- Received clips: inserted into history only. **Never** written to `NSPasteboard`, **never** re-broadcast.
- Received timestamps are clamped: `min(message.timestamp, now())`.
- Sync is **disabled by default**. With it off, v1 behavior must be bit-for-bit unchanged.
- No pin/delete propagation, no backfill/catch-up, no tombstones — explicitly out of scope.

---

## File Structure

```
Sources/Pastie/
  Models/Clip.swift                    MODIFY  +uuid, +originDevice
  Storage/ClipStore.swift              MODIFY  migration 3, clipExists(uuid:)
  Capture/ClipboardMonitor.swift       MODIFY  +onLocalClipCaptured callback
  Preferences/PreferencesStore.swift   MODIFY  +syncEnabled, +deviceID, +deviceName
  AppDelegate.swift                    MODIFY  wire sync when enabled
  UI/PreferencesView.swift             MODIFY  +Sync section
  UI/PreferencesViewModel.swift        MODIFY  +sync properties
  Sync/
    SyncMessage.swift        wire type (Codable) + binary plist codec
    MessageFraming.swift     length-prefix framing + incremental decoder
    SyncCrypto.swift         PBKDF2 derivation + SecretStore protocol/impls
    SyncedFileStore.swift    writes received file bytes to disk
    PeerTransport.swift      transport protocol + NWConnection implementation
    SyncCoordinator.swift    bridge: broadcast local clips, insert remote ones
    SyncService.swift        NWListener/NWBrowser lifecycle, peer list, TLS-PSK
Tests/PastieTests/
  SyncMessageTests.swift
  MessageFramingTests.swift
  SyncCryptoTests.swift
  SyncedFileStoreTests.swift
  SyncCoordinatorTests.swift
  SyncIntegrationTests.swift
```

---

### Task 1: Clip schema — `uuid` and `originDevice`

**Files:**
- Modify: `Sources/Pastie/Models/Clip.swift`
- Modify: `Sources/Pastie/Storage/ClipStore.swift`
- Test: `Tests/PastieTests/ClipStoreTests.swift` (append)

**Interfaces:**
- Produces: `Clip.uuid: String` (defaulted to `UUID().uuidString` in the memberwise init, so all existing call sites keep compiling), `Clip.originDevice: String?` (defaulted `nil`).
- Produces: `ClipStore.clipExists(uuid: String) throws -> Bool`
- Produces: GRDB migration `"addSyncColumns"` adding both columns, backfilling `uuid` on pre-existing rows, and creating a unique index `clip_on_uuid`.

- [ ] **Step 1: Write the failing tests**

```swift
// Append to Tests/PastieTests/ClipStoreTests.swift
extension ClipStoreTests {
    func testInsertPreservesUUIDAndOriginDevice() throws {
        let store = try makeStore()
        let clip = Clip(id: nil, uuid: "fixed-uuid-1", type: .text, textContent: "hi", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0, originDevice: "device-A")
        _ = try store.insert(clip)

        let all = try store.fetchAll()
        XCTAssertEqual(all.first?.uuid, "fixed-uuid-1")
        XCTAssertEqual(all.first?.originDevice, "device-A")
    }

    func testClipExistsByUUID() throws {
        let store = try makeStore()
        _ = try store.insert(Clip(id: nil, uuid: "known", type: .text, textContent: "x", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))

        XCTAssertTrue(try store.clipExists(uuid: "known"))
        XCTAssertFalse(try store.clipExists(uuid: "unknown"))
    }

    func testDefaultUUIDIsGeneratedAndUnique() throws {
        let store = try makeStore()
        let a = try store.insert(Clip(id: nil, type: .text, textContent: "a", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))
        let b = try store.insert(Clip(id: nil, type: .text, textContent: "b", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))

        XCTAssertFalse(a.uuid.isEmpty)
        XCTAssertNotEqual(a.uuid, b.uuid)
        XCTAssertNil(a.originDevice)
    }

    func testMigrationBackfillsUUIDOnPreExistingRows() throws {
        // Simulate a v1 database: create the v1 schema and insert a row with no uuid column,
        // then open it through ClipStore (which runs migrations 2 and 3) and confirm backfill.
        let dbQueue = try DatabaseQueue()
        try dbQueue.write { db in
            try db.create(table: "clip") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull()
                t.column("textContent", .text)
                t.column("imageData", .blob)
                t.column("filePath", .text)
                t.column("sourceApp", .text)
                t.column("timestamp", .datetime).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            // Mark migration 1 as already applied so ClipStore runs migrations 2 (v3) and 3 (sync).
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('createClip')")
            try db.execute(sql: """
                INSERT INTO clip (type, textContent, timestamp, pinned, sortOrder)
                VALUES ('text', 'legacy row', ?, 0, 0)
                """, arguments: [Date()])
        }

        let store = try ClipStore(dbQueue: dbQueue, retentionCount: 500)

        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all[0].uuid.isEmpty, "migration must backfill a uuid on pre-existing rows")
        XCTAssertNil(all[0].originDevice)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/stavnsananes/Applications/Pastie && swift test --filter ClipStoreTests`
Expected: FAIL to build — `Clip` has no `uuid`/`originDevice`, `ClipStore` has no `clipExists`.

- [ ] **Step 3: Add the fields to `Clip`**

```swift
// Sources/Pastie/Models/Clip.swift — replace the struct declaration
struct Clip: Identifiable, Equatable, Codable {
    var id: Int64?
    /// Global identity, stable across machines. Basis for cross-peer dedup.
    var uuid: String = UUID().uuidString
    var type: ClipType
    var textContent: String?
    var imageData: Data?
    var filePath: String?
    var sourceApp: String?
    var timestamp: Date
    var saved: Bool
    var sortOrder: Int64
    /// Device ID this clip arrived from; nil for locally-captured clips.
    /// Non-nil is the loop-prevention guard: such clips are never re-broadcast.
    var originDevice: String? = nil
}
```

Both new properties are defaulted, so the memberwise initializer keeps working for every existing call site that omits them (`ClipboardMonitor.makeClip`, the existing tests). Leave the `FetchableRecord`/`MutablePersistableRecord` extension and `hasSameContent(as:)` unchanged.

- [ ] **Step 4: Add migration 2 and `clipExists` to `ClipStore`**

```swift
// Sources/Pastie/Storage/ClipStore.swift — inside migrate(_:), after the existing
// migrator.registerMigration("createClip") { ... } block:
        migrator.registerMigration("addSyncColumns") { db in
            try db.alter(table: "clip") { t in
                t.add(column: "uuid", .text)
                t.add(column: "originDevice", .text)
            }
            let ids = try Int64.fetchAll(db, sql: "SELECT id FROM clip WHERE uuid IS NULL")
            for id in ids {
                try db.execute(
                    sql: "UPDATE clip SET uuid = ? WHERE id = ?",
                    arguments: [UUID().uuidString, id]
                )
            }
            try db.create(index: "clip_on_uuid", on: "clip", columns: ["uuid"], unique: true)
        }
```

```swift
// Sources/Pastie/Storage/ClipStore.swift — add alongside the other query methods
    func clipExists(uuid: String) throws -> Bool {
        try dbQueue.read { db in
            try Clip.filter(Column("uuid") == uuid).fetchCount(db) > 0
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: PASS — the 4 new tests plus all 29 pre-existing ones (33 total).

- [ ] **Step 6: Commit**

```bash
git add Sources/Pastie/Models/Clip.swift Sources/Pastie/Storage/ClipStore.swift Tests/PastieTests/ClipStoreTests.swift
git commit -m "feat: add uuid and originDevice to Clip for sync identity"
```

---

### Task 2: `SyncMessage` wire type and codec

**Files:**
- Create: `Sources/Pastie/Sync/SyncMessage.swift`
- Test: `Tests/PastieTests/SyncMessageTests.swift`

**Interfaces:**
- Produces: `struct SyncMessage: Codable, Equatable` with fields `clipUUID: String`, `type: ClipType`, `textContent: String?`, `imageData: Data?`, `fileName: String?`, `fileData: Data?`, `timestamp: Date`, `originDeviceID: String`, `originDeviceName: String`.
- Produces: `func encoded() throws -> Data` and `static func decode(_ data: Data) throws -> SyncMessage`.

**Why binary plist, not JSON:** `JSONEncoder` base64-encodes `Data`, inflating image and file payloads by ~33%. `PropertyListEncoder` with `.binary` stores bytes natively.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncMessageTests`
Expected: FAIL to build — `SyncMessage` not defined.

- [ ] **Step 3: Write `SyncMessage.swift`**

```swift
// Sources/Pastie/Sync/SyncMessage.swift
import Foundation

/// One clip on the wire. Deliberately flat and self-contained: peers never
/// negotiate schema, they just decode this.
struct SyncMessage: Codable, Equatable {
    let clipUUID: String
    let type: ClipType
    let textContent: String?
    let imageData: Data?
    let fileName: String?
    let fileData: Data?
    let timestamp: Date
    let originDeviceID: String
    let originDeviceName: String

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SyncMessage {
        try PropertyListDecoder().decode(SyncMessage.self, from: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncMessageTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/Sync/SyncMessage.swift Tests/PastieTests/SyncMessageTests.swift
git commit -m "feat: add SyncMessage wire type with binary plist codec"
```

---

### Task 3: Length-prefix framing

**Files:**
- Create: `Sources/Pastie/Sync/MessageFraming.swift`
- Test: `Tests/PastieTests/MessageFramingTests.swift`

**Interfaces:**
- Produces: `enum MessageFraming { static let maxMessageBytes = 32 * 1024 * 1024; static func frame(_ payload: Data) -> Data }` — 4-byte big-endian length prefix followed by the payload.
- Produces: `final class FrameDecoder { func append(_ data: Data) throws -> [Data] }` — accumulates arbitrary chunks, returns whatever complete payloads are now available.
- Produces: `enum FramingError: Error { case messageTooLarge(Int) }`

TCP delivers a byte stream with no message boundaries, so a single `append` may carry half a message, three messages, or a message split mid-length-prefix. That is exactly what these tests pin down.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PastieTests/MessageFramingTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MessageFramingTests`
Expected: FAIL to build — `MessageFraming`/`FrameDecoder` not defined.

- [ ] **Step 3: Write `MessageFraming.swift`**

```swift
// Sources/Pastie/Sync/MessageFraming.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MessageFramingTests`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/Sync/MessageFraming.swift Tests/PastieTests/MessageFramingTests.swift
git commit -m "feat: add length-prefix message framing"
```

---

### Task 4: Key derivation and passphrase storage

**Files:**
- Create: `Sources/Pastie/Sync/SyncCrypto.swift`
- Test: `Tests/PastieTests/SyncCryptoTests.swift`

**Interfaces:**
- Produces: `enum SyncKeyDerivation { static let iterations = 200_000; static func deriveKey(passphrase: String) -> Data }` — 32-byte PBKDF2-SHA256 output.
- Produces: `protocol SecretStore: AnyObject { func passphrase() -> String?; func setPassphrase(_ value: String?) }`
- Produces: `final class KeychainSecretStore: SecretStore` (real Keychain, `kSecClassGenericPassword`) and `final class InMemorySecretStore: SecretStore` (tests).

**Why a protocol:** Keychain access under `swift test` is environment-dependent (unsigned test binaries, CI machines with no unlocked keychain). The contract is unit-tested through `InMemorySecretStore`; `KeychainSecretStore` is verified manually in Task 10's smoke test. This keeps a real security dependency out of the automated suite without leaving the logic untested.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PastieTests/SyncCryptoTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncCryptoTests`
Expected: FAIL to build — `SyncKeyDerivation`/`InMemorySecretStore` not defined.

- [ ] **Step 3: Write `SyncCrypto.swift`**

```swift
// Sources/Pastie/Sync/SyncCrypto.swift
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
        var derived = [UInt8](repeating: 0, count: keyLength)
        let saltBytes = [UInt8](salt)

        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passphraseBytes.isEmpty ? "" : passphrase,
            passphraseBytes.count,
            saltBytes,
            saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(iterations),
            &derived,
            keyLength
        )

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncCryptoTests`
Expected: PASS (5 tests). Note: 200k PBKDF2 iterations take ~100ms each, so this suite runs about half a second.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/Sync/SyncCrypto.swift Tests/PastieTests/SyncCryptoTests.swift
git commit -m "feat: add PBKDF2 key derivation and keychain passphrase storage"
```

---

### Task 5: `SyncedFileStore`

**Files:**
- Create: `Sources/Pastie/Sync/SyncedFileStore.swift`
- Test: `Tests/PastieTests/SyncedFileStoreTests.swift`

**Interfaces:**
- Produces: `final class SyncedFileStore { init(directory: URL); static func defaultDirectory() -> URL; func write(data: Data, clipUUID: String, fileName: String) throws -> String }` — returns the absolute path written.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PastieTests/SyncedFileStoreTests.swift
import XCTest
@testable import Pastie

final class SyncedFileStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pastie-file-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWritesFileAndReturnsReadablePath() throws {
        let store = SyncedFileStore(directory: tempDir)
        let bytes = Data("report contents".utf8)

        let path = try store.write(data: bytes, clipUUID: "uuid-1", fileName: "report.pdf")

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), bytes)
        XCTAssertTrue(path.hasSuffix("report.pdf"), "original filename should be preserved")
    }

    func testCreatesDirectoryIfMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))
        let store = SyncedFileStore(directory: tempDir)

        _ = try store.write(data: Data("x".utf8), clipUUID: "uuid-2", fileName: "a.txt")

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
    }

    func testSanitizesPathSeparatorsInFileName() throws {
        let store = SyncedFileStore(directory: tempDir)

        let path = try store.write(data: Data("x".utf8), clipUUID: "uuid-3", fileName: "../../etc/passwd")

        XCTAssertTrue(path.hasPrefix(tempDir.path), "written file must stay inside the store directory")
        XCTAssertFalse(path.contains(".."), "path traversal segments must be stripped")
    }

    func testEmptyFileNameFallsBackToPlaceholder() throws {
        let store = SyncedFileStore(directory: tempDir)

        let path = try store.write(data: Data("x".utf8), clipUUID: "uuid-4", fileName: "")

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testDistinctClipsDoNotCollideOnSameFileName() throws {
        let store = SyncedFileStore(directory: tempDir)

        let first = try store.write(data: Data("one".utf8), clipUUID: "uuid-5", fileName: "same.txt")
        let second = try store.write(data: Data("two".utf8), clipUUID: "uuid-6", fileName: "same.txt")

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: first)), Data("one".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: second)), Data("two".utf8))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncedFileStoreTests`
Expected: FAIL to build — `SyncedFileStore` not defined.

- [ ] **Step 3: Write `SyncedFileStore.swift`**

```swift
// Sources/Pastie/Sync/SyncedFileStore.swift
import Foundation

/// Holds the bytes of file clips received from peers, so pasting one on this
/// machine yields a real file rather than a path that means nothing here.
final class SyncedFileStore {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    static func defaultDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Pastie", isDirectory: true)
            .appendingPathComponent("SyncedFiles", isDirectory: true)
    }

    /// Writes `data` under a per-clip subdirectory so two peers sending different
    /// files with the same name cannot overwrite each other.
    func write(data: Data, clipUUID: String, fileName: String) throws -> String {
        let clipDirectory = directory.appendingPathComponent(sanitize(clipUUID), isDirectory: true)
        try FileManager.default.createDirectory(at: clipDirectory, withIntermediateDirectories: true)

        let destination = clipDirectory.appendingPathComponent(sanitize(fileName))
        try data.write(to: destination)
        return destination.path
    }

    /// Reduces an arbitrary peer-supplied string to a single safe path component.
    private func sanitize(_ name: String) -> String {
        let component = (name as NSString).lastPathComponent
        let cleaned = component
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "file"
        }
        return cleaned
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncedFileStoreTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/Sync/SyncedFileStore.swift Tests/PastieTests/SyncedFileStoreTests.swift
git commit -m "feat: add SyncedFileStore for received file clip bytes"
```

---

### Task 6: `PeerTransport` protocol

**Files:**
- Create: `Sources/Pastie/Sync/PeerTransport.swift`

**Interfaces:**
- Produces: `protocol PeerTransport: AnyObject { var peerID: String { get }; var peerName: String { get }; var onReceive: ((Data) -> Void)? { get set }; var onClose: (() -> Void)? { get set }; func send(_ payload: Data); func close() }`
- Produces: `final class NWConnectionTransport: PeerTransport` — wraps one `NWConnection`, frames outgoing payloads with `MessageFraming.frame`, feeds incoming bytes through a `FrameDecoder`, and calls `onReceive` per complete message.

The protocol exists so `SyncCoordinator` (Task 7) is testable against a fake with no networking at all.

- [ ] **Step 1: Write `PeerTransport.swift`**

```swift
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
                self?.onClose?()
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
                    self.close()
                    return
                }
            }

            if isComplete || error != nil {
                self.close()
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
        connection.cancel()
        onClose?()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean, no warnings.

- [ ] **Step 3: Run the full suite to confirm nothing regressed**

Run: `swift test`
Expected: PASS — still 54 tests (29 from v1, +4 Task 1, +5 Task 2, +6 Task 3, +5 Task 4, +5 Task 5). No new tests in this task: the protocol has no behavior of its own, and `NWConnectionTransport` is exercised by the loopback integration test in Task 10.

- [ ] **Step 4: Commit**

```bash
git add Sources/Pastie/Sync/PeerTransport.swift
git commit -m "feat: add PeerTransport protocol and NWConnection implementation"
```

---

### Task 7: `SyncCoordinator` — broadcast, dedup, loop prevention

**Files:**
- Create: `Sources/Pastie/Sync/SyncCoordinator.swift`
- Test: `Tests/PastieTests/SyncCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ClipStore` (`insert`, `clipExists(uuid:)`), `SyncedFileStore.write(data:clipUUID:fileName:)`, `SyncMessage`, `PeerTransport`.
- Produces: `final class SyncCoordinator { init(store: ClipStore, fileStore: SyncedFileStore, deviceID: String, deviceName: String, maxFileBytes: Int = 25 * 1024 * 1024, now: @escaping () -> Date = Date.init); var transportsProvider: () -> [PeerTransport]; func handleLocalClip(_ clip: Clip); func handleIncoming(_ data: Data, fromPeer peerID: String) }`

This is where the two rules that keep the system from eating itself live: **a clip with `originDevice != nil` is never broadcast** (otherwise two peers ping-pong a clip forever), and **a message whose `clipUUID` already exists is dropped** (otherwise three-or-more peers insert the same clip twice by different paths).

- [ ] **Step 1: Write the failing test**

```swift
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

        coordinator.handleLocalClip(Clip(id: 1, uuid: "clip-1", type: .text, textContent: "shared", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))

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
        coordinator.handleLocalClip(Clip(id: 1, uuid: "clip-2", type: .text, textContent: "echo", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0, originDevice: "other-device"))

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

        coordinator.handleLocalClip(Clip(id: 1, uuid: "big", type: .file, textContent: nil, imageData: nil, filePath: bigFile.path, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))

        XCTAssertTrue(peer.sent.isEmpty, "files over the ceiling are not synced")
    }

    func testMalformedIncomingDataIsIgnored() throws {
        let (coordinator, store) = try makeCoordinator(transports: [])

        coordinator.handleIncoming(Data("garbage".utf8), fromPeer: "device-B")

        XCTAssertTrue(try store.fetchAll().isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncCoordinatorTests`
Expected: FAIL to build — `SyncCoordinator` not defined.

- [ ] **Step 3: Write `SyncCoordinator.swift`**

```swift
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
            saved: false,
            sortOrder: 0,
            originDevice: message.originDeviceID
        )

        do {
            try store.insert(clip)
        } catch {
            NSLog("SyncCoordinator: failed to insert received clip: \(error)")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncCoordinatorTests`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/Sync/SyncCoordinator.swift Tests/PastieTests/SyncCoordinatorTests.swift
git commit -m "feat: add SyncCoordinator with dedup and loop prevention"
```

---

### Task 8: `SyncService` — listener, browser, TLS-PSK

**Files:**
- Create: `Sources/Pastie/Sync/SyncService.swift`

**Interfaces:**
- Consumes: `SyncCoordinator`, `NWConnectionTransport`, `SyncKeyDerivation.deriveKey(passphrase:)`.
- Produces: `struct SyncPeerStatus: Identifiable, Equatable { let id: String; let name: String; let state: State; enum State: Equatable { case connected, authenticationFailed, disconnected } }`
- Produces: `final class SyncService { init(coordinator: SyncCoordinator, deviceID: String, deviceName: String, passphrase: String, port: NWEndpoint.Port = .any); func start() throws; func stop(); func connect(to endpoint: NWEndpoint); var onPeersChanged: (([SyncPeerStatus]) -> Void)?; var peers: [SyncPeerStatus]; var listeningPort: NWEndpoint.Port? }`

`connect(to:)` is public rather than private so Task 10's integration test can dial a known loopback port directly instead of waiting on Bonjour, which is slow and flaky inside a test process. The browser uses the same method.

- [ ] **Step 1: Write `SyncService.swift`**

```swift
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
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean. If `sec_protocol_options_add_pre_shared_key` complains about `DispatchData` bridging, adjust the cast (the `__DispatchData` bridge is the standard workaround); the API shape is what matters, not the exact cast spelling.

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: PASS, still 63 tests (54 + 9 from Task 7). `SyncService` gains no unit tests of its own — its behavior is networking, covered by Task 10's loopback integration test.

- [ ] **Step 4: Commit**

```bash
git add Sources/Pastie/Sync/SyncService.swift
git commit -m "feat: add SyncService with Bonjour discovery and TLS-PSK"
```

---

### Task 9: Preferences — sync settings and UI

**Files:**
- Modify: `Sources/Pastie/Preferences/PreferencesStore.swift`
- Modify: `Sources/Pastie/UI/PreferencesViewModel.swift`
- Modify: `Sources/Pastie/UI/PreferencesView.swift`
- Test: `Tests/PastieTests/PreferencesStoreTests.swift` (append), `Tests/PastieTests/PreferencesViewModelTests.swift` (append)

**Interfaces:**
- Produces on `PreferencesStore`: `var syncEnabled: Bool` (default `false`), `var deviceID: String` (generated once on first read, then stable), `var deviceName: String` (defaults to `Host.current().localizedName ?? "Mac"`).
- Produces on `PreferencesViewModel`: `@Published var syncEnabled: Bool`, `@Published var deviceName: String`, `@Published var passphrase: String`, `@Published var peers: [SyncPeerStatus]`, and `init(store: PreferencesStore, secretStore: SecretStore = KeychainSecretStore())`.

- [ ] **Step 1: Write the failing tests**

```swift
// Append to Tests/PastieTests/PreferencesStoreTests.swift
extension PreferencesStoreTests {
    func testSyncDisabledByDefault() {
        XCTAssertFalse(makeStore().syncEnabled)
    }

    func testSyncEnabledRoundTrips() {
        let store = makeStore()
        store.syncEnabled = true
        XCTAssertTrue(store.syncEnabled)
    }

    func testDeviceIDIsGeneratedOnceAndStable() {
        let store = makeStore()
        let first = store.deviceID
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(store.deviceID, first, "device ID must not change between reads")
    }

    func testDeviceNameDefaultsToSomethingNonEmpty() {
        XCTAssertFalse(makeStore().deviceName.isEmpty)
    }

    func testDeviceNameRoundTrips() {
        let store = makeStore()
        store.deviceName = "Studio Mac"
        XCTAssertEqual(store.deviceName, "Studio Mac")
    }
}
```

```swift
// Append to Tests/PastieTests/PreferencesViewModelTests.swift
extension PreferencesViewModelTests {
    private func makeSyncViewModel() -> (PreferencesViewModel, InMemorySecretStore) {
        let secretStore = InMemorySecretStore()
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-sync-vm-tests-\(UUID())")!)
        return (PreferencesViewModel(store: store, secretStore: secretStore), secretStore)
    }

    func testTogglingSyncPersistsToStore() {
        let (viewModel, _) = makeSyncViewModel()

        viewModel.syncEnabled = true

        XCTAssertTrue(viewModel.syncEnabled)
    }

    func testPassphraseIsWrittenToSecretStoreNotDefaults() {
        let (viewModel, secretStore) = makeSyncViewModel()

        viewModel.passphrase = "correct horse battery staple"

        XCTAssertEqual(secretStore.passphrase(), "correct horse battery staple")
    }

    func testPassphraseLoadsFromSecretStoreOnInit() {
        let secretStore = InMemorySecretStore(passphrase: "already set")
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-sync-vm-tests-\(UUID())")!)

        let viewModel = PreferencesViewModel(store: store, secretStore: secretStore)

        XCTAssertEqual(viewModel.passphrase, "already set")
    }

    func testDeviceNameChangePersists() {
        let (viewModel, _) = makeSyncViewModel()

        viewModel.deviceName = "Studio Mac"

        XCTAssertEqual(viewModel.deviceName, "Studio Mac")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesStoreTests && swift test --filter PreferencesViewModelTests`
Expected: FAIL to build — the new properties and the `secretStore:` initializer parameter don't exist.

- [ ] **Step 3: Extend `PreferencesStore`**

```swift
// Sources/Pastie/Preferences/PreferencesStore.swift
// Add to the Keys enum:
        static let syncEnabled = "syncEnabled"
        static let deviceID = "deviceID"
        static let deviceName = "deviceName"

// Add alongside the other properties:
    var syncEnabled: Bool {
        get { defaults.bool(forKey: Keys.syncEnabled) }
        set { defaults.set(newValue, forKey: Keys.syncEnabled) }
    }

    /// Stable identity for this machine, generated once on first access.
    var deviceID: String {
        if let existing = defaults.string(forKey: Keys.deviceID) { return existing }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Keys.deviceID)
        return generated
    }

    var deviceName: String {
        get {
            defaults.string(forKey: Keys.deviceName)
                ?? Host.current().localizedName
                ?? "Mac"
        }
        set { defaults.set(newValue, forKey: Keys.deviceName) }
    }
```

- [ ] **Step 4: Extend `PreferencesViewModel`**

```swift
// Sources/Pastie/UI/PreferencesViewModel.swift — add the secret store, new published
// properties, and the new initializer parameter. Existing properties/methods unchanged.
    private let secretStore: SecretStore

    @Published var syncEnabled: Bool {
        didSet { store.syncEnabled = syncEnabled }
    }
    @Published var deviceName: String {
        didSet { store.deviceName = deviceName }
    }
    @Published var passphrase: String {
        didSet { secretStore.setPassphrase(passphrase.isEmpty ? nil : passphrase) }
    }
    @Published var peers: [SyncPeerStatus] = []

    init(store: PreferencesStore, secretStore: SecretStore = KeychainSecretStore()) {
        self.store = store
        self.secretStore = secretStore
        self.retentionCount = store.retentionCount
        self.launchAtLogin = store.launchAtLogin
        self.excludedBundleIDs = Array(store.excludedBundleIDs).sorted()
        self.syncEnabled = store.syncEnabled
        self.deviceName = store.deviceName
        self.passphrase = secretStore.passphrase() ?? ""
    }
```

Note: the existing `init(store:)` call site in `AppDelegate.openPreferences()` keeps compiling because `secretStore` is defaulted.

- [ ] **Step 5: Add the Sync section to `PreferencesView`**

```swift
// Sources/Pastie/UI/PreferencesView.swift — add inside the Form, after the
// "Excluded Apps" Section:
            Section("Sync") {
                Toggle("Sync clipboard with other Macs", isOn: $viewModel.syncEnabled)
                TextField("This Mac's name", text: $viewModel.deviceName)
                SecureField("Shared passphrase", text: $viewModel.passphrase)
                Text("Every Mac you sync must use the same passphrase. Its strength is what protects your clipboard on the network — pick a long one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.peers.isEmpty {
                    Text("No peers connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.peers) { peer in
                        HStack {
                            Text(peer.name)
                            Spacer()
                            Text(statusLabel(for: peer.state))
                                .font(.caption)
                                .foregroundStyle(peer.state == .authenticationFailed ? .red : .secondary)
                        }
                    }
                }
            }
```

```swift
// Sources/Pastie/UI/PreferencesView.swift — add as a method on PreferencesView:
    private func statusLabel(for state: SyncPeerStatus.State) -> String {
        switch state {
        case .connected: return "Connected"
        case .authenticationFailed: return "Authentication failed — check passphrase"
        case .disconnected: return "Disconnected"
        }
    }
```

Also widen the window so the new section fits: change `.frame(width: 380, height: 420)` to `.frame(width: 420, height: 640)`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test`
Expected: PASS — 72 tests (63 + 5 store + 4 view model).

- [ ] **Step 7: Commit**

```bash
git add Sources/Pastie/Preferences/PreferencesStore.swift Sources/Pastie/UI/PreferencesViewModel.swift Sources/Pastie/UI/PreferencesView.swift Tests/PastieTests/PreferencesStoreTests.swift Tests/PastieTests/PreferencesViewModelTests.swift
git commit -m "feat: add sync settings and Preferences sync section"
```

---

### Task 10: Wire it up — monitor callback, AppDelegate, integration test

**Files:**
- Modify: `Sources/Pastie/Capture/ClipboardMonitor.swift`
- Modify: `Sources/Pastie/AppDelegate.swift`
- Test: `Tests/PastieTests/SyncIntegrationTests.swift`

**Interfaces:**
- Produces on `ClipboardMonitor`: `var onLocalClipCaptured: ((Clip) -> Void)?`, invoked with the **inserted** clip (which carries its `id` and `uuid`) after a successful local insert.
- Consumes: everything from Tasks 1-9.

- [ ] **Step 1: Add the capture callback to `ClipboardMonitor`**

```swift
// Sources/Pastie/Capture/ClipboardMonitor.swift — add the property alongside the others:
    /// Called with each newly-captured local clip after it is stored. SyncCoordinator
    /// hooks this to broadcast; nil when sync is off, which is the default.
    var onLocalClipCaptured: ((Clip) -> Void)?

// And replace the insert block at the end of tick():
        do {
            let inserted = try store.insert(clip)
            onLocalClipCaptured?(inserted)
        } catch {
            NSLog("ClipboardMonitor: failed to insert clip: \(error)")
        }
```

- [ ] **Step 2: Write the failing integration test**

```swift
// Tests/PastieTests/SyncIntegrationTests.swift
import XCTest
import Network
import GRDB
@testable import Pastie

/// Two SyncService instances in one process, talking over loopback.
/// Dials an explicit port rather than waiting on Bonjour: discovery inside a test
/// process is slow and flaky, and what we're proving here is that a clip crosses
/// the wire — TLS handshake, framing, coordinator, and store insert end to end.
final class SyncIntegrationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pastie-integration-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeSide(deviceID: String, deviceName: String, port: NWEndpoint.Port) throws -> (SyncService, ClipStore) {
        let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
        let coordinator = SyncCoordinator(
            store: store,
            fileStore: SyncedFileStore(directory: tempDir.appendingPathComponent(deviceID)),
            deviceID: deviceID,
            deviceName: deviceName
        )
        let service = SyncService(
            coordinator: coordinator,
            deviceID: deviceID,
            deviceName: deviceName,
            passphrase: "shared test passphrase",
            port: port
        )
        return (service, store)
    }

    func testClipCrossesFromOneServiceToTheOther() throws {
        let port = NWEndpoint.Port(rawValue: 56_812)!
        let (receiver, receiverStore) = try makeSide(deviceID: "dev-receiver", deviceName: "Receiver", port: port)
        let (sender, _) = try makeSide(deviceID: "dev-sender", deviceName: "Sender", port: .any)

        try receiver.start()
        try sender.start()
        defer {
            receiver.stop()
            sender.stop()
        }

        sender.connect(to: .hostPort(host: "127.0.0.1", port: port))

        // Give the TLS handshake time to complete before sending.
        let connected = expectation(description: "peer connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { connected.fulfill() }
        wait(for: [connected], timeout: 5.0)

        let clip = Clip(id: 1, uuid: "crossing-clip", type: .text, textContent: "hello from the other Mac", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0)
        senderCoordinatorBroadcast(sender, clip: clip)

        // Poll for arrival rather than sleeping a fixed amount.
        let arrived = expectation(description: "clip arrived on receiver")
        DispatchQueue.global().async {
            for _ in 0..<50 {
                if let all = try? receiverStore.fetchAll(), all.contains(where: { $0.uuid == "crossing-clip" }) {
                    arrived.fulfill()
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        wait(for: [arrived], timeout: 10.0)

        let received = try XCTUnwrap(try receiverStore.fetchAll().first { $0.uuid == "crossing-clip" })
        XCTAssertEqual(received.textContent, "hello from the other Mac")
        XCTAssertEqual(received.originDevice, "dev-sender", "received clips must be tagged with their origin")
    }

    /// SyncService owns its coordinator privately; this reaches the same broadcast path
    /// the ClipboardMonitor callback would drive in the real app.
    private func senderCoordinatorBroadcast(_ service: SyncService, clip: Clip) {
        service.broadcastForTesting(clip)
    }
}
```

- [ ] **Step 3: Add the test seam to `SyncService`**

```swift
// Sources/Pastie/Sync/SyncService.swift — store the coordinator reference and expose
// a narrow seam for the integration test. Add to the class:
    /// Drives the same broadcast path the ClipboardMonitor callback uses in the app.
    /// Exists so the loopback integration test can send a clip without standing up a
    /// real pasteboard monitor.
    func broadcastForTesting(_ clip: Clip) {
        coordinator.handleLocalClip(clip)
    }
```

- [ ] **Step 4: Run the integration test**

Run: `swift test --filter SyncIntegrationTests`
Expected: PASS. macOS may prompt for permission to accept incoming network connections the first time — allow it. If the test is flaky under load, the fixed 2s handshake wait is the knob to raise; do not "fix" flakiness by weakening the assertions.

- [ ] **Step 5: Wire sync into `AppDelegate`**

```swift
// Sources/Pastie/AppDelegate.swift — add the stored properties:
    private var syncService: SyncService?
    private var syncCoordinator: SyncCoordinator?
    private let secretStore: SecretStore = KeychainSecretStore()

// And add this call at the end of applicationDidFinishLaunching, after
// hotkeyManager.registerFromPreferences():
        startSyncIfEnabled()

// Then add the method:
    private func startSyncIfEnabled() {
        guard preferences.syncEnabled else { return }
        guard let passphrase = secretStore.passphrase(), !passphrase.isEmpty else {
            NSLog("Pastie: sync is enabled but no passphrase is set — not starting sync")
            return
        }

        let coordinator = SyncCoordinator(
            store: clipStore,
            fileStore: SyncedFileStore(directory: SyncedFileStore.defaultDirectory()),
            deviceID: preferences.deviceID,
            deviceName: preferences.deviceName
        )
        let service = SyncService(
            coordinator: coordinator,
            deviceID: preferences.deviceID,
            deviceName: preferences.deviceName,
            passphrase: passphrase
        )

        do {
            try service.start()
        } catch {
            NSLog("Pastie: failed to start sync: \(error)")
            return
        }

        monitor.onLocalClipCaptured = { [weak coordinator] clip in
            coordinator?.handleLocalClip(clip)
        }

        syncCoordinator = coordinator
        syncService = service
    }
```

Then connect the service's peer updates to the Preferences UI — without this, the
peer list added in Task 9 is dead UI that always reads "No peers connected".
Retain the view model as a property and feed it:

```swift
// Sources/Pastie/AppDelegate.swift — add the stored property:
    private var preferencesViewModel: PreferencesViewModel?

// And replace the body of openPreferences() with:
    private func openPreferences() {
        if preferencesWindow == nil {
            let viewModel = PreferencesViewModel(store: preferences, secretStore: secretStore)
            preferencesViewModel = viewModel

            // Seed with whatever peers are already connected, then keep it live.
            viewModel.peers = syncService?.peers ?? []
            syncService?.onPeersChanged = { [weak viewModel] peers in
                viewModel?.peers = peers
            }

            let hosting = NSHostingController(rootView: PreferencesView(viewModel: viewModel))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Pastie Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

`SyncService.onPeersChanged` already dispatches to the main queue before firing, so
assigning to a `@Published` property from it is safe.

- [ ] **Step 6: Build and run the full suite**

Run: `swift build && swift test`
Expected: builds clean; all tests pass (73 with the integration test).

- [ ] **Step 7: Manual verification**

1. `Scripts/build-app.sh && open build/Pastie.app` — confirm sync being off by default changes nothing about v1 behavior (copy something, hotkey popup still works).
2. Open Preferences → Sync: enable it, set a passphrase, confirm the passphrase survives quitting and relaunching the app (this is the real `KeychainSecretStore` path, which has no automated coverage by design).
3. Build the same `.app` on a second Mac on the same wifi, set the **same** passphrase, enable sync on both. Copy text on Mac A → confirm it appears in Mac B's popup within a few seconds, and that Mac B's own clipboard is untouched.
4. Copy an image, then a small file, on Mac A → confirm both arrive on Mac B, and that pasting the file on Mac B produces a real file.
5. On Mac B, change the passphrase to something wrong → confirm the Sync section shows "Authentication failed — check passphrase" rather than failing silently.
6. Confirm a clip received on Mac B is not echoed back to Mac A (Mac A's history should show it exactly once).

- [ ] **Step 8: Commit**

```bash
git add Sources/Pastie/Capture/ClipboardMonitor.swift Sources/Pastie/AppDelegate.swift Sources/Pastie/Sync/SyncService.swift Tests/PastieTests/SyncIntegrationTests.swift
git commit -m "feat: wire sync into the app and add loopback integration test"
```

---

## Spec Coverage Check

- Mac ↔ Mac, LAN-direct, Bonjour `_pastie._tcp` → Task 8
- TLS-PSK from passphrase; PBKDF2-SHA256 200k iterations, fixed salt → Tasks 4, 8
- Passphrase in Keychain, never UserDefaults → Task 4 (`KeychainSecretStore`), Task 9 (UI writes through it)
- Live push of new clips (text/image/file) → Tasks 7, 10
- File clips transfer bytes, 25MB ceiling, over-ceiling skipped + logged → Task 7
- Received files written to `SyncedFiles/`, `filePath` points there → Tasks 5, 7
- `uuid` + `originDevice` schema, migration with backfill → Task 1
- Dedup by `uuid` → Tasks 1, 7
- Loop prevention (`originDevice != nil` never re-broadcast) → Task 7
- History-only receive (never writes `NSPasteboard`) → Task 7 (`SyncCoordinator` has no pasteboard access at all — structurally guaranteed, not just by convention)
- Timestamp clamping → Task 7
- Filters applied at origin, retention applies to received clips → Task 7 (inserts through normal `ClipStore.insert`)
- Sync disabled by default; v1 unchanged when off → Tasks 9, 10
- Peer disappears → drop connection, keep browsing → Task 8
- Wrong passphrase visible in UI → Tasks 8 (`.authenticationFailed`), 9 (red status row)
- DB insert failure logged and skipped → Task 7
- Malformed message drops the connection → Task 6
- Testing: codec, framing, coordinator dedup/loop, key derivation, loopback integration → Tasks 2, 3, 4, 7, 10
