# Pastie — Searchable Text Inside Images (OCR) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make copied screenshots findable — Vision reads the text inside an image clip on-device, and typing that text in the popup finds the image.

**Architecture:** One new module, `Sources/Pastie/OCR/`, holding a `TextRecognizing` protocol and its Vision implementation. Recognition runs asynchronously after the clip is already stored, so capture never waits on it, and the result is written back to a new `ocrText` column (migration 4). `ClipSearch` gains one line so image clips match on that text. Nothing about pasting changes.

**Tech Stack:** Swift 5.9, AppKit, Vision (`VNRecognizeTextRequest`, `VNImageRequestHandler`), GRDB 6.24+ (migration 4), SwiftUI for the one settings toggle, XCTest.

**Spec:** `/Users/stavnsananes/Applications/Pastie/docs/superpowers/specs/2026-09-06-pastie-ocr-design.md`

**Glossary:** `/Users/stavnsananes/Applications/Pastie/CONTEXT.md` — use these words in code and commits: Clip, History, Saved, Quick-paste slot, Transform, Capture, Rich payload. (`CONTEXT.md` is gitignored — read it with `cat`, never `git add` it.)

## Global Constraints

- Platform floor: **macOS 13.0** (`Package.swift` says `.macOS(.v13)`). `VNRecognizeTextRequest` predates it; no availability guard is needed.
- **No App Sandbox.** Vision needs no entitlement. Never add sandbox entitlements (ADR 0001).
- **Nothing leaves the machine.** Recognition is on-device. No network call may appear in this work.
- **Search index only.** `ocrText` is never pasted, never displayed, never transformed. No UI shows it.
- **No backfill.** Only images captured after this ships are recognised. Do not write a migration-time or launch-time pass over existing rows.
- Migration numbering: 1 `createClip`, 2 `savedAndRichPayload`, 3 `addSyncColumns`, and **ours is 4, `addOCRText`**, registered last. GRDB replays migrations in registration order.
- Recognition must run on the **original** image bytes, never the downsampled ones (see Task 5).
- `nil` and `""` from a recogniser mean the same thing: not searchable. Do not add a third state.
- The OCR toggle defaults to **on** and lives in the Capture tab.

## File Structure

```
Sources/Pastie/
  OCR/TextRecognizing.swift          CREATE  protocol — the test seam
  OCR/VisionTextRecognizer.swift     CREATE  the only file importing Vision
  Models/Clip.swift                  MODIFY  +ocrText (defaulted, declared last)
  Storage/ClipStore.swift            MODIFY  migration 4; setOCRText
  Search/ClipSearch.swift            MODIFY  image clips match on ocrText
  Preferences/PreferencesStore.swift MODIFY  +ocrEnabled (default true)
  UI/PreferencesViewModel.swift      MODIFY  +@Published ocrEnabled
  UI/SettingsTabs/CaptureTab.swift   MODIFY  +toggle
  Capture/ClipboardMonitor.swift     MODIFY  keep original bytes; kick off recognition
  AppDelegate.swift                  MODIFY  inject VisionTextRecognizer

Tests/PastieTests/
  ClipStoreTests.swift               MODIFY  migration 4, setOCRText
  ClipSearchTests.swift              MODIFY  image matching
  PreferencesStoreTests.swift        MODIFY  default
  PreferencesViewModelTests.swift    MODIFY  write-through
  ClipboardMonitorTests.swift        MODIFY  fake recogniser cases
```

Task order is dependency order: schema (1) → search (2) → the recogniser seam (3) → the setting (4) → the wiring that consumes all four (5).

---

### Task 1: Migration 4 — the `ocrText` column

**Files:**
- Modify: `Sources/Pastie/Models/Clip.swift`
- Modify: `Sources/Pastie/Storage/ClipStore.swift`
- Test: `Tests/PastieTests/ClipStoreTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `Clip.ocrText: String?` (default `nil`), and `ClipStore.setOCRText(_ text: String?, id: Int64) throws`.

**Context you need:** `Clip` already carries three defaulted trailing properties — `rtfData`, `slotIndex`, `originDevice` — added by earlier work in exactly this way. Adding a fourth defaulted property at the end means none of the dozen `Clip(...)` call sites change. GRDB's `DatabaseMigrator` records each migration by its string identifier in `grdb_migrations` and replays them in registration order, so `addOCRText` must be registered after `addSyncColumns`, not before.

`ClipStore.setOCRText` must tolerate a missing row: recognition finishes after capture, and by then the clip may have been evicted by the retention cap or deleted by the user. A `fetchOne` that returns nil is the normal case, not an error.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PastieTests/ClipStoreTests.swift`:

