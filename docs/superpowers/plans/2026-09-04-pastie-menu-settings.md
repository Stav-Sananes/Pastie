# Pastie Menu Bar & Settings Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Pastie's plain menu-bar dropdown and single-page Preferences form with an icon/shortcut-labeled menu and a 4-tab Settings window (General/Hotkey/Capture/Appearance), closing the hotkey-remap gap the v1 spec called for but never shipped.

**Architecture:** No new persistence layer. Five new `PreferencesStore` keys (`UserDefaults`-backed, same pattern as existing keys) drive a type-gate check in `CaptureFilter`, a configurable image-size threshold in `ClipboardMonitor`, and three new SwiftUI tabs. A new pure `HotkeyCapture.isValidBinding` function backs a custom `NSViewRepresentable` hotkey recorder. `MenuBarController` and `PopupWindowController` each gain a `PreferencesStore` dependency to read live settings.

**Tech Stack:** Swift 5.9, AppKit + SwiftUI, XCTest. No new external dependencies.

**Spec:** `docs/superpowers/specs/2026-09-03-pastie-menu-settings-design.md`

## Global Constraints

- Platform: macOS 13+ (`Package.swift` `platforms: [.macOS(.v13)]`), Swift tools 5.9.
- No App Sandbox — Pastie ships Developer ID + notarized, local-only (per project ADR). Do not add sandboxing entitlements or assume a sandboxed container.
- No new external dependencies — existing `Package.swift` deps (`GRDB`, `HotKey`) cover everything this plan needs.
- Every `PreferencesStore`-backed test uses a fresh `UserDefaults(suiteName: "pastie-<component>-tests-\(UUID())")`, never `.standard` — this is how existing tests avoid polluting the real app's defaults.
- The Settings tab container must stay open to more tabs (a planned "Groups" tab and an "Actions" tab land in later work): one SwiftUI file per tab, `PreferencesView` just lists `tabItem`s — never hardcode "4 tabs" logic anywhere else.
- Out of scope for this plan: `PopupWindowController`'s search/list/paste behavior (only its panel height changes, in Task 6).

---

### Task 1: PreferencesStore — capture toggles, image size, popup row count

**Files:**
- Modify: `Sources/Pastie/Preferences/PreferencesStore.swift`
- Modify: `Tests/PastieTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: nothing new (extends the existing `PreferencesStore` class)
- Produces: `var captureText: Bool`, `var captureImages: Bool`, `var captureFiles: Bool` (all default `true`), `var maxImageSizeMB: Int` (default `5`), `var popupRowCount: Int` (default `8`) — all `UserDefaults`-backed, get/set, same pattern as `retentionCount`

- [ ] **Step 1: Write the failing tests**

Add these methods inside the existing `PreferencesStoreTests` class in `Tests/PastieTests/PreferencesStoreTests.swift`:

```swift
func testCaptureTypeTogglesDefaultToTrue() {
    let store = makeStore()
    XCTAssertTrue(store.captureText)
    XCTAssertTrue(store.captureImages)
    XCTAssertTrue(store.captureFiles)
}

func testCaptureTypeTogglesRoundTrip() {
    let store = makeStore()
    store.captureImages = false
    XCTAssertFalse(store.captureImages)
    XCTAssertTrue(store.captureText)
}

func testMaxImageSizeMBDefaultsTo5() {
    XCTAssertEqual(makeStore().maxImageSizeMB, 5)
}

func testMaxImageSizeMBRoundTrips() {
    let store = makeStore()
    store.maxImageSizeMB = 25
    XCTAssertEqual(store.maxImageSizeMB, 25)
}

func testPopupRowCountDefaultsTo8() {
    XCTAssertEqual(makeStore().popupRowCount, 8)
}

