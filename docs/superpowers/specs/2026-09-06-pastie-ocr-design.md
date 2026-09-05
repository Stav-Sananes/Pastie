# Pastie — Searchable Text Inside Images (OCR)

Status: approved (chat), pending write-up review
Scope: `Clip`, `ClipStore` (migration 4), `ClipboardMonitor`, `ClipSearch`,
`PreferencesStore`, `CaptureTab`, plus a new `Sources/Pastie/OCR/` module.
Out of scope: `PopupWindowController`, `PasteEngine`, the `Sync/` module.

## Why

Pastie stores image clips and shows them in the history, but they are invisible
to search: `ClipSearch.filter` returns `false` for every `.image` clip. Copy a
screenshot of an invoice and the only way back to it is scrolling. Every
clipboard manager that competes on features — Paste, Pastery, Clibbits, Clipsy —
now reads text inside screenshots and makes it searchable, and it is the one
capability whose absence is visible the moment a user copies a screenshot.

Apple's Vision framework does this on-device, with no network call, no account,
and no dependency to add. That fits the constraints Pastie already committed to:
direct download, no App Sandbox, nothing leaves the machine (ADR 0001).

## What this is, and is not

**Is:** a hidden search index. Typing `invoice` in the popup finds the
screenshot of an invoice. The clip is still an image and still pastes as an
image.

**Is not:** a screenshot-to-text feature. There is no "paste the recognised
text" verb, no Transform over `ocrText`, no OCR result shown in the UI. Pasting
machine-read text into real work, with its silent transcription errors, is a
different feature with different failure costs; if it is ever wanted it is a
separate spec.

Also excluded, deliberately:

- **No backfill.** Images already in the history stay unsearchable until they
  are copied again. A one-time pass over 500 stored images on first launch after
  an upgrade buys a better day-one demo at the cost of a CPU burst, progress
  reporting, and cancellation — none of which the feature needs to be useful.
- **No language picker.** Vision's automatic language handling, with the
  system's languages, is what ships. A picker is a settings row for a
  preference almost nobody changes.
- **No confidence threshold, bounding boxes, or per-word data.** The output is
  one string per image or nothing.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Purpose | Search index only | See above. |
| When OCR runs | Asynchronously, right after the clip is inserted | Vision takes ~100–500ms; the capture tick fires every 0.5s, so it cannot run inline without stalling capture. |
| Scope | New image clips only | No backfill (see above). |
| User control | One toggle in the Capture tab, default on | Mirrors `rtfCaptureEnabled`. OCR is exactly the kind of thing a privacy-minded user wants to switch off. |
| Storage | `ocrText` column on `clip` | A `clip_ocr` side table buys a join and a second delete path for capability ("search only") that does not use it. |
| Search | Extend the existing in-memory `ClipSearch` filter | FTS5 would rebuild working search semantics to solve a scale problem that ≤500 in-memory rows do not have. A search rewrite is its own decision, not a rider on OCR. |

## Components

### New — `Sources/Pastie/OCR/TextRecognizing.swift`

```swift
protocol TextRecognizing {
    /// Recognises text in `imageData`, calling back on an unspecified queue.
    /// nil means nothing was found or recognition failed — both are "not searchable".
    func recognizeText(in imageData: Data, completion: @escaping (String?) -> Void)
}
```

The testability seam, in the same shape as `SecretStore` and
`AccessibilityStatus`: tests inject a fake and assert on what the monitor does
with the result, without running Vision.

`nil` and `""` are not distinguished. Neither is searchable, and no caller
benefits from telling them apart.

### New — `Sources/Pastie/OCR/VisionTextRecognizer.swift`

The only file in the project that imports Vision.

- `VNImageRequestHandler(data:options:)` + `VNRecognizeTextRequest`.
- `recognitionLevel = .accurate`, `usesLanguageCorrection = true`, languages left
  to Vision's default.
- Joins each observation's top candidate with `\n`, in the order Vision returns
  them.
- Runs the request on its own serial `DispatchQueue` (`com.stav.pastie.ocr`),
  so a burst of copies queues instead of spawning threads.