```swift
    func testMigrationAddsOCRTextColumnWithoutLosingRows() throws {
        // A database at migration 3 (createClip + savedAndRichPayload + addSyncColumns is what
        // ClipStore itself produces), reopened, must gain ocrText as nil and keep its rows.
        let dbQueue = try DatabaseQueue()
        let first = try ClipStore(dbQueue: dbQueue, retentionCount: 500)
        _ = try first.insert(Clip(id: nil, type: .text, textContent: "survivor", imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))

        let reopened = try ClipStore(dbQueue: dbQueue, retentionCount: 500)
        let all = try reopened.fetchAll()

        XCTAssertEqual(all.count, 1, "migration must not lose rows")
        XCTAssertEqual(all.first?.textContent, "survivor")
        XCTAssertNil(all.first?.ocrText, "an existing clip has no recognised text")
    }

    func testSetOCRTextRoundTrips() throws {
        let store = try makeStore()
        let inserted = try store.insert(Clip(id: nil, type: .image, textContent: nil, imageData: Data([0x01]), filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))
        let id = try XCTUnwrap(inserted.id)

        try store.setOCRText("INVOICE 2026-09", id: id)

        XCTAssertEqual(try store.fetchAll().first?.ocrText, "INVOICE 2026-09")
    }

    func testSetOCRTextOnAMissingRowIsANoOp() throws {
        let store = try makeStore()
        let inserted = try store.insert(Clip(id: nil, type: .image, textContent: nil, imageData: Data([0x01]), filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))
        let id = try XCTUnwrap(inserted.id)
        try store.delete(id: id)

        // Recognition finishes after the clip was evicted or deleted. This must not throw.
        XCTAssertNoThrow(try store.setOCRText("too late", id: id))
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testSetOCRTextNilClearsIt() throws {
        let store = try makeStore()
        let inserted = try store.insert(Clip(id: nil, type: .image, textContent: nil, imageData: Data([0x01]), filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0))
        let id = try XCTUnwrap(inserted.id)
        try store.setOCRText("something", id: id)

        try store.setOCRText(nil, id: id)

        XCTAssertNil(try store.fetchAll().first?.ocrText)
    }
```

`makeStore()` already exists in this file — do not redefine it.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClipStoreTests`
Expected: FAIL to build — `Clip` has no member `ocrText`, `ClipStore` has no member `setOCRText`.

- [ ] **Step 3: Add the property to `Clip`**

In `Sources/Pastie/Models/Clip.swift`, after `originDevice`, as the last stored property:

```swift
    /// Text recognised inside an image clip, or nil. Search-only: never pasted, never shown.
    /// Populated asynchronously after capture, so a freshly copied image is briefly stored
    /// with `ocrText == nil`.
    var ocrText: String? = nil
```

`hasSameContent(as:)` is unchanged — recognised text is not part of a Clip's identity, so an image that has been recognised and the same image freshly copied are still one Clip.

- [ ] **Step 4: Add migration 4 and `setOCRText` to `ClipStore`**

In `Sources/Pastie/Storage/ClipStore.swift`, inside `migrate(_:)`, after the `addSyncColumns` block:

```swift
        migrator.registerMigration("addOCRText") { db in
            try db.alter(table: "clip") { t in
                t.add(column: "ocrText", .text)
            }
        }
```

No index: search is an in-memory filter over the fetched clips, so nothing queries this column in SQL.

Then add the writer, next to `setSaved`:

```swift
    /// Writes recognised text onto a clip. A no-op when the row is gone — recognition finishes
    /// after capture, by which time the clip may have been evicted or deleted.
    func setOCRText(_ text: String?, id: Int64) throws {
        try dbQueue.write { db in
            if var clip = try Clip.fetchOne(db, key: id) {
                clip.ocrText = text
                try clip.update(db)
            }
        }
    }