func testPopupRowCountRoundTrips() {
    let store = makeStore()
    store.popupRowCount = 12
    XCTAssertEqual(store.popupRowCount, 12)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesStoreTests`
Expected: FAIL to build — `captureText`/`captureImages`/`captureFiles`/`maxImageSizeMB`/`popupRowCount` not defined.

- [ ] **Step 3: Extend `PreferencesStore.swift`**

Replace the file with:

```swift
import AppKit
import Foundation

final class PreferencesStore {
    private let defaults: UserDefaults

    private enum Keys {
        static let excludedBundleIDs = "excludedBundleIDs"
        static let retentionCount = "retentionCount"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let launchAtLogin = "launchAtLogin"
        static let captureText = "captureText"
        static let captureImages = "captureImages"
        static let captureFiles = "captureFiles"
        static let maxImageSizeMB = "maxImageSizeMB"
        static let popupRowCount = "popupRowCount"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var excludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.excludedBundleIDs) }
    }

    var retentionCount: Int {
        get { defaults.object(forKey: Keys.retentionCount) as? Int ?? 500 }
        set { defaults.set(newValue, forKey: Keys.retentionCount) }
    }

    var hotkeyKeyCode: UInt32 {
        get { defaults.object(forKey: Keys.hotkeyKeyCode) as? UInt32 ?? 9 } // kVK_ANSI_V
        set { defaults.set(newValue, forKey: Keys.hotkeyKeyCode) }
    }

    var hotkeyModifiers: UInt32 {
        get {
            defaults.object(forKey: Keys.hotkeyModifiers) as? UInt32
                ?? UInt32(NSEvent.ModifierFlags([.option, .command]).rawValue)
        }
        set { defaults.set(newValue, forKey: Keys.hotkeyModifiers) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    var captureText: Bool {
        get { defaults.object(forKey: Keys.captureText) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.captureText) }
    }

    var captureImages: Bool {
        get { defaults.object(forKey: Keys.captureImages) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.captureImages) }
    }

    var captureFiles: Bool {
        get { defaults.object(forKey: Keys.captureFiles) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.captureFiles) }
    }

    var maxImageSizeMB: Int {
        get { defaults.object(forKey: Keys.maxImageSizeMB) as? Int ?? 5 }
        set { defaults.set(newValue, forKey: Keys.maxImageSizeMB) }
    }

    var popupRowCount: Int {
        get { defaults.object(forKey: Keys.popupRowCount) as? Int ?? 8 }
        set { defaults.set(newValue, forKey: Keys.popupRowCount) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreferencesStoreTests`
Expected: PASS (11 tests: 5 existing + 6 new)

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/Preferences/PreferencesStore.swift Tests/PastieTests/PreferencesStoreTests.swift
git commit -m "feat: add capture-type, image-size, and popup-row-count settings"
```

---

### Task 2: CaptureFilter type-gate + configurable image-size threshold

**Files:**
- Modify: `Sources/Pastie/Capture/CaptureFilter.swift`
- Modify: `Sources/Pastie/Capture/ClipboardMonitor.swift`
- Modify: `Tests/PastieTests/CaptureFilterTests.swift`
- Modify: `Tests/PastieTests/ClipboardMonitorTests.swift`

**Interfaces:**
- Consumes: `PreferencesStore.captureText/captureImages/captureFiles/maxImageSizeMB` (Task 1), `ClipType` (existing, `Sources/Pastie/Models/Clip.swift`)
- Produces: `CaptureFilter.isTypeEnabled(_ type: ClipType, captureText: Bool, captureImages: Bool, captureFiles: Bool) -> Bool`

- [ ] **Step 1: Write the failing tests**

Add these methods inside the existing `CaptureFilterTests` class in `Tests/PastieTests/CaptureFilterTests.swift`:

```swift
func testIsTypeEnabledRespectsTextToggle() {
    XCTAssertTrue(CaptureFilter.isTypeEnabled(.text, captureText: true, captureImages: false, captureFiles: false))
    XCTAssertFalse(CaptureFilter.isTypeEnabled(.text, captureText: false, captureImages: true, captureFiles: true))
}

func testIsTypeEnabledRespectsImageToggle() {
    XCTAssertTrue(CaptureFilter.isTypeEnabled(.image, captureText: false, captureImages: true, captureFiles: false))
    XCTAssertFalse(CaptureFilter.isTypeEnabled(.image, captureText: true, captureImages: false, captureFiles: true))
}

func testIsTypeEnabledRespectsFileToggle() {
    XCTAssertTrue(CaptureFilter.isTypeEnabled(.file, captureText: false, captureImages: false, captureFiles: true))
    XCTAssertFalse(CaptureFilter.isTypeEnabled(.file, captureText: true, captureImages: true, captureFiles: false))
}
```

Add these methods inside the existing `ClipboardMonitorTests` class in `Tests/PastieTests/ClipboardMonitorTests.swift`:

```swift
func testTickSkipsImageWhenCaptureImagesDisabled() throws {
    let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
    let prefs = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-monitor-tests-\(UUID())")!)
    prefs.captureImages = false
    let monitor = ClipboardMonitor(store: store, preferences: prefs)

    NSPasteboard.general.clearContents()
    let image = NSImage(size: NSSize(width: 4, height: 4))
    image.lockFocus()
    NSColor.red.set()
    NSRect(x: 0, y: 0, width: 4, height: 4).fill()
    image.unlockFocus()
    NSPasteboard.general.writeObjects([image])

    monitor.tick()

    XCTAssertEqual(try store.fetchAll().count, 0)
}

func testTickCapturesImageWhenCaptureImagesEnabled() throws {
    let store = try ClipStore(dbQueue: try DatabaseQueue(), retentionCount: 500)
    let prefs = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-monitor-tests-\(UUID())")!)
    let monitor = ClipboardMonitor(store: store, preferences: prefs)

    NSPasteboard.general.clearContents()
    let image = NSImage(size: NSSize(width: 4, height: 4))
    image.lockFocus()
    NSColor.blue.set()
    NSRect(x: 0, y: 0, width: 4, height: 4).fill()
    image.unlockFocus()
    NSPasteboard.general.writeObjects([image])

    monitor.tick()

    let all = try store.fetchAll()
    XCTAssertEqual(all.count, 1)
    XCTAssertEqual(all.first?.type, .image)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CaptureFilterTests` — expected FAIL to build, `isTypeEnabled` not defined.
Run: `swift test --filter ClipboardMonitorTests` — expected PASS still (the new tests only fail once you confirm `isTypeEnabled` is wired into `tick()` in Step 4; run again after Step 4 if it passes prematurely here, that's fine — it means the default-true toggles didn't need gating to pass the "enabled" case, but `testTickSkipsImageWhenCaptureImagesDisabled` will FAIL until `tick()` actually checks the toggle).

- [ ] **Step 3: Add `isTypeEnabled` to `CaptureFilter.swift`**

Replace the file with:

```swift
import Foundation

struct CaptureContext {
    let pasteboardTypes: Set<String>
    let frontmostBundleID: String?
}

enum CaptureFilter {
    static let concealedType = "org.nspasteboard.ConcealedType"
    static let transientType = "org.nspasteboard.TransientType"

    static func shouldCapture(context: CaptureContext, excludedBundleIDs: Set<String>) -> Bool {
        if context.pasteboardTypes.contains(concealedType) || context.pasteboardTypes.contains(transientType) {
            return false
        }
        if let bundleID = context.frontmostBundleID, excludedBundleIDs.contains(bundleID) {
            return false
        }
        return true
    }

    /// Gates a clip by its type against the user's per-type capture toggles. Checked
    /// AFTER shouldCapture() and after the clip is built — shouldCapture() covers
    /// privacy signals (concealed/transient, excluded app) that must block reading
    /// pasteboard content at all; this only decides whether to store what was read.
    static func isTypeEnabled(_ type: ClipType, captureText: Bool, captureImages: Bool, captureFiles: Bool) -> Bool {
        switch type {
        case .text: return captureText
        case .image: return captureImages
        case .file: return captureFiles
        }
    }
}
```

- [ ] **Step 4: Wire the type-gate and configurable threshold into `ClipboardMonitor.swift`**

Replace the file with:

```swift
import AppKit
import Foundation

final class ClipboardMonitor {
    private let store: ClipStore
    private let preferences: PreferencesStore
    private var lastChangeCount: Int
    private var timer: Timer?
    private let pollInterval: TimeInterval
    /// Set by ignoreNextChange() right before Pastie writes to the pasteboard itself
    /// (e.g. during paste). The next tick() that observes a changed pasteboard is
    /// treated as our own write rather than a new external copy, so it isn't captured.
    private var ignoringSelfWrite = false

    init(store: ClipStore, preferences: PreferencesStore, pollInterval: TimeInterval = 0.5) {
        self.store = store
        self.preferences = preferences
        self.pollInterval = pollInterval
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call right before Pastie writes a clip to the pasteboard (e.g. from PasteEngine) so the
    /// resulting pasteboard change is not re-captured as a brand-new clip on the next tick().
    func ignoreNextChange() {
        ignoringSelfWrite = true
    }

    func tick() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if ignoringSelfWrite {
            ignoringSelfWrite = false
            return
        }

        let types = Set((pasteboard.types ?? []).map { $0.rawValue })
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let context = CaptureContext(pasteboardTypes: types, frontmostBundleID: bundleID)
        guard CaptureFilter.shouldCapture(context: context, excludedBundleIDs: preferences.excludedBundleIDs) else {
            return
        }

        guard let clip = makeClip(from: pasteboard, sourceApp: bundleID) else { return }

        guard CaptureFilter.isTypeEnabled(
            clip.type,
            captureText: preferences.captureText,
            captureImages: preferences.captureImages,
            captureFiles: preferences.captureFiles
        ) else { return }

        if let last = try? store.mostRecent(), last.hasSameContent(as: clip) {
            return
        }

        do {
            try store.insert(clip)
        } catch {
            NSLog("ClipboardMonitor: failed to insert clip: \(error)")
        }
    }

    private func makeClip(from pasteboard: NSPasteboard, sourceApp: String?) -> Clip? {
        let now = Date()
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = fileURLs.first, first.isFileURL {
            return Clip(id: nil, type: .file, textContent: nil, imageData: nil, filePath: first.path, sourceApp: sourceApp, timestamp: now, pinned: false, sortOrder: 0)
        }
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation {
            let data = downsampleIfNeeded(tiff)
            return Clip(id: nil, type: .image, textContent: nil, imageData: data, filePath: nil, sourceApp: sourceApp, timestamp: now, pinned: false, sortOrder: 0)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return Clip(id: nil, type: .text, textContent: text, imageData: nil, filePath: nil, sourceApp: sourceApp, timestamp: now, pinned: false, sortOrder: 0)
        }
        return nil
    }

    private func downsampleIfNeeded(_ data: Data) -> Data {
        let thresholdBytes = preferences.maxImageSizeMB * 1024 * 1024
        guard data.count > thresholdBytes,
              let image = NSImage(data: data), image.size.width > 0 else { return data }
        let targetWidth: CGFloat = 400
        let targetSize = NSSize(width: targetWidth, height: targetWidth * (image.size.height / image.size.width))
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize))
        thumbnail.unlockFocus()
        return thumbnail.tiffRepresentation ?? data
    }
}
```

Note: this removes the old `static let imageDownsampleThresholdBytes = 5 * 1024 * 1024` constant — it's replaced by `preferences.maxImageSizeMB * 1024 * 1024`, computed live so a Settings change takes effect on the next tick with no extra plumbing. Nothing else in the codebase references the old constant.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter CaptureFilterTests` — Expected: PASS (4 existing + 3 new)
Run: `swift test --filter ClipboardMonitorTests` — Expected: PASS (3 existing + 2 new)

- [ ] **Step 6: Commit**

```bash
git add Sources/Pastie/Capture/CaptureFilter.swift Sources/Pastie/Capture/ClipboardMonitor.swift Tests/PastieTests/CaptureFilterTests.swift Tests/PastieTests/ClipboardMonitorTests.swift
git commit -m "feat: gate capture by per-type toggle, make image-size threshold configurable"
```

---

### Task 3: HotkeyCapture — pure modifier-key validation

**Files:**
- Create: `Sources/Pastie/Hotkey/HotkeyCapture.swift`
- Create: `Tests/PastieTests/HotkeyCaptureTests.swift`

**Interfaces:**
- Consumes: nothing (pure function over `NSEvent.ModifierFlags`)
- Produces: `enum HotkeyCapture { static func isValidBinding(modifiers: NSEvent.ModifierFlags) -> Bool }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PastieTests/HotkeyCaptureTests.swift
import XCTest
import AppKit
@testable import Pastie

final class HotkeyCaptureTests: XCTestCase {
    func testRejectsBareKeyWithNoModifiers() {
        XCTAssertFalse(HotkeyCapture.isValidBinding(modifiers: []))
    }

    func testAcceptsCommandModifier() {
        XCTAssertTrue(HotkeyCapture.isValidBinding(modifiers: [.command]))
    }

    func testAcceptsOptionCommandCombo() {
        XCTAssertTrue(HotkeyCapture.isValidBinding(modifiers: [.option, .command]))
    }

    func testIgnoresCapsLockAndFunctionFlags() {
        // capsLock/function are device flags, not modifiers a user deliberately chose —
        // a combo carrying only these should still be rejected.
        XCTAssertFalse(HotkeyCapture.isValidBinding(modifiers: [.capsLock, .function]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HotkeyCaptureTests`
Expected: FAIL to build — `HotkeyCapture` not defined.

- [ ] **Step 3: Write `HotkeyCapture.swift`**

```swift
// Sources/Pastie/Hotkey/HotkeyCapture.swift
import AppKit
import Foundation

enum HotkeyCapture {
    /// A captured key combo must include at least one "real" modifier — a bare letter
    /// shouldn't silently rebind the global hotkey while the user is just typing, and
    /// capsLock/function are device state, not a deliberate modifier choice.
    static func isValidBinding(modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.intersection([.command, .option, .control, .shift]).isEmpty
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HotkeyCaptureTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/Hotkey/HotkeyCapture.swift Tests/PastieTests/HotkeyCaptureTests.swift
git commit -m "feat: add HotkeyCapture modifier-key validation"
```

---

### Task 4: HotkeyRecorderView — click-to-record hotkey field

**Files:**
- Create: `Sources/Pastie/UI/HotkeyRecorderView.swift`

**Interfaces:**
- Consumes: `HotkeyCapture.isValidBinding` (Task 3)
- Produces: `struct HotkeyRecorderView: NSViewRepresentable { init(displayText: String, onCapture: @escaping (UInt32, UInt32) -> Void) }`

- [ ] **Step 1: Write `HotkeyRecorderView.swift`**

```swift
// Sources/Pastie/UI/HotkeyRecorderView.swift
import AppKit
import SwiftUI

/// Captures the next key-down as a global hotkey binding. Click to start recording;
/// press a combo (must include a modifier — see HotkeyCapture); Escape cancels.
final class HotkeyRecorderNSView: NSView {
    var isRecording = false {
        didSet { needsDisplay = true }
    }
    var onCapture: ((UInt32, UInt32) -> Void)?
    private let label = NSTextField(labelWithString: "")

    var displayText: String = "" {
        didSet {
            guard !isRecording else { return }
            label.stringValue = displayText
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.frame = bounds
        label.autoresizingMask = [.width, .height]
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        label.stringValue = "Press a key combo…"
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { // Escape cancels
            isRecording = false
            label.stringValue = displayText
            return
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard HotkeyCapture.isValidBinding(modifiers: modifiers) else { return }
        isRecording = false
        onCapture?(UInt32(event.keyCode), UInt32(modifiers.rawValue))
    }

    override func updateLayer() {
        layer?.backgroundColor = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
            : NSColor.clear.cgColor
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    let displayText: String
    let onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView(frame: .zero)
        view.displayText = displayText
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.displayText = displayText
        nsView.onCapture = onCapture
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Manual test**

No automated test path — same reasoning as `HotkeyManager` in the v1 plan (no clean way to script global key-combo capture on macOS). Verified end-to-end once wired into the Hotkey tab in Task 9: click the field, press ⌃⇧S, confirm the label updates to "⌃⇧S"; press a bare letter (no modifier) — confirm it's ignored and recording stays active; press Escape — confirm recording cancels and the field reverts to the previous display text.

- [ ] **Step 4: Commit**

```bash
git add Sources/Pastie/UI/HotkeyRecorderView.swift
git commit -m "feat: add HotkeyRecorderView click-to-record hotkey field"
```

---

### Task 5: PreferencesViewModel — expose new settings + hotkey update

**Files:**
- Modify: `Sources/Pastie/UI/PreferencesViewModel.swift`
- Modify: `Tests/PastieTests/PreferencesViewModelTests.swift`

**Interfaces:**
- Consumes: `PreferencesStore` (Task 1), `HotkeyFormatter.displayString` (existing)
- Produces: adds `@Published var captureText/captureImages/captureFiles: Bool`, `@Published var maxImageSizeMB: Int`, `@Published var popupRowCount: Int`, `@Published var hotkeyDisplay: String`, `func updateHotkey(keyCode: UInt32, modifiers: UInt32)`; `init(store:onHotkeyChanged: @escaping () -> Void = {})` (new optional param, existing call sites with just `store:` keep compiling)

- [ ] **Step 1: Write the failing tests**

Add `import AppKit` to the top of `Tests/PastieTests/PreferencesViewModelTests.swift` (needed for `NSEvent.ModifierFlags` in the new test below), then add these methods inside the existing `PreferencesViewModelTests` class:

```swift
func testCaptureTogglesDefaultToTrueAndRoundTrip() {
    let vm = makeViewModel()
    XCTAssertTrue(vm.captureText)
    XCTAssertTrue(vm.captureImages)
    XCTAssertTrue(vm.captureFiles)
    vm.captureImages = false
    XCTAssertFalse(vm.captureImages)
}

func testUpdateHotkeyUpdatesDisplayAndFiresCallback() {
    var changed = false
    let store = PreferencesStore(defaults: UserDefaults(suiteName: "pastie-vm-hotkey-tests-\(UUID())")!)
    let vm = PreferencesViewModel(store: store, onHotkeyChanged: { changed = true })

    vm.updateHotkey(keyCode: 1, modifiers: UInt32(NSEvent.ModifierFlags([.control, .shift]).rawValue))

    XCTAssertEqual(vm.hotkeyDisplay, "⌃⇧S")
    XCTAssertTrue(changed)
    XCTAssertEqual(store.hotkeyKeyCode, 1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesViewModelTests`
Expected: FAIL to build — `captureText`/`updateHotkey`/`hotkeyDisplay` not defined.

- [ ] **Step 3: Extend `PreferencesViewModel.swift`**

Replace the file with:

```swift
import Combine
import Foundation

final class PreferencesViewModel: ObservableObject {
    private let store: PreferencesStore
    private let onHotkeyChanged: () -> Void

    @Published var retentionCount: Int {
        didSet { store.retentionCount = retentionCount }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            store.launchAtLogin = launchAtLogin
            LaunchAtLogin.set(launchAtLogin)
        }
    }
    @Published var excludedBundleIDs: [String]
    @Published var newBundleID: String = ""
    @Published var captureText: Bool {
        didSet { store.captureText = captureText }
    }
    @Published var captureImages: Bool {
        didSet { store.captureImages = captureImages }
    }
    @Published var captureFiles: Bool {
        didSet { store.captureFiles = captureFiles }
    }
    @Published var maxImageSizeMB: Int {
        didSet { store.maxImageSizeMB = maxImageSizeMB }
    }
    @Published var popupRowCount: Int {
        didSet { store.popupRowCount = popupRowCount }
    }
    @Published var hotkeyDisplay: String

    init(store: PreferencesStore, onHotkeyChanged: @escaping () -> Void = {}) {
        self.store = store
        self.onHotkeyChanged = onHotkeyChanged
        self.retentionCount = store.retentionCount
        self.launchAtLogin = store.launchAtLogin
        self.excludedBundleIDs = Array(store.excludedBundleIDs).sorted()
        self.captureText = store.captureText
        self.captureImages = store.captureImages
        self.captureFiles = store.captureFiles
        self.maxImageSizeMB = store.maxImageSizeMB
        self.popupRowCount = store.popupRowCount
        self.hotkeyDisplay = HotkeyFormatter.displayString(keyCode: store.hotkeyKeyCode, modifiers: store.hotkeyModifiers)
    }

    func addExcluded() {
        let trimmed = newBundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !excludedBundleIDs.contains(trimmed) else {
            newBundleID = ""
            return
        }
        excludedBundleIDs.append(trimmed)
        excludedBundleIDs.sort()
        store.excludedBundleIDs = Set(excludedBundleIDs)
        newBundleID = ""
    }

    func removeExcluded(at offsets: IndexSet) {
        for index in offsets {
            store.excludedBundleIDs.remove(excludedBundleIDs[index])
        }
        for index in offsets.sorted(by: >) {
            excludedBundleIDs.remove(at: index)
        }
    }

    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        store.hotkeyKeyCode = keyCode
        store.hotkeyModifiers = modifiers
        hotkeyDisplay = HotkeyFormatter.displayString(keyCode: keyCode, modifiers: modifiers)
        onHotkeyChanged()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreferencesViewModelTests`
Expected: PASS (3 existing + 2 new)

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/UI/PreferencesViewModel.swift Tests/PastieTests/PreferencesViewModelTests.swift
git commit -m "feat: expose capture settings and hotkey update on PreferencesViewModel"
```

---

### Task 6: PopupWindowController — configurable panel height

**Files:**
- Modify: `Sources/Pastie/UI/PopupWindowController.swift`
- Modify: `Sources/Pastie/AppDelegate.swift`
- Create: `Tests/PastieTests/PopupWindowControllerTests.swift`

**Interfaces:**
- Consumes: `PreferencesStore.popupRowCount` (Task 1)
- Produces: `PopupWindowController.panelHeight(forRows rows: Int) -> CGFloat` (static, pure); `init(store:pasteEngine:preferences:)` (adds `preferences: PreferencesStore` param — breaks the one existing call site in `AppDelegate.swift`, fixed in this same task)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PastieTests/PopupWindowControllerTests.swift
import XCTest
@testable import Pastie

final class PopupWindowControllerTests: XCTestCase {
    func testPanelHeightGrowsWithRowCount() {
        let four = PopupWindowController.panelHeight(forRows: 4)
        let eight = PopupWindowController.panelHeight(forRows: 8)
        XCTAssertGreaterThan(eight, four)
    }

    func testPanelHeightClampsBelowOneRow() {
        XCTAssertEqual(PopupWindowController.panelHeight(forRows: 0), PopupWindowController.panelHeight(forRows: 1))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PopupWindowControllerTests`
Expected: FAIL to build — `panelHeight` not defined.

- [ ] **Step 3: Add `panelHeight` and wire `preferences` into `PopupWindowController.swift`**

Replace the file with:

```swift
// Sources/Pastie/UI/PopupWindowController.swift
import AppKit

final class PopupWindowController: NSObject, NSWindowDelegate {
    /// Non-list chrome (search field + margins) in buildPanel()'s base layout — total
    /// panel height minus the space given to the row list.
    static let chromeHeight: CGFloat = 56
    static let rowHeight: CGFloat = 24

    static func panelHeight(forRows rows: Int) -> CGFloat {
        chromeHeight + CGFloat(max(1, rows)) * rowHeight
    }

    private let store: ClipStore
    private let pasteEngine: PasteEngine
    private let preferences: PreferencesStore
    private var panel: NSPanel!
    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var allClips: [Clip] = []
    private var filteredClips: [Clip] = []
    /// The app that was frontmost right before Pastie activated itself, so pasteSelection()
    /// can hand focus back to it before simulating ⌘V.
    private var previousApp: NSRunningApplication?
    /// Local key-down monitor active while the panel is visible, so Return/Escape work
    /// regardless of which control (search field or table view) currently has focus.
    private var keyMonitor: Any?
    /// Told to ignore the pasteboard change caused by our own paste-as-list writes, so
    /// ClipboardMonitor.tick() doesn't re-capture what we just pasted as a brand-new clip.
    weak var clipboardMonitor: ClipboardMonitor?

    init(store: ClipStore, pasteEngine: PasteEngine, preferences: PreferencesStore) {
        self.store = store
        self.pasteEngine = pasteEngine
        self.preferences = preferences
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.delegate = self
        panel.title = "Pastie"

        searchField = NSSearchField(frame: NSRect(x: 8, y: 320, width: 404, height: 24))
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = self

        tableView = NSTableView(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.width = 400
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.target = self
        tableView.doubleAction = #selector(pasteSelection)
        tableView.menu = buildContextMenu()

        scrollView = NSScrollView(frame: NSRect(x: 8, y: 8, width: 404, height: 304))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true

        panel.contentView?.addSubview(searchField)
        panel.contentView?.addSubview(scrollView)
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        refresh()
        var frame = panel.frame
        frame.size.height = Self.panelHeight(forRows: preferences.popupRowCount)
        panel.setFrame(frame, display: false)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        removeKeyMonitor()
    }

    /// Enter/Esc need to work no matter which control has focus — doCommandBy: on the search
    /// field's delegate only fires while focus is IN the search field, but clicking a row (the
    /// only way to ⌘/⇧-click multi-select) moves first responder to the table view. A local
    /// event monitor catches Return/Escape regardless of first responder, without disturbing
    /// the existing doCommandBy: arrow-key/Return/Escape forwarding used while typing.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 36: // Return
                self.pasteSelection()
                return nil
            case 53: // Escape
                self.hide()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func refresh() {
        allClips = (try? store.fetchAll()) ?? []
        applyFilter()
    }

    private func applyFilter() {
        filteredClips = ClipSearch.filter(allClips, query: searchField.stringValue)
        tableView.reloadData()
        if !filteredClips.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    private func moveSelection(by delta: Int) {
        guard !filteredClips.isEmpty else { return }
        let current = tableView.selectedRow
        let next = current < 0 ? 0 : max(0, min(filteredClips.count - 1, current + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func pasteSelection() {
        let indexes = tableView.selectedRowIndexes
        guard !indexes.isEmpty else { return }
        let selection = indexes.map { filteredClips[$0] }

        // Hide Pastie and hand focus back to whatever app the user was in BEFORE simulating
        // ⌘V — otherwise the keystroke goes to the still-key Pastie panel instead of the
        // target app. Give the target app's focus a moment to settle before pasting.
        hide()
        previousApp?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let pasted = self.pasteEngine.paste(selection, beforeEachWrite: { [weak self] in
                self?.clipboardMonitor?.ignoreNextChange()
            })
            if !pasted {
                self.showAccessibilityFallbackAlert()
            }
        }
    }

    private func showAccessibilityFallbackAlert() {
        let alert = NSAlert()
        alert.messageText = "Copied to Clipboard"
        alert.informativeText = "Pastie needs Accessibility permission to paste automatically. The content is on your clipboard — press ⌘V to paste manually, or grant permission in System Settings → Privacy & Security → Accessibility."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open System Settings")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    func togglePin(at row: Int) {
        guard row >= 0, row < filteredClips.count, let id = filteredClips[row].id else { return }
        try? store.setPinned(!filteredClips[row].pinned, id: id)
        refresh()
    }

    func deleteRow(at row: Int) {
        guard row >= 0, row < filteredClips.count, let id = filteredClips[row].id else { return }
        try? store.delete(id: id)
        refresh()
    }

    // Right-click context menu — the only way to reach togglePin/deleteRow from the UI.
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Pin", action: #selector(togglePinFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Delete", action: #selector(deleteFromMenu), keyEquivalent: "").target = self
        return menu
    }

    @objc private func togglePinFromMenu() {
        togglePin(at: tableView.clickedRow)
    }

    @objc private func deleteFromMenu() {
        deleteRow(at: tableView.clickedRow)
    }

    // NSWindowDelegate
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

extension PopupWindowController: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            pasteSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }
}

extension PopupWindowController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = tableView.clickedRow
        let validRow = row >= 0 && row < filteredClips.count
        let pinned = validRow && filteredClips[row].pinned
        for item in menu.items {
            item.isEnabled = validRow
            if item.action == #selector(togglePinFromMenu) {
                item.title = pinned ? "Unpin" : "Pin"
            }
        }
    }
}

extension PopupWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredClips.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let clip = filteredClips[row]
        let cell = NSTextField(labelWithString: displayText(for: clip))
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    private func displayText(for clip: Clip) -> String {
        let pinPrefix = clip.pinned ? "📌 " : ""
        switch clip.type {
        case .text: return pinPrefix + (clip.textContent ?? "")
        case .file: return pinPrefix + "📄 " + (clip.filePath ?? "")
        case .image: return pinPrefix + "🖼 Image (\((clip.imageData?.count ?? 0) / 1024) KB)"
        }
    }
}
```

- [ ] **Step 4: Fix the `AppDelegate.swift` call site**

In `Sources/Pastie/AppDelegate.swift`, find this line (inside `applicationDidFinishLaunching`):

```swift
popupController = PopupWindowController(store: clipStore, pasteEngine: PasteEngine())
```

Replace it with:

```swift
popupController = PopupWindowController(store: clipStore, pasteEngine: PasteEngine(), preferences: preferences)
```

- [ ] **Step 5: Run tests and build to verify everything passes**

Run: `swift test --filter PopupWindowControllerTests` — Expected: PASS
Run: `swift build` — Expected: builds clean (confirms the `AppDelegate.swift` call site compiles)

- [ ] **Step 6: Commit**

```bash
git add Sources/Pastie/UI/PopupWindowController.swift Sources/Pastie/AppDelegate.swift Tests/PastieTests/PopupWindowControllerTests.swift
git commit -m "feat: make popup panel height configurable via popupRowCount"
```

---

### Task 7: MenuBarController — icons, shortcuts, live hotkey display

**Files:**
- Modify: `Sources/Pastie/UI/MenuBarController.swift`
- Modify: `Sources/Pastie/AppDelegate.swift`

**Interfaces:**
- Consumes: `PreferencesStore.hotkeyKeyCode/hotkeyModifiers` (existing), `HotkeyFormatter.displayString` (existing)
- Produces: `init(popupController:clipStore:preferences:onOpenPreferences:)` (adds `preferences: PreferencesStore` param — breaks the one existing call site in `AppDelegate.swift`, fixed in this same task)

No automated test — `NSMenu`/`NSStatusItem` construction is UI, same reasoning as the v1 plan's `MenuBarController` task (manual verification only).

- [ ] **Step 1: Rewrite `MenuBarController.swift`**

Replace the file with:

```swift
// Sources/Pastie/UI/MenuBarController.swift
import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popupController: PopupWindowController
    private let clipStore: ClipStore
    private let preferences: PreferencesStore
    private let onOpenPreferences: () -> Void
    private let openPastieItem = NSMenuItem()

    init(popupController: PopupWindowController, clipStore: ClipStore, preferences: PreferencesStore, onOpenPreferences: @escaping () -> Void) {
        self.popupController = popupController
        self.clipStore = clipStore
        self.preferences = preferences
        self.onOpenPreferences = onOpenPreferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pastie")
        }

        openPastieItem.title = "Open Pastie"
        openPastieItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        openPastieItem.action = #selector(openPopup)
        openPastieItem.target = self

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        preferencesItem.target = self

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        clearItem.target = self

        let quitItem = NSMenuItem(title: "Quit Pastie", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(openPastieItem)
        menu.addItem(.separator())
        menu.addItem(preferencesItem)
        menu.addItem(clearItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func openPopup() {
        popupController.show()
    }

    @objc private func openPreferences() {
        onOpenPreferences()
    }

    @objc private func clearHistory() {
        try? clipStore.clearAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension MenuBarController: NSMenuDelegate {
    // Refreshes the "Open Pastie" title with the live hotkey binding each time the
    // menu opens, so a remap in Settings shows up without rebuilding the whole menu.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let hotkey = HotkeyFormatter.displayString(keyCode: preferences.hotkeyKeyCode, modifiers: preferences.hotkeyModifiers)
        openPastieItem.title = "Open Pastie    \(hotkey)"
    }
}
```

- [ ] **Step 2: Fix the `AppDelegate.swift` call site**

In `Sources/Pastie/AppDelegate.swift`, find this block (inside `applicationDidFinishLaunching`):

```swift
menuBarController = MenuBarController(
    popupController: popupController,
    clipStore: clipStore,
    onOpenPreferences: { [weak self] in self?.openPreferences() }
)
```

Replace it with:

```swift
menuBarController = MenuBarController(
    popupController: popupController,
    clipStore: clipStore,
    preferences: preferences,
    onOpenPreferences: { [weak self] in self?.openPreferences() }
)
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 4: Manual test**

Wired fully in Task 9's smoke test: confirm the status-bar icon shows, the dropdown lists "Open Pastie ⌥⌘V" / Preferences… (with ⌘,) / Clear History / Quit Pastie, each with the icons from the table in the spec, and that "Open Pastie"'s hotkey text updates after a remap in the Hotkey tab.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pastie/UI/MenuBarController.swift Sources/Pastie/AppDelegate.swift
git commit -m "feat: add icons, shortcuts, and live hotkey display to menu bar"
```

---

### Task 8: Settings tabs — General / Hotkey / Capture / Appearance

**Files:**
- Create: `Sources/Pastie/UI/SettingsTabs/GeneralTab.swift`
- Create: `Sources/Pastie/UI/SettingsTabs/HotkeyTab.swift`
- Create: `Sources/Pastie/UI/SettingsTabs/CaptureTab.swift`
- Create: `Sources/Pastie/UI/SettingsTabs/AppearanceTab.swift`
- Modify: `Sources/Pastie/UI/PreferencesView.swift`

**Interfaces:**
- Consumes: `PreferencesViewModel` (Task 5), `HotkeyRecorderView` (Task 4)
- Produces: `struct GeneralTab/HotkeyTab/CaptureTab/AppearanceTab: View { @ObservedObject var viewModel: PreferencesViewModel }`; `PreferencesView`'s `init(viewModel:)` signature is unchanged

No automated test — SwiftUI view bodies, same reasoning as the v1 plan's `PreferencesView` task (build + manual verification only).

- [ ] **Step 1: Write `GeneralTab.swift`**

```swift
// Sources/Pastie/UI/SettingsTabs/GeneralTab.swift
import SwiftUI

struct GeneralTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Stepper("Retention: \(viewModel.retentionCount) items", value: $viewModel.retentionCount, in: 50...5000, step: 50)
            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
            Section("Excluded Apps") {
                List {
                    ForEach(viewModel.excludedBundleIDs, id: \.self) { id in
                        HStack {
                            Text(id)
                            Spacer()
                            Button("Remove") {
                                guard let index = viewModel.excludedBundleIDs.firstIndex(of: id) else { return }
                                viewModel.removeExcluded(at: IndexSet(integer: index))
                            }
                        }
                    }
                    .onDelete(perform: viewModel.removeExcluded)
                }
                HStack {
                    TextField("Bundle ID (e.g. com.1password.1password)", text: $viewModel.newBundleID)
                    Button("Add") { viewModel.addExcluded() }
                }
            }
        }
        .padding()
    }
}
```

- [ ] **Step 2: Write `HotkeyTab.swift`**

```swift
// Sources/Pastie/UI/SettingsTabs/HotkeyTab.swift
import SwiftUI

struct HotkeyTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Global Hotkey") {
                HotkeyRecorderView(displayText: viewModel.hotkeyDisplay) { keyCode, modifiers in
                    viewModel.updateHotkey(keyCode: keyCode, modifiers: modifiers)
                }
                .frame(height: 28)
                Text("Click the field above and press a key combo. Must include at least one modifier key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 3: Write `CaptureTab.swift`**

```swift
// Sources/Pastie/UI/SettingsTabs/CaptureTab.swift
import SwiftUI

struct CaptureTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Capture text", isOn: $viewModel.captureText)
                Toggle("Capture images", isOn: $viewModel.captureImages)
                Toggle("Capture files", isOn: $viewModel.captureFiles)
            }
            Section("Image Size") {
                Picker("Max image size to keep", selection: $viewModel.maxImageSizeMB) {
                    Text("1 MB").tag(1)
                    Text("5 MB").tag(5)
                    Text("10 MB").tag(10)
                    Text("25 MB").tag(25)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 4: Write `AppearanceTab.swift`**

```swift
// Sources/Pastie/UI/SettingsTabs/AppearanceTab.swift
import SwiftUI

struct AppearanceTab: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Stepper("Rows shown in popup: \(viewModel.popupRowCount)", value: $viewModel.popupRowCount, in: 3...20)
        }
        .padding()
    }
}
```

- [ ] **Step 5: Rewrite `PreferencesView.swift` as the tab shell**

Replace the file with:

```swift
// Sources/Pastie/UI/PreferencesView.swift
import SwiftUI

// Each tab is a standalone file under SettingsTabs/ taking the shared viewModel.
// Adding a future tab (e.g. "Groups", "Actions") means: one new file + one new
// case here — never gate anything elsewhere on "there are 4 tabs".
struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
            HotkeyTab(viewModel: viewModel)
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
            CaptureTab(viewModel: viewModel)
                .tabItem { Label("Capture", systemImage: "tray.and.arrow.down") }
            AppearanceTab(viewModel: viewModel)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 480, height: 360)
    }
}
```

- [ ] **Step 6: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 7: Manual test**

Wired fully in Task 9's smoke test: open Preferences, confirm 4 tabs (General/Hotkey/Capture/Appearance) each render their controls, and every control's edits persist across closing and reopening the window.

- [ ] **Step 8: Commit**

```bash
git add Sources/Pastie/UI/SettingsTabs Sources/Pastie/UI/PreferencesView.swift
git commit -m "feat: split Preferences into General/Hotkey/Capture/Appearance tabs"
```

---

### Task 9: Wire it up — AppDelegate + end-to-end verification

**Files:**
- Modify: `Sources/Pastie/AppDelegate.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–8
- Produces: nothing new — this is the final assembly point

