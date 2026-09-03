# Pastie — Menu Bar & Settings Redesign

Status: approved (chat), pending write-up review
Scope: `MenuBarController`, `PreferencesView` + supporting store/view-model/capture code.
Out of scope: `PopupWindowController` (clip search/list panel) — untouched.

## Why

The menu bar is 4 unstyled text items. Preferences is a single flat `Form`
with three fields (retention, launch-at-login, excluded apps) and is missing
the hotkey-remap UI the v1 spec (`2026-09-01-ditto-mac-design.md`) already
called for — `HotkeyFormatter` exists but nothing calls it. This redesign
closes that gap and adds capture-type and popup-appearance controls while
keeping the surface small (4 settings tabs, no new persistence layer).

## Menu bar

Replace the plain `NSMenu` items with icon + shortcut versions:

| Item | Icon (SF Symbol) | Shortcut shown |
|---|---|---|
| Open Pastie | `doc.on.clipboard` | current hotkey, e.g. "⌥⌘V" |
| — separator — | | |
| Preferences… | `gearshape` | ⌘, |
| Clear History | `trash` | — |
| — separator — | | |
| Quit Pastie | — | ⌘Q (unchanged) |

- Status item icon stays `doc.on.clipboard` (unchanged).
- "Open Pastie"'s shortcut is **display-only**, appended to the title string
  (`"Open Pastie    ⌥⌘V"`), not a real `NSMenuItem.keyEquivalent` — a global
  hotkey isn't an app-local key equivalent. Formatted via the existing
  `HotkeyFormatter.displayString(keyCode:modifiers:)`, read from
  `PreferencesStore` each time the menu is rebuilt so it reflects remaps.
- "Preferences…" gets `keyEquivalent: ","` (real app-local shortcut, standard
  macOS convention) in addition to the icon.

## Settings window

`TabView`-based, native macOS Settings-style, ~480×360. Four tabs, one file
each under `Sources/Pastie/UI/SettingsTabs/` instead of growing
`PreferencesView` into one large file.

### Tab 1 — General
Unchanged content, moved from the old single-page Form:
- Retention stepper (`viewModel.retentionCount`, 50–5000 step 50)
- Launch at login toggle
- Excluded Apps section (list + add/remove, existing behavior)

### Tab 2 — Hotkey
New `HotkeyRecorderView` (`NSViewRepresentable`):
- Displays current binding via `HotkeyFormatter.displayString`.
- Click → becomes first responder → next `keyDown` is captured: extract
  `keyCode` + `modifierFlags`, write to
  `PreferencesStore.hotkeyKeyCode`/`hotkeyModifiers`.
- Reject modifier-less combos (typing a bare letter shouldn't rebind).
- On save: `HotkeyManager.unregister()` then `registerFromPreferences()` —
  both methods already exist, no new API needed, just call them again from
  the recorder's completion.
- If `HotKey`'s underlying registration silently fails (key already bound at
  OS level), show inline "Key already in use" text rather than doing nothing.

### Tab 3 — Capture
New toggles, default **on**:
- "Capture text"
- "Capture images"
- "Capture files"

Backed by new `PreferencesStore` keys (`captureText`/`captureImages`/`captureFiles`,
`Bool`, default `true`). `CaptureFilter.shouldCapture` gets a type-gate check
using the clip type inferred from `CaptureContext.pasteboardTypes` (file URL
present → file; image present → image; else text — same precedence
`ClipboardMonitor.makeClip` already uses) gated on these toggles.

"Max image size to keep" — segmented control: 1 / 5 / 10 / 25 MB. Replaces
the hardcoded `ClipboardMonitor.imageDownsampleThresholdBytes` static
constant with a new `PreferencesStore.maxImageSizeMB` (`Int`, default 5,
matching today's hardcoded 5 MB). `ClipboardMonitor` reads
`preferences.maxImageSizeMB * 1024 * 1024` at downsample-check time instead
of the static constant. Downsample behavior (400px-wide thumbnail) unchanged.

### Tab 4 — Appearance
- "Rows shown in popup" — new `PreferencesStore.popupRowCount` (`Int`,
  default ~8). Cosmetic only: affects `PopupWindowController`'s panel height,
  does not change how many clips are retained/stored.
- **No custom accent color / theme picker.** SwiftUI inherits the system
  accent color automatically; a Pastie-specific theme is real effort (color
  picker UI, persistence, applying it consistently to pin icons/selected
  rows) for low payoff on a 4-tab prefs window. Skipped by design, not by
  omission.

## Components touched

New files:
- `Sources/Pastie/UI/HotkeyRecorderView.swift`
- `Sources/Pastie/UI/SettingsTabs/GeneralTab.swift`
- `Sources/Pastie/UI/SettingsTabs/HotkeyTab.swift`
- `Sources/Pastie/UI/SettingsTabs/CaptureTab.swift`
- `Sources/Pastie/UI/SettingsTabs/AppearanceTab.swift`

Changed files:
- `Sources/Pastie/UI/PreferencesView.swift` — becomes the `TabView` shell
  hosting the four tab files above.
- `Sources/Pastie/UI/PreferencesViewModel.swift` — add `@Published` wrappers
  for `captureText`/`captureImages`/`captureFiles`/`maxImageSizeMB`/
  `popupRowCount`, same `didSet → store.x = x` pattern as `retentionCount`.
- `Sources/Pastie/Preferences/PreferencesStore.swift` — add the five new
  `UserDefaults`-backed keys above. New keys simply default when absent — no
  migration needed.
- `Sources/Pastie/Capture/CaptureFilter.swift` — `shouldCapture` gains the
  type-gate check.
- `Sources/Pastie/Capture/ClipboardMonitor.swift` — downsample threshold
  becomes instance-level, reads from `preferences.maxImageSizeMB` instead of
  the static `imageDownsampleThresholdBytes` constant.
- `Sources/Pastie/UI/MenuBarController.swift` — icons + shortcut-title
  changes from the Menu bar section above.
- `Sources/Pastie/UI/PopupWindowController.swift` — panel height respects
  `preferences.popupRowCount` on `show()`/`refresh()`. (Only touch point
  outside the menu/settings surfaces; the popup's own search/list/paste
  behavior is unchanged.)

## Data flow

Unchanged pattern: `PreferencesViewModel` writes flow straight through to
`PreferencesStore` (`UserDefaults`), same as `retentionCount` today. Side
effects on write:
- Hotkey change → `HotkeyManager.unregister()` + `registerFromPreferences()`.
- Capture toggle / image size change → no explicit push; `CaptureFilter` and
  `ClipboardMonitor` read `PreferencesStore` live on each tick, so changes
  take effect on the next clipboard poll with no extra plumbing.
- Popup row count → read by `PopupWindowController` on next `show()`.

No new persistence layer, no database schema change, no migration.

## Testing

- `CaptureFilter`'s new type-gate is a pure function — unit tested the same
  way as the existing checks in `Tests/PastieTests/CaptureFilterTests.swift`.
- `PreferencesStore`/`PreferencesViewModel` new keys — unit tested following
  the existing pattern in `PreferencesStoreTests.swift` /
  `PreferencesViewModelTests.swift`.
- `HotkeyRecorderView`, menu bar icon/shortcut rendering, and popup row-count
  effect on panel height are UI — manual verification only, consistent with
  how `HotkeyManager`/paste-simulation are already excluded from automated
  tests per the v1 spec (no clean automated-test path for macOS global
  hotkeys/`CGEvent`).