```

- [ ] **Step 5: Run the full suite**

Run: `swift build && swift test`
Expected: PASS, every test — the four new ones and every pre-existing one, with no call-site changes anywhere.

- [ ] **Step 6: Commit**

```bash
git add Sources/Pastie/Models/Clip.swift Sources/Pastie/Storage/ClipStore.swift Tests/PastieTests/ClipStoreTests.swift
git commit -m "feat: migration 4 — add ocrText to clips

Recognised text from an image clip, written back after capture by the
OCR module. Search-only: it is never pasted or displayed. setOCRText is
a no-op on a missing row because recognition outlives the clip it came
from when the retention cap evicts it first."
```

---

### Task 2: Image clips match on recognised text

**Files:**
- Modify: `Sources/Pastie/Search/ClipSearch.swift`
- Test: `Tests/PastieTests/ClipSearchTests.swift`

**Interfaces:**
- Consumes: `Clip.ocrText` (Task 1).
- Produces: nothing new — `ClipSearch.filter(_:query:)` keeps its signature.

**Context you need:** `ClipSearch.filter` is a pure in-memory filter with one `switch` over `ClipType`, and the `.image` case currently returns `false` unconditionally — that hard `false` is the bug this whole feature exists to fix. Matching for text and file clips is lowercased substring containment; image matching must be the same, so the search box behaves identically whatever kind of clip it finds.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PastieTests/ClipSearchTests.swift`:

```swift
    private func imageClip(ocrText: String?) -> Clip {
        Clip(id: nil, type: .image, textContent: nil, imageData: Data([0x01]), filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0, ocrText: ocrText)
    }

    func testImageClipMatchesOnRecognisedText() {
        let clips = [imageClip(ocrText: "Invoice 2026-09 total 480"), imageClip(ocrText: "unrelated")]

        let result = ClipSearch.filter(clips, query: "invoice")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.ocrText, "Invoice 2026-09 total 480")
    }

    func testImageMatchingIsCaseInsensitiveLikeTextMatching() {
        let clips = [imageClip(ocrText: "SHIPPING LABEL")]

        XCTAssertEqual(ClipSearch.filter(clips, query: "shipping").count, 1)
    }

    func testImageClipWithoutRecognisedTextNeverMatches() {
        let clips = [imageClip(ocrText: nil)]

        XCTAssertTrue(ClipSearch.filter(clips, query: "anything").isEmpty)
    }

    func testImageClipsStillSurviveAnEmptyQuery() {
        let clips = [imageClip(ocrText: nil), imageClip(ocrText: "text")]

        XCTAssertEqual(ClipSearch.filter(clips, query: "").count, 2, "an un-recognised image is still in the history")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClipSearchTests`
Expected: FAIL — `testImageClipMatchesOnRecognisedText` and `testImageMatchingIsCaseInsensitiveLikeTextMatching` return zero results, because the `.image` case returns `false`.

- [ ] **Step 3: Match on `ocrText`**

In `Sources/Pastie/Search/ClipSearch.swift`, replace the `.image` case:

```swift
            case .image: return clip.ocrText?.lowercased().contains(lowered) ?? false
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipSearchTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/Search/ClipSearch.swift Tests/PastieTests/ClipSearchTests.swift
git commit -m "feat: image clips are searchable by their recognised text

Replaces the unconditional false in ClipSearch's image case. Matching is
lowercased substring containment, the same rule text and file clips use,
so the search box behaves identically whatever it finds."
```

---

### Task 3: The recogniser — protocol and Vision implementation