- [ ] **Step 1: Wire `onHotkeyChanged` into `openPreferences()`**

Replace `Sources/Pastie/AppDelegate.swift` with:

```swift
// Sources/Pastie/AppDelegate.swift
import AppKit
import GRDB
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipStore: ClipStore!
    private var preferences: PreferencesStore!
    private var monitor: ClipboardMonitor!
    private var hotkeyManager: HotkeyManager!
    private var menuBarController: MenuBarController!
    private var popupController: PopupWindowController!
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences = PreferencesStore()

        let dbQueue: DatabaseQueue
        do {
            dbQueue = try DatabaseQueue(path: Self.databasePath())
            clipStore = try ClipStore(dbQueue: dbQueue, retentionCountProvider: { [weak preferences] in
                preferences?.retentionCount ?? 500
            })
        } catch {
            NSLog("Pastie: fatal storage init error: \(error)")
            NSApp.terminate(nil)
            return
        }

        popupController = PopupWindowController(store: clipStore, pasteEngine: PasteEngine(), preferences: preferences)

        menuBarController = MenuBarController(
            popupController: popupController,
            clipStore: clipStore,
            preferences: preferences,
            onOpenPreferences: { [weak self] in self?.openPreferences() }
        )

        monitor = ClipboardMonitor(store: clipStore, preferences: preferences)
        monitor.start()
        popupController.clipboardMonitor = monitor

        hotkeyManager = HotkeyManager(preferences: preferences) { [weak self] in
            self?.popupController.toggle()
        }
        hotkeyManager.registerFromPreferences()

        requestAccessibilityIfNeeded()
    }

    private func openPreferences() {
        if preferencesWindow == nil {
            let viewModel = PreferencesViewModel(store: preferences, onHotkeyChanged: { [weak self] in
                self?.hotkeyManager.unregister()
                self?.hotkeyManager.registerFromPreferences()
            })
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

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func databasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Pastie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pastie.sqlite").path
    }
}
```