- Returns `nil` on a thrown error, on no observations, or on an all-whitespace
  result. Errors are logged with `NSLog`, never surfaced in the UI — a failed
  recognition means one clip is not searchable, which is exactly the status quo.

Like `SyncService`, this file gets no unit tests of its own: it is a thin
adapter over a framework, and its behaviour is Vision's.

### Modified — `Sources/Pastie/Models/Clip.swift`

```swift
/// Text recognised inside an image clip, or nil. Search-only: never pasted,
/// never shown. Populated asynchronously after capture, so a freshly copied
/// image is briefly present with `ocrText == nil`.
var ocrText: String? = nil
```

Declared last, defaulted, so no existing `Clip(...)` call site changes — the
same property the `rtfData`/`slotIndex`/`originDevice` additions relied on.

### Modified — `Sources/Pastie/Storage/ClipStore.swift`

Migration 4, registered after `addSyncColumns`:

```swift
migrator.registerMigration("addOCRText") { db in
    try db.alter(table: "clip") { t in
        t.add(column: "ocrText", .text)
    }
}
```

No index. Search is an in-memory filter; an index on a column nothing queries in
SQL is dead weight.

```swift
/// Writes recognised text onto a clip. A no-op when the row is gone — a clip can
/// be evicted or deleted while recognition is still running.
func setOCRText(_ text: String?, id: Int64) throws
```

### Modified — `Sources/Pastie/Capture/ClipboardMonitor.swift`

Takes a `TextRecognizing?` in its initialiser, defaulting to `nil` so existing
call sites and tests compile unchanged; `AppDelegate` passes a
`VisionTextRecognizer`.

`makeClip`'s `.image` branch keeps the **original** TIFF alongside the
(possibly downsampled) bytes it stores. After a successful insert, if the clip
is `.image`, `preferences.ocrEnabled` is true, a recognizer exists, and the
inserted clip has an id, the monitor calls `recognizeText(in:)` with the
original bytes and writes the result back with `setOCRText`.

**This is the one non-obvious constraint in the design.** `downsampleIfNeeded`
reduces images over the size cap to 400px wide, which destroys most screenshot
text. OCR must see the pre-downsample bytes while the row stores the
post-downsample bytes.

### Modified — `Sources/Pastie/Search/ClipSearch.swift`

```swift
case .image: return clip.ocrText?.lowercased().contains(lowered) ?? false
```

Matching stays substring, case-insensitive, consistent with text and file clips.

### Modified — `Sources/Pastie/Preferences/PreferencesStore.swift`

```swift
/// Recognise text inside captured images so they can be searched. On-device; the
/// recognised text is never pasted or displayed.
var ocrEnabled: Bool {
    get { defaults.object(forKey: Keys.ocrEnabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Keys.ocrEnabled) }
}
```

`object(forKey:) as? Bool ?? true`, not `bool(forKey:)`, because the default is
`true` and an unset key must not read as `false`.

### Modified — `Sources/Pastie/UI/PreferencesViewModel.swift`

`@Published var ocrEnabled: Bool`, written through to `PreferencesStore` in the
same pattern as the existing capture properties. The tabs bind to the view
model, never to the store directly.

### Modified — `Sources/Pastie/UI/SettingsTabs/CaptureTab.swift`

One toggle under the image capture controls, bound to `viewModel.ocrEnabled`:
**"Search text inside images"**,
with the help text *"Reads text from screenshots on this Mac so you can search
for it. The text is never pasted or sent anywhere."* Disabled when image capture
itself is off — OCR on images that are never captured is meaningless.

## Data flow

```
tick()
  └─ makeClip()                    original TIFF kept beside stored bytes
  └─ store.insert(clip)            image is in the history immediately
  └─ guard type == .image, ocrEnabled, recognizer != nil, id != nil
       └─ recognizer.recognizeText(in: originalTIFF) ── serial OCR queue
            └─ store.setOCRText(text, id:)            no-op if the row is gone
                 └─ next refresh() shows nothing new; the clip is now searchable
```

A freshly copied image is searchable a moment after it appears. Nothing in the
UI indicates the difference, and nothing needs to: the user is not waiting on it.

## Edge cases