**Files:**
- Create: `Sources/Pastie/OCR/TextRecognizing.swift`
- Create: `Sources/Pastie/OCR/VisionTextRecognizer.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `protocol TextRecognizing { func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) }`
  - `final class VisionTextRecognizer: TextRecognizing` with `init()`.

**Context you need:** This is the same shape as `SecretStore` in `Sources/Pastie/Sync/SyncCrypto.swift` and `AccessibilityStatus` in `Sources/Pastie/Support/`: a protocol so the consumer can be tested against a fake, plus one real implementation that is a thin adapter over a framework. Like `SyncService`, the real implementation gets **no unit tests** — its behaviour is Vision's, and a test would assert that Apple's OCR works.

`VNImageRequestHandler(data:options:)` accepts the TIFF bytes Pastie already holds, so no `NSImage` → `CGImage` conversion is needed. `VNRecognizeTextRequest.results` is `[VNRecognizedTextObservation]`; each observation's `topCandidates(1).first?.string` is the best reading of one line.

Recognition runs on a private serial queue. Serial, not concurrent: a burst of copies should queue behind each other rather than start N Vision requests at once, and image recognition is CPU-heavy enough that parallelism here would compete with the UI.

- [ ] **Step 1: Write `TextRecognizing.swift`**

```swift
// Sources/Pastie/OCR/TextRecognizing.swift
import Foundation

/// Reads text out of image bytes. The seam that keeps Vision out of the capture path's tests.
///
/// `completion` is called on an unspecified queue — callers that touch UI must hop themselves.
/// A nil result means "nothing searchable came back": no text found, or recognition failed.
/// The two are not distinguished because no caller benefits from telling them apart.
protocol TextRecognizing {
    func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void)
}
```

- [ ] **Step 2: Write `VisionTextRecognizer.swift`**

```swift
// Sources/Pastie/OCR/VisionTextRecognizer.swift
import Foundation
import Vision

/// The only file in Pastie that imports Vision.
///
/// On-device text recognition: nothing is uploaded, and no entitlement is required. Failure is
/// always silent from the user's point of view — a clip that could not be read is simply not
/// searchable, which is exactly how every image clip behaved before this feature.
final class VisionTextRecognizer: TextRecognizing {
    /// Serial on purpose: a burst of copied screenshots should queue rather than start several
    /// CPU-heavy Vision requests at once.
    private let queue = DispatchQueue(label: "com.stav.pastie.ocr")

    func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) {
        queue.async {
            completion(Self.recognize(imageData))
        }
    }

    private static func recognize(_ imageData: Data) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("VisionTextRecognizer: recognition failed: \(error)")
            return nil
        }

        guard let observations = request.results else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds clean, no warnings. Nothing constructs `VisionTextRecognizer` yet — that is Task 5.

- [ ] **Step 4: Run the full suite to confirm nothing regressed**

Run: `swift test`
Expected: PASS, the same count as after Task 2. These two files add no tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/OCR/
git commit -m "feat: add on-device text recognition behind a protocol

TextRecognizing is the seam that keeps Vision out of the capture path's
tests; VisionTextRecognizer is the only file importing Vision. Requests
run on a serial queue so a burst of copies queues instead of starting
several CPU-heavy recognitions at once."
```

---

### Task 4: The setting — store, view model, Capture tab

**Files:**
- Modify: `Sources/Pastie/Preferences/PreferencesStore.swift`
- Modify: `Sources/Pastie/UI/PreferencesViewModel.swift`
- Modify: `Sources/Pastie/UI/SettingsTabs/CaptureTab.swift`
- Test: `Tests/PastieTests/PreferencesStoreTests.swift`
- Test: `Tests/PastieTests/PreferencesViewModelTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `PreferencesStore.ocrEnabled: Bool` (default `true`) and `PreferencesViewModel.ocrEnabled: Bool` (`@Published`). Task 5 reads the store property.

**Context you need:** `PreferencesStore` uses `defaults.object(forKey:) as? Bool ?? true` for every default-on flag, never `defaults.bool(forKey:)` — the latter reports `false` for "never set", which would silently ship the feature switched off. `PreferencesViewModel` mirrors each store property as an `@Published` with a `didSet` that writes through; the tabs bind to the view model, never to the store. `CaptureTab` is a `SettingsForm` of `Section`s, each with a `header` and a `SettingHint` footer.

