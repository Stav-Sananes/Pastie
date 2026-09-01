# Pastie for Mac — Design Spec

Date: 2026-09-01

## Purpose

Port the core experience of Ditto (open-source Windows clipboard manager) to
native macOS: background clipboard history, hotkey-summoned searchable popup,
menu-bar access. Multi-machine LAN sync (Ditto's flagship feature) is
explicitly deferred to a later phase — this spec covers single-machine only.

## Scope (v1)

In:
- Clipboard history capture: text, images, files (file paths/URLs)
- Global hotkey popup: search, arrow-key nav, enter to paste
- Menu-bar icon: quick access to popup + Preferences + Clear History + Quit
- Paste-as-list: multi-select history items, paste sequentially in one action
- Pin/favorite items: exempt from retention eviction
- Exclude-app list: skip capture when frontmost app is in a user-configured
  block list; also respect the `org.nspasteboard.ConcealedType` /
  `org.nspasteboard.TransientType` pasteboard conventions (apps like password
  managers already mark sensitive copies this way)
- Retention: cap history by item count (user-configurable, default e.g. 500),
  pinned items exempt from the cap
- Launch at login

Out (future phases):
- Multi-machine sync
- Plugins/extensibility
- iCloud/cross-device features beyond LAN sync

## Architecture

Menu-bar-only app (`LSUIElement = true`, no Dock icon). No public
clipboard-change notification API exists on macOS, so a background poller
watches `NSPasteboard.general.changeCount` (0.5s interval — the standard
approach used by existing mac clipboard managers). New clips persist to a
local SQLite database. A global hotkey (default ⌥⌘V, remappable) opens a
borderless `NSPanel` popup for search/select/paste. A menu-bar `NSStatusItem`
gives the same popup plus Preferences/Clear History/Quit.

## Components

1. **ClipboardMonitor** — polls `changeCount`; on change, reads content
   (string / image / file URL); skips if the pasteboard carries
   `ConcealedType`/`TransientType`, or if the frontmost app (via
   `NSWorkspace`) is in the excluded-app list; dedups against the
   most-recently-stored item; writes to ClipStore.
2. **ClipStore** — SQLite (GRDB). Table:
   `clips(id, type, textContent, imageData BLOB, filePath, sourceApp, timestamp, pinned, sortOrder)`.
   On insert, evicts oldest unpinned rows beyond the configured count cap.
3. **HotkeyManager** — registers/remaps the global hotkey, toggles the popup.
4. **PopupWindowController** — borderless `NSPanel`; search field; list with
   arrow-key navigation; multi-select for paste-as-list; per-item pin/delete;
   Esc dismisses.
5. **PasteEngine** — writes selection to the system pasteboard and simulates
   ⌘V via `CGEvent`. For multi-select, pastes items sequentially
   (paste-as-list). Requires macOS Accessibility permission; app prompts and
   deep-links to System Settings on first use.
6. **MenuBarController** — `NSStatusItem`; click opens popup; menu holds
   Preferences, Clear History, Quit.
7. **Preferences** — hotkey remap, retention count, excluded-app list,
   launch-at-login (`SMAppService`).

## Data Flow

Pasteboard change → Monitor filters (concealed type / excluded app) →
ClipStore writes + evicts beyond cap → Popup queries ClipStore live as user
types/selects → on paste action, PasteEngine writes selection back to
pasteboard and simulates the paste keystroke(s) into the frontmost app.

## Error Handling

- DB write failure: log, skip that clip, non-fatal.
- Oversized images (~>5MB): store a downsampled thumbnail for list display;
  full-resolution data kept or dropped per a size setting.
- Missing Accessibility permission: paste falls back to "copied to clipboard
  — paste manually" toast instead of failing silently.

## Testing

- Unit tests: ClipStore (insert, count-cap eviction, pin exemption, dedup
  logic), Monitor's capture filters (concealed type, excluded app).
- Manual/integration: global hotkey registration, simulated paste via
  `CGEvent` — no clean automated-test path exists for macOS global hotkeys or
  synthetic keystrokes into arbitrary frontmost apps.

## Tech Stack

Swift + SwiftUI/AppKit. Native `NSStatusItem` menu-bar app, `CGEvent` for
paste simulation, GRDB (or raw SQLite) for storage.
