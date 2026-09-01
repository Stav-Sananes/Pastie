# Pastie v2 — Multi-Machine Sync Design Spec

Date: 2026-09-02

Builds on: `2026-09-01-ditto-mac-design.md` (Pastie v1, complete — single-machine
clipboard manager at `/Users/stavnsananes/Applications/Pastie`).

## Purpose

Add the multi-machine sync deferred from v1: a clip copied on one Mac appears in
another Mac's clipboard history within seconds, over the local network, with no
server and no account.

## Scope

In:
- Mac ↔ Mac only (both ends run Pastie; no Windows Ditto interop, no iOS)
- LAN-direct transport with Bonjour discovery — no cloud, no relay, no account
- Live push of newly captured clips: text, image, and file clips
- File clips transfer the file's actual bytes (up to a 25MB ceiling), so pasting
  on the receiving Mac yields a real, usable file
- Shared-passphrase authentication with an encrypted channel
- Received clips land in history only — they never take over the receiving Mac's
  live pasteboard

Out (explicitly not in this phase):
- Propagating pin/unpin and deletes between peers (so: no tombstones, no
  per-clip `updatedAt`, no merge/conflict resolution)
- Backfill/catch-up of clips missed while a peer was away — a peer that was
  offline simply doesn't have those clips
- Windows/iOS peers, cloud or relay transports, sync over the internet
- Any change to v1's single-machine behavior when sync is disabled

## Architecture

A new, isolated `Sync/` module. When sync is disabled in Preferences (the
default), none of it starts and v1 behavior is bit-for-bit unchanged.

Transport is **Network.framework + Bonjour + TLS-PSK**: `NWListener` advertises
the service and `NWBrowser` discovers peers (Bonjour comes free with both), and
`NWProtocolTLS` takes the passphrase-derived key as a pre-shared key, so
authentication and encryption both come from Apple's TLS stack rather than
hand-rolled crypto. A peer that doesn't know the passphrase fails the TLS
handshake and never reaches application code.

Two alternatives were considered and rejected: raw TCP plus hand-rolled CryptoKit
AES-GCM (full wire-format control, but we would own the handshake, nonce
discipline, and replay protection — the three things implementations get wrong),
and MultipeerConnectivity (one small API for discovery + transport + encryption,
but built for ad-hoc foreground sessions, long-standing flakiness reports in
long-lived background use, and a certificate-based security model that doesn't
fit passphrase auth).

## Components

1. **`SyncService`** — lifecycle owner. Starts `NWListener` (advertising
   `_pastie._tcp`) and `NWBrowser`, holds live connections, publishes the
   connected-peer list for the Preferences UI. Started by `AppDelegate` only
   when sync is enabled.
2. **`PeerTransport`** — one connection's framing: length-prefixed messages,
   encode/decode, partial-buffer accumulation. Knows nothing about clips.
   Defined against a protocol so tests can substitute a fake.
3. **`SyncMessage`** — the `Codable` wire type: clip `uuid`, clip type,
   text content / image bytes / file bytes + filename, origin timestamp,
   origin device ID and name.
4. **`SyncCoordinator`** — the bridge between sync and v1's storage. Broadcasts
   locally-captured clips; inserts received ones. Owns dedup and loop
   prevention.
5. **`SyncKeychain`** — reads/writes the passphrase as a
   `kSecClassGenericPassword` Keychain item.
6. **`SyncKeyDerivation`** — passphrase → 32-byte PSK.

## Storage Changes

`Clip` gains two fields, via a second GRDB migration:

- `uuid: String` — global identity, the basis for cross-peer dedup. The
  migration backfills existing rows with fresh UUIDs.
- `originDevice: String?` — the device ID a clip arrived from; `nil` for
  locally-captured clips. This is what loop prevention keys on.

Received file bytes are written to
`~/Library/Application Support/Pastie/SyncedFiles/<uuid>-<filename>`, and the
clip's `filePath` points there.

## Data Flow