| Case | Behaviour |
|---|---|
| Row evicted or deleted before recognition returns | `setOCRText` finds no row and does nothing. |
| Retention eviction during a slow recognition | Eviction counts unsaved clips and is unaffected; a late write never resurrects an evicted clip. |
| Same image copied twice | Dedup rejects the second copy at insert; it never reaches OCR. |
| Burst of image copies | The serial OCR queue processes them one at a time, in order. |
| Toggle switched off while a recognition is in flight | The completion still writes. The preference is read at kickoff; cancellation would be more code for a case with no cost. |
| Vision throws, or finds no text | `nil`, logged; the clip stays unsearchable, as it is today. |
| Image over the size cap | OCR sees the original bytes, the row stores the downsampled ones. |
| Non-image clips | Never touch OCR. |
| `ocrEnabled` off | No recognizer call; existing `ocrText` values are left alone and stay searchable. |

## Testing

| Test | What it pins |
|---|---|
| `ClipStoreTests.testMigrationAddsOCRTextColumn` | A pre-migration database gains `ocrText` as nil without losing rows. |
| `ClipStoreTests.testSetOCRTextRoundTrips` | Writing and reading back recognised text. |
| `ClipStoreTests.testSetOCRTextOnMissingRowIsANoOp` | The eviction race does not throw. |
| `ClipSearchTests.testImageClipMatchesOnOCRText` | An image with `ocrText` is found by a substring of it. |
| `ClipSearchTests.testImageClipWithoutOCRTextNeverMatches` | The current behaviour is preserved for un-OCR'd images. |
| `ClipboardMonitorTests.testImageCaptureKicksOffRecognition` | A fake recognizer receives the image and the result lands on the row. |
| `ClipboardMonitorTests.testRecognizerReceivesOriginalNotDownsampledBytes` | The size-cap hazard: an oversized image is OCR'd at full size. |
| `ClipboardMonitorTests.testOCRDisabledSkipsRecognition` | The toggle is honoured. |
| `ClipboardMonitorTests.testTextClipNeverReachesTheRecognizer` | Only image clips are recognised. |
| `PreferencesStoreTests.testOCRDefaultsToOn` | Unset reads as `true`, not `false`. |
| `PreferencesViewModelTests.testOCRTogglePersists` | The view model writes through to the store. |

`VisionTextRecognizer` has no unit tests — it is a framework adapter, verified
by using the app. Everything above runs against the `TextRecognizing` fake.

## Files

```
Sources/Pastie/
  OCR/TextRecognizing.swift          CREATE  protocol (the test seam)
  OCR/VisionTextRecognizer.swift     CREATE  the only file importing Vision
  Models/Clip.swift                  MODIFY  +ocrText (defaulted, declared last)
  Storage/ClipStore.swift            MODIFY  migration 4; setOCRText
  Capture/ClipboardMonitor.swift     MODIFY  keep original bytes; kick off OCR
  Search/ClipSearch.swift            MODIFY  image clips match on ocrText
  Preferences/PreferencesStore.swift MODIFY  +ocrEnabled (default true)
  UI/PreferencesViewModel.swift      MODIFY  +@Published ocrEnabled
  UI/SettingsTabs/CaptureTab.swift   MODIFY  +toggle
  AppDelegate.swift                  MODIFY  inject VisionTextRecognizer

Tests/PastieTests/
  ClipStoreTests.swift               MODIFY  migration, setOCRText
  ClipSearchTests.swift              MODIFY  image matching
  ClipboardMonitorTests.swift        MODIFY  fake recognizer cases
  PreferencesStoreTests.swift        MODIFY  default
  PreferencesViewModelTests.swift    MODIFY  toggle write-through
```

## Constraints inherited

- Platform floor macOS 13.0. Vision's `VNRecognizeTextRequest` predates it.
- No App Sandbox; no entitlement is needed for Vision.
- Nothing leaves the machine. Recognition is on-device; no network call exists in
  this design, and adding one would contradict ADR 0001.
- Migration numbering: v3 owns 2 (`savedAndRichPayload`), sync owns 3
  (`addSyncColumns`), this is 4 (`addOCRText`). GRDB replays in registration
  order.