- [ ] **Step 2: Run the full test suite**

Run: `swift test`
Expected: PASS, all tests (existing 29 + new from Tasks 1, 2, 3, 5, 6 — 29 + 6 + 5 + 4 + 2 + 2 = 48).

- [ ] **Step 3: Build and run the full manual smoke test**

Run: `swift build && .build/debug/Pastie &`

1. Confirm the menu-bar icon appears; open its dropdown — "Open Pastie ⌥⌘V" (with clipboard icon), separator, "Preferences…" (⌘, shortcut, gear icon), "Clear History" (trash icon), separator, "Quit Pastie" (⌘Q).
2. Open Preferences via ⌘, or the menu — confirm 4 tabs: General, Hotkey, Capture, Appearance.
3. **Hotkey tab:** click the recorder field, press ⌃⇧S — confirm it now shows "⌃⇧S". Press the OLD hotkey (⌥⌘V) somewhere — confirm the popup does NOT open. Press ⌃⇧S — confirm the popup DOES open.
4. Close Preferences, reopen it, reopen the status-bar dropdown — confirm "Open Pastie" now shows "⌃⇧S".
5. **Capture tab:** disable "Capture images". Copy a screenshot (⌃⇧⌘4 then click, or copy any image). Confirm it does NOT appear in the popup. Re-enable "Capture images", copy another image, confirm it DOES appear.
6. **Appearance tab:** set "Rows shown in popup" to 4. Open the popup (⌃⇧S) — confirm the panel is visibly shorter than before (list still scrolls if there are more clips than fit).
7. Quit and relaunch Pastie. Confirm the hotkey remap, capture toggles, and row count all persisted (re-check the Hotkey/Capture/Appearance tabs match what was set).

- [ ] **Step 4: Commit**

```bash
git add Sources/Pastie/AppDelegate.swift
git commit -m "feat: wire hotkey re-registration into Settings"
```

---

## Spec Coverage Check

| Spec section | Task |
|---|---|
| Menu bar icons/shortcuts, live hotkey display | Task 7 |
| Settings — General tab | Task 8 (content unchanged from Task 5/1 in v1 plan, just relocated) |
| Settings — Hotkey tab (remap UI) | Tasks 3, 4, 5, 8 |
| Settings — Capture tab (type toggles, image size) | Tasks 1, 2, 5, 8 |
| Settings — Appearance tab (popup row count) | Tasks 1, 5, 6, 8 |
| No custom theme picker (explicitly skipped) | N/A — no task, by design |
| Data flow / no migration needed | Task 1 (new keys default when absent, no schema change) |
| Testing approach (pure functions unit-tested, UI manual) | All tasks |