**Send:** `ClipboardMonitor` gains an `onLocalClipCaptured` closure (the same
injection pattern as `PasteEngine.beforeEachWrite` from v1's fix wave), fired
after a successful local insert. `SyncCoordinator` builds a `SyncMessage`,
loading file bytes for file clips under the size ceiling, and broadcasts it to
every connected peer.

**Receive:** decode → drop if a clip with that `uuid` already exists (required
once three or more peers are connected, where the same clip can arrive by two
paths) → for file clips, write bytes into `SyncedFiles/` and set `filePath` →
insert with `originDevice` set to the sender.

A received clip is never re-broadcast (`originDevice != nil` is the guard) and
never written to `NSPasteboard`. Because receive never touches the pasteboard,
the self-capture class of bug that v1's `ignoringSelfWrite` flag exists to
prevent cannot arise on this path at all.

**Filtering and retention on receive:** v1's capture filters (concealed/transient
pasteboard types, excluded-app list) are applied by the *origin* machine at
capture time, so a clip that reaches the wire has already passed them; the
receiving side applies no additional filtering. Received clips insert through the
normal `ClipStore.insert`, so the retention cap and its pinned-item exemption
apply to them exactly as they do to local clips.

**Clock skew:** received clips carry the origin's timestamp, so a peer with a
fast clock would permanently pin its clips to the top of the list. Clamp on
receipt: `timestamp = min(message.timestamp, Date())`.

## Security

The passphrase is stored in the **Keychain**, never in `UserDefaults` —
`UserDefaults` is a plist readable by anything running as the user.

Key derivation is **PBKDF2-SHA256, 200,000 iterations, fixed app salt**,
producing the 32-byte TLS-PSK. Deliberately not HKDF: HKDF assumes
high-entropy input, and a human-chosen passphrase is not. Without a
password-hardening KDF, an attacker who captures a single handshake can
brute-force a weak passphrase offline. The Preferences pane states plainly that
passphrase strength is what protects the channel.

Each machine has a device identity: a UUID generated once and stored in
`UserDefaults`, plus a human-readable name for the peer list — defaulting to
`Host.current().localizedName` (the machine's Sharing name) and editable in
Preferences.

## Preferences Surface

A new Sync section in `PreferencesView`: enable toggle (default off), passphrase
`SecureField`, this machine's device name, and a live list of connected peers
with status.

## Error Handling

- **Peer disappears:** log, drop the connection, keep browsing.
  `NWBrowser` re-reports the peer when it returns; no retry loop of our own.
- **Wrong passphrase:** the TLS handshake fails. This must surface visibly in
  the Sync pane (e.g. "Peer *MacBook-Air*: authentication failed") — a mistyped
  passphrase is the most likely failure mode in this feature, and silence is the
  worst possible response to it.
- **Oversized file** (over the 25MB ceiling): the clip is not synced, a log line
  records it, and the clip remains available locally on the origin machine.
- **DB insert failure on receive:** log and skip, matching v1's posture.
- **Malformed message:** drop the connection rather than guess at resyncing the
  framing; it will re-establish through normal discovery.

## Testing

The pure units carry the load:

- `SyncMessage` codec round-trip across all three clip types.
- Length-prefix framing against split and partial buffers — the classic bug
  source in any hand-written framing layer.
- `SyncCoordinator` dedup (same `uuid` twice → one insert) and loop prevention
  (a clip with `originDevice != nil` is never broadcast), against a
  protocol-based fake transport and an in-memory `ClipStore`.
- Key-derivation determinism: same passphrase → same key; different
  passphrase → different key.

Then one integration test: two `SyncService` instances in a single test process
over loopback, asserting a clip crosses from one store to the other.

Verification on two physical Macs on the same wifi stays manual, as does the
wrong-passphrase UI path.

## Tech Stack

Swift, Network.framework (`NWListener`/`NWBrowser`/`NWConnection`/
`NWProtocolTLS`), CryptoKit + CommonCrypto (PBKDF2), Security framework
(Keychain), GRDB (existing store), SwiftUI (Preferences section), XCTest.