The toggle belongs in the existing **Images** section, under the size picker, and is disabled when `captureImages` is off — recognising text in images that are never captured is meaningless.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PastieTests/PreferencesStoreTests.swift`:

```swift
    func testOCRDefaultsToOn() {
        let defaults = UserDefaults(suiteName: "PastieTests.ocr.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults)

        XCTAssertTrue(store.ocrEnabled, "reading text inside images is on by default")
    }

    func testOCRSettingRoundTrips() {
        let defaults = UserDefaults(suiteName: "PastieTests.ocr.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults)

        store.ocrEnabled = false

        XCTAssertFalse(store.ocrEnabled)
        XCTAssertFalse(PreferencesStore(defaults: defaults).ocrEnabled, "the setting survives a fresh store")
    }
```

Add to `Tests/PastieTests/PreferencesViewModelTests.swift`:

```swift
    func testOCRTogglePersistsToTheStore() {
        let defaults = UserDefaults(suiteName: "PastieTests.vm.ocr.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults)
        let viewModel = PreferencesViewModel(store: store)

        XCTAssertTrue(viewModel.ocrEnabled, "the view model starts from the store's default")

        viewModel.ocrEnabled = false

        XCTAssertFalse(store.ocrEnabled, "the toggle writes through")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesStoreTests` then `swift test --filter PreferencesViewModelTests`
Expected: FAIL to build — no member `ocrEnabled` on either type.

- [ ] **Step 3: Add the preference key and accessor**

In `Sources/Pastie/Preferences/PreferencesStore.swift`, add to `Keys`:

```swift
        static let ocrEnabled = "ocrEnabled"
```

and the accessor, next to `rtfCaptureEnabled`:

```swift
    /// Recognise text inside captured images so they can be searched. On-device; the recognised
    /// text is never pasted or displayed. `object(forKey:)` rather than `bool(forKey:)` because
    /// the default is true and an unset key must not read as false.
    var ocrEnabled: Bool {
        get { defaults.object(forKey: Keys.ocrEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.ocrEnabled) }
    }
```

- [ ] **Step 4: Mirror it on the view model**

In `Sources/Pastie/UI/PreferencesViewModel.swift`, add the published property next to `rtfCaptureEnabled`:

```swift
    @Published var ocrEnabled: Bool {
        didSet { store.ocrEnabled = ocrEnabled }
    }
```

and seed it in `init`, alongside the other assignments (before the `hotkeyDisplay` line):

```swift
        self.ocrEnabled = store.ocrEnabled
```

Swift requires every stored property to be initialised before `self` is used, and the existing initialiser already follows that order — put the assignment with the other `self.x = store.x` lines.

- [ ] **Step 5: Add the toggle to the Capture tab**

In `Sources/Pastie/UI/SettingsTabs/CaptureTab.swift`, extend the existing **Images** section so it reads:

```swift
            Section {
                Picker("Keep images up to", selection: $viewModel.maxImageSizeMB) {
                    Text("1 MB").tag(1)
                    Text("5 MB").tag(5)
                    Text("10 MB").tag(10)
                    Text("25 MB").tag(25)
                }
                .pickerStyle(.segmented)
                Toggle("Search text inside images", isOn: $viewModel.ocrEnabled)
                    .disabled(!viewModel.captureImages)
            } header: {
                Text("Images")
            } footer: {
                SettingHint("Anything larger is stored as a 400-point-wide thumbnail. The original is not kept. Text inside images is read on this Mac so you can search for it — it is never pasted or sent anywhere.")
            }
```

- [ ] **Step 6: Run the full suite**

Run: `swift build && swift test`
Expected: PASS, including the three new tests.

- [ ] **Step 7: Manual verification**

Run `swift run Pastie`, open Preferences (⌘,) → Capture. Confirm: the Images section shows "Search text inside images", on by default; turning "Images" off in the first section greys the new toggle out; quitting and relaunching remembers the toggle's state.

- [ ] **Step 8: Commit**

```bash
git add Sources/Pastie/Preferences/PreferencesStore.swift Sources/Pastie/UI/PreferencesViewModel.swift Sources/Pastie/UI/SettingsTabs/CaptureTab.swift Tests/PastieTests/
git commit -m "feat: add the setting for reading text inside images

On by default, in the Capture tab's Images section, disabled when image
capture itself is off. Read through object(forKey:) rather than
bool(forKey:) so an unset key does not ship the feature switched off."
```

---

### Task 5: Wire recognition into capture

**Files:**
- Modify: `Sources/Pastie/Capture/ClipboardMonitor.swift`
- Modify: `Sources/Pastie/AppDelegate.swift`
- Test: `Tests/PastieTests/ClipboardMonitorTests.swift`

**Interfaces:**
- Consumes: `ClipStore.setOCRText(_:id:)` (Task 1), `TextRecognizing` (Task 3), `PreferencesStore.ocrEnabled` (Task 4).
- Produces: `ClipboardMonitor.init(store:preferences:recognizer:pollInterval:)` with `recognizer: TextRecognizing? = nil`, and `ClipboardMonitor.makeClip(from:sourceApp:) -> CapturedClip?` where `struct CapturedClip { let clip: Clip; let originalImageData: Data? }`.

**Context you need — the hazard this task exists to avoid:** `downsampleIfNeeded` shrinks any image over `maxImageSizeMB` to **400 points wide** before it is stored. Running OCR on that thumbnail would read almost nothing off a screenshot: a 2560-wide screenshot's text is illegible at 400 points. Recognition must therefore see the **original** TIFF while the row keeps the downsampled bytes.

That is why `makeClip` changes its return type. The alternative — re-reading `NSImage(pasteboard:)?.tiffRepresentation` in `tick()` — would decode a large image a second time on the timer's thread, which is the main thread. Returning both values from the one decode costs nothing and keeps the expensive work in one place.

`makeClip` is `internal` (not `private`) so the tests can call it directly; `ClipboardMonitorTests` calls it in **seven** places. Those call sites become `makeClip(...)?.clip`.

`store.insert` returns the inserted `Clip`, with its `id` populated by GRDB's `didInsert`. `tick()` currently discards that return value; it now needs it to address the write-back.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PastieTests/ClipboardMonitorTests.swift`:

```swift
    /// Records what it was asked to read and answers immediately, so the tests stay synchronous.
    final class FakeRecognizer: TextRecognizing {
        private(set) var receivedData: [Data] = []
        var result: String?

        init(result: String? = nil) {
            self.result = result
        }

        func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void) {
            receivedData.append(imageData)
            completion(result)
        }
    }

    private func makeMonitor(recognizer: TextRecognizing?, maxImageSizeMB: Int = 25) throws -> (ClipboardMonitor, ClipStore, PreferencesStore) {
        let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
        let prefs = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-monitor-ocr-\(UUID())")!)
        prefs.maxImageSizeMB = maxImageSizeMB
        let monitor = ClipboardMonitor(store: store, preferences: prefs, recognizer: recognizer)
        return (monitor, store, prefs)
    }

    /// A solid-colour PNG-backed TIFF of the given size. Big sizes are what push a clip past the
    /// downsample threshold; the content does not matter because the recogniser is faked.
    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.white.drawSwatch(in: NSRect(x: 0, y: 0, width: width, height: height))
        image.unlockFocus()
        return image.tiffRepresentation!
    }

    private func copyImageToPasteboard(_ data: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .tiff)
    }

    func testCapturedImageIsRecognisedAndTheTextLandsOnTheClip() throws {
        let recognizer = FakeRecognizer(result: "INVOICE 2026-09")
        let (monitor, store, _) = try makeMonitor(recognizer: recognizer)
        copyImageToPasteboard(makeImageData(width: 40, height: 40))

        monitor.tick()

        XCTAssertEqual(recognizer.receivedData.count, 1, "an image clip is handed to the recogniser once")
        XCTAssertEqual(try store.fetchAll().first?.ocrText, "INVOICE 2026-09")
    }

    func testRecogniserSeesTheOriginalImageNotTheDownsampledOne() throws {
        // 1MB cap with a large image forces downsampleIfNeeded to shrink what is stored.
        let recognizer = FakeRecognizer(result: "read me")
        let (monitor, store, _) = try makeMonitor(recognizer: recognizer, maxImageSizeMB: 1)
        let original = makeImageData(width: 1200, height: 1200)
        copyImageToPasteboard(original)

        monitor.tick()

        let stored = try XCTUnwrap(try store.fetchAll().first?.imageData)
        XCTAssertLessThan(stored.count, original.count, "precondition: the stored image was downsampled")
        XCTAssertEqual(recognizer.receivedData.first?.count, original.count, "OCR must read the full-size image, not the 400-point thumbnail")
    }

    func testRecognitionIsSkippedWhenTheSettingIsOff() throws {
        let recognizer = FakeRecognizer(result: "should not be read")
        let (monitor, store, prefs) = try makeMonitor(recognizer: recognizer)
        prefs.ocrEnabled = false
        copyImageToPasteboard(makeImageData(width: 40, height: 40))

        monitor.tick()

        XCTAssertTrue(recognizer.receivedData.isEmpty)
        XCTAssertNil(try store.fetchAll().first?.ocrText)
    }

    func testTextClipsNeverReachTheRecogniser() throws {
        let recognizer = FakeRecognizer(result: "should not be read")
        let (monitor, _, _) = try makeMonitor(recognizer: recognizer)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("plain words \(UUID())", forType: .string)

        monitor.tick()

        XCTAssertTrue(recognizer.receivedData.isEmpty)
    }

    func testAnEmptyRecognitionLeavesTheClipUnsearchableWithoutFailing() throws {
        let recognizer = FakeRecognizer(result: nil)
        let (monitor, store, _) = try makeMonitor(recognizer: recognizer)
        copyImageToPasteboard(makeImageData(width: 40, height: 40))

        monitor.tick()

        XCTAssertEqual(try store.fetchAll().count, 1, "the image clip is stored either way")
        XCTAssertNil(try store.fetchAll().first?.ocrText)
    }

    func testCaptureWorksWithNoRecogniserAtAll() throws {
        let (monitor, store, _) = try makeMonitor(recognizer: nil)
        copyImageToPasteboard(makeImageData(width: 40, height: 40))

        monitor.tick()

        XCTAssertEqual(try store.fetchAll().count, 1)
        XCTAssertNil(try store.fetchAll().first?.ocrText)
    }
```

Then update all seven existing `makeClip` call sites in this file: `monitor.makeClip(from: pasteboard, sourceApp: nil)` becomes `monitor.makeClip(from: pasteboard, sourceApp: nil)?.clip`. Search the file for `makeClip(` and change every one — the assertions that follow them (`clip?.type`, `clip?.textContent`, `clip?.rtfData`) are unchanged.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClipboardMonitorTests`
Expected: FAIL to build — `ClipboardMonitor.init` has no `recognizer:` parameter, and `CapturedClip` does not exist.

- [ ] **Step 3: Return the original bytes from `makeClip`**

In `Sources/Pastie/Capture/ClipboardMonitor.swift`, above the class, add:

```swift
/// What one pasteboard read produced: the Clip to store, plus — for images — the full-size bytes
/// before downsampling. Text recognition needs the original: downsampleIfNeeded shrinks anything
/// over the size cap to 400 points wide, which leaves a screenshot's text unreadable.
struct CapturedClip {
    let clip: Clip
    let originalImageData: Data?
}
```

Change `makeClip`'s signature and its three `return`s:

```swift
    func makeClip(from pasteboard: NSPasteboard, sourceApp: String?) -> CapturedClip? {
        let now = Date()
        switch inferClipType(from: pasteboard) {
        case .file:
            guard let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  let first = fileURLs.first else { return nil }
            return CapturedClip(
                clip: Clip(id: nil, type: .file, textContent: nil, imageData: nil, filePath: first.path, sourceApp: sourceApp, timestamp: now, saved: false, sortOrder: 0),
                originalImageData: nil
            )
        case .image:
            if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation {
                let data = downsampleIfNeeded(tiff)
                return CapturedClip(
                    clip: Clip(id: nil, type: .image, textContent: nil, imageData: data, filePath: nil, sourceApp: sourceApp, timestamp: now, saved: false, sortOrder: 0),
                    originalImageData: tiff
                )
            }
            // The image type was declared but nothing decodable came back; a string beside it is
            // better than dropping the copy entirely.
            return textClip(from: pasteboard, sourceApp: sourceApp, now: now).map {
                CapturedClip(clip: $0, originalImageData: nil)
            }
        case .text:
            return textClip(from: pasteboard, sourceApp: sourceApp, now: now).map {
                CapturedClip(clip: $0, originalImageData: nil)
            }
        case .none:
            return nil
        }
    }
```

Leave `textClip` returning `Clip?` — only `makeClip` wraps it. If the existing `switch` has a different `case .none`/`default` spelling, keep whichever it uses; only the return values change.

- [ ] **Step 4: Accept a recogniser and kick it off after insert**

Add the stored property and initialiser parameter:

```swift
    private let recognizer: TextRecognizing?

    init(store: ClipStore, preferences: PreferencesStore, recognizer: TextRecognizing? = nil, pollInterval: TimeInterval = 0.5) {
        self.store = store
        self.preferences = preferences
        self.recognizer = recognizer
        self.pollInterval = pollInterval
        self.lastChangeCount = NSPasteboard.general.changeCount
    }
```

`recognizer` is optional and defaults to `nil` so every existing construction — the tests, and anything that does not want OCR — compiles unchanged.

In `tick()`, replace the capture-and-insert tail:

```swift
        guard let captured = makeClip(from: pasteboard, sourceApp: bundleID) else { return }

        if let last = try? store.mostRecent(), last.hasSameContent(as: captured.clip) {
            return
        }

        do {
            let inserted = try store.insert(captured.clip)
            recognizeIfNeeded(captured, insertedID: inserted.id)
        } catch {
            NSLog("ClipboardMonitor: failed to insert clip: \(error)")
        }
```

and add:

```swift
    /// Hands an image clip's original bytes to the recogniser and writes the result back. The clip
    /// is already stored and visible by this point — recognition only makes it findable, so
    /// nothing waits on it and every failure is silent.
    private func recognizeIfNeeded(_ captured: CapturedClip, insertedID: Int64?) {
        guard captured.clip.type == .image,
              preferences.ocrEnabled,
              let recognizer,
              let imageData = captured.originalImageData,
              let id = insertedID else { return }

        recognizer.recognizeText(in: imageData) { [weak self] text in
            guard let self, let text else { return }
            do {
                try self.store.setOCRText(text, id: id)
            } catch {
                NSLog("ClipboardMonitor: failed to store recognised text: \(error)")
            }
        }
    }
```

The `guard let text else { return }` is why a nil result leaves the column untouched: there is nothing to write, and the clip is already correct.

- [ ] **Step 5: Inject the real recogniser in `AppDelegate`**

In `Sources/Pastie/AppDelegate.swift`, change the monitor's construction:

```swift
        monitor = ClipboardMonitor(store: clipStore, preferences: preferences, recognizer: VisionTextRecognizer())
```

Nothing else in `AppDelegate` changes.

- [ ] **Step 6: Run the full suite**

Run: `swift build && swift test`
Expected: PASS — the six new monitor tests, the updated `makeClip` call sites, and every pre-existing test.

- [ ] **Step 7: Manual verification**

Run `swift run Pastie`, then:

1. Take a screenshot of a page with clear text (⇧⌘4, then copy it, or ⌃⇧⌘4 to copy directly).
2. Wait a second, open the popup (⌥⌘V), and type a distinctive word from the screenshot. The image row should appear.
3. Turn "Search text inside images" off in Preferences → Capture, copy a second screenshot, and search a word from it — nothing should match.
4. Turn it back on, copy a very large screenshot (bigger than the size cap), and search a word from it. It should still match — this is the downsample hazard, verified end to end against real Vision.

- [ ] **Step 8: Commit**

```bash
git add Sources/Pastie/Capture/ClipboardMonitor.swift Sources/Pastie/AppDelegate.swift Tests/PastieTests/ClipboardMonitorTests.swift
git commit -m "feat: recognise text in captured images so they can be searched

makeClip now returns the original image bytes beside the Clip, because
downsampleIfNeeded shrinks oversized images to 400 points wide and a
screenshot's text is unreadable at that size. Recognition runs after the
insert, off the capture path, and writes the text back to the row; the
clip is stored and visible either way."
```

---

## After the plan

The README's feature list and its "What Pastie can see" section both describe capture behaviour and should mention that text inside images is read on-device and searchable. That is a documentation pass over `README.md`, not a code task — do it once the feature is verified by hand, in its own commit.
