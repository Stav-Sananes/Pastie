# Pastie

A clipboard manager for macOS. It lives in the menu bar, remembers what you copy, and gives it
back to you with a keystroke.

macOS keeps exactly one thing on the clipboard. Copy something else and the previous thing is
gone. Pastie keeps a history of what you copied, lets you search it, and pastes any entry
straight into whatever app you are using.

**Status:** working, version 0.3.0. Built for macOS 13 and later. 93 tests pass.

---

## Contents

- [For users](#for-users) — install it, use it, and what it can see
- [For developers](#for-developers) — build, test, and the shape of the code
- [Design notes](#design-notes) — why the odd parts are the way they are
- [Project status](#project-status) — what exists and what is only planned

---

# For users

## What it does

- **Remembers your clipboard.** Text, images, and files you copy are kept in a local history,
  newest first. The default is the last 500 items.
- **Summons with a hotkey.** Press **⌥⌘V** (remappable) and a small search panel appears over
  whatever you were doing.
- **Searches as you type.** Filter the history, pick an entry with the arrow keys, press ↵, and
  it is pasted into the app you were in.
- **Pastes several at once.** Select multiple entries and they are pasted one after another.
- **Keeps what matters.** A **Saved** clip is never dropped when the history fills up, and sits
  in its own section above the stream.
- **Quick-paste slots.** Bind a Saved clip to a slot 1–9 and paste it from anywhere with
  **⌥⌘1**–**⌥⌘9**, without the panel ever appearing.
- **Keeps formatting, or drops it.** Styled text is stored with its RTF alongside the plain
  string: **↵** pastes it styled, **⇧↵** pastes it plain.
- **Reshapes on the way out.** **⌘T** applies a transform — pretty-print JSON, change case,
  base64, URL encode/decode, trim — to what you are about to paste. **⌘E** edits it first.
  Neither touches the stored clip.
- **Skips what it shouldn't see.** Password managers mark their copies as concealed, and Pastie
  honours that. You can also name apps it should ignore entirely.
- **Stays out of the way.** No Dock icon, no window, just a menu-bar icon.

## Installing

Download `Pastie.app.zip` from the
[latest release](https://github.com/Stav-Sananes/Pastie/releases/latest), unzip it, and move
`Pastie.app` to your Applications folder. Then read the next section, because macOS will not let
you open it on the first try.

Prefer to build it yourself? See [For developers](#for-developers) — it takes about a minute and
skips the Gatekeeper problem entirely, because a locally built app is never quarantined.

### The Gatekeeper warning, and why you will get one

Pastie is not signed with an Apple Developer ID, because that requires a paid Apple Developer
Program membership this project does not have yet. macOS will therefore refuse to open a
downloaded copy the first time, saying it "is damaged" or "cannot be opened because Apple cannot
check it for malicious software".

On macOS 15 and later — including macOS 26 — the old trick of Control-clicking the app and
choosing Open **no longer works**. The current path is:

1. Double-click `Pastie.app`. macOS refuses and shows the warning. Dismiss it.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the Security section. There is a line saying `"Pastie" was blocked`, with an
   **Open Anyway** button. Click it.
4. Confirm, and authenticate.

You should be suspicious of this. An unsigned app that asks for permission to watch your
clipboard and press keys for you is exactly the shape of something malicious, and the warning
exists for good reasons. If you did not build this yourself from source you have no way to know
what is inside it. Building it yourself takes about a minute and avoids the whole problem — a
locally built app is not quarantined.

### Accessibility permission

Pastie pastes by pressing ⌘V for you in whatever app is frontmost. macOS only allows an app to
send keystrokes to other apps if you grant it Accessibility permission, so on first use it will
ask.

**System Settings → Privacy & Security → Accessibility →** turn Pastie on.

Without it, everything still works except the final keystroke: Pastie puts the entry on your
clipboard and tells you to press ⌘V yourself.

## Using it

| Action | How |
| --- | --- |
| Open the panel | **⌥⌘V**, or click the menu-bar icon → Open Pastie |
| Search | Just type — the panel opens with the search field focused |
| Move through results | **↑** / **↓** |
| Paste the selected entry | **↵** |
| Select several | **⌘-click** or **⇧-click** rows, then **↵** to paste them in order |
| Paste without formatting | **⇧↵** |
| Paste the Nth visible row | **⌘1**–**⌘9** |
| Transform before pasting | **⌘T**, then pick one |
| Edit before pasting | **⌘E** |
| Save, assign a slot, or delete an entry | **Right-click** the row |
| Paste a slot from any app | **⌥⌘1**–**⌥⌘9** (modifier configurable) |
| Close the panel | **Esc**, or click away |
| Preferences | Menu-bar icon → Preferences…, or **⌘,** |
| Empty the history | Menu-bar icon → Clear History |

Preferences has four tabs:

- **General** — how many entries to keep, launch at login
- **Hotkey** — record a new hotkey by pressing the combination you want; choose the modifier the
  quick-paste slots use (⌥⌘, ⌃⌘, or ⇧⌘)
- **Capture** — turn text, image, or file capture on and off individually; set the maximum image
  size; keep or drop formatting, with a size cap for it; manage the list of apps to ignore
- **Appearance** — how many rows the panel shows

## What Pastie can see, and where it puts it

A clipboard manager sees everything you copy. That includes passwords, tokens, and private
messages. Being precise about this matters more than reassuring you about it.

**What it reads.** Every change to the system clipboard, checked twice a second, along with the
bundle identifier of the app that was frontmost when the change happened.

**What it does not read.** A copy that the source app marks as concealed or transient — the
convention password managers are expected to use (`org.nspasteboard.ConcealedType`,
`org.nspasteboard.TransientType`) — is skipped and never stored. Whether any particular app
actually sets that marker is up to that app, so treat it as a courtesy that usually holds rather
than a guarantee: if a password manager you rely on does not set it, add it to the excluded list
instead. Apps on that list are skipped entirely while they are frontmost. Capture types you turn off are never stored.

**Where it goes.** A SQLite database at:

```
~/Library/Application Support/Pastie/pastie.sqlite
```

**It is not encrypted.** Anything running as your user account can read that file, and so can
anyone with your unlocked Mac. This is a deliberate trade for a local single-user tool, but you
should know it. If you copy a password from an app that does not mark it concealed, that
password is sitting in that file in plain text until it is evicted.

**What leaves your machine: nothing.** There is no server, no account, no analytics, no hosted
crash reporting, no network code of any kind in the app. If Pastie crashes it writes a report to
`~/Library/Application Support/Pastie/Logs` — a local file you can read, reachable from the
menu-bar icon → Reveal Logs in Finder. Nothing is transmitted. There is nothing to opt out of.

**Clear History keeps your Saved clips.** It deletes unsaved history only. To remove everything,
unsave first, or delete the database file above and restart.

---

# For developers

## Requirements

- macOS 13 or later
- Swift 5.9 or later (Xcode 15+, or the standalone toolchain)

## Build and run

```bash
git clone https://github.com/Stav-Sananes/Pastie.git
cd Pastie
swift build              # compile
swift test               # run the suite — 93 tests
./Scripts/build-app.sh   # produce build/Pastie.app
open build/Pastie.app
```

`Scripts/build-app.sh` does a release build, then assembles a bundle by hand: the binary into
`Contents/MacOS/`, `Resources/Info.plist` into `Contents/`. There is no Xcode project — this is
a SwiftPM package, and the bundle is three copy commands rather than a build system.

The app is a menu-bar agent (`LSUIElement` is true in `Info.plist`), so it has no Dock icon and
no main window. Quit it from the menu-bar icon.

## Dependencies

Two, both small:

- [GRDB](https://github.com/groue/GRDB.swift) — SQLite with a typed record layer and a migration
  system
- [HotKey](https://github.com/soffes/HotKey) — a thin wrapper over Carbon's
  `RegisterEventHotKey`, which is still the only way to get a global hotkey on macOS

## Layout

```
Sources/Pastie/
  main.swift                  Entry point: installs AppDelegate, runs the app
  AppDelegate.swift           Wires every component together at launch
  Models/Clip.swift           The Clip record and its content-equality rule
  Storage/ClipStore.swift     SQLite: migrations, insert, eviction, saved, slots, delete
  Capture/
    ClipboardMonitor.swift    The polling loop; turns a pasteboard into a Clip
    CaptureFilter.swift       Pure rules for what may be captured
  Search/ClipSearch.swift     Pure substring filtering over clips
  Transforms/
    Transform.swift           The protocol and the registry that is also the menu order
    BuiltInTransforms.swift   Nine pure String -> String? functions
  Paste/PasteEngine.swift     Writes the pasteboard and synthesises ⌘V
  Hotkey/
    HotkeyManager.swift       Registers the global hotkey from preferences
    HotkeyCapture.swift       Turns a key event into a storable binding
    HotkeyFormatter.swift     Renders a binding as "⌥⌘V"
    SlotHotkeyManager.swift   One global hotkey per *bound* quick-paste slot
  UI/
    MenuBarController.swift   The status item and its menu
    PopupWindowController.swift  The search panel: two sections, keys, paste
    ClipEditSheet.swift       Edit-before-paste; never writes to the store
    PreferencesView.swift     Tab container
    SettingsTabs/             General, Hotkey, Capture, Appearance
    HotkeyRecorderView.swift  "Press a key combination" control
    PreferencesViewModel.swift
  Preferences/PreferencesStore.swift   UserDefaults-backed settings
  Onboarding/OnboardingController.swift  First-run Accessibility explanation
  Support/
    LaunchAtLogin.swift       SMAppService wrapper
    AccessibilityStatus.swift Test seam over AXIsProcessTrusted()
    CrashLogFormatter.swift   Pure formatting of a crash record
    CrashLogger.swift         Handler installation and local log writing
```

The split is deliberate: **anything with a rule in it is a pure function in its own type**, and
the AppKit classes are wiring. `CaptureFilter` decides what may be captured but touches no
pasteboard; `ClipSearch` filters an array; `HotkeyFormatter` formats; a `Transform` is a pure
function. That is why 93 tests can cover the logic of an app whose interface is untestable — the
untestable parts contain no decisions.

## Testing

```bash
swift test                                  # everything
swift test --filter ClipStoreTests          # one suite
```

What is covered: storage (insert, eviction, the Saved exemption, the slot API and its
move-on-conflict rule, migration 2 against a hand-built v1 database), capture rules (concealed and
transient types, excluded apps, per-type toggles, RTF capture and its size cap), what the paste
engine writes to a pasteboard for rich and plain, every transform including its failure cases,
search, hotkey capture and formatting, preferences defaults and round-trips, the onboarding
decision, crash-log formatting and writing, and panel sizing.

What is not, and cannot easily be: global hotkey registration, synthetic ⌘V into another app,
and the panel's event handling. These need a real user session and a real frontmost app. They
are verified by hand. If you change them, launch the app and check them yourself — a green
suite says nothing about whether paste still works.

---

# Design notes

The parts of this codebase that look wrong usually are not. Each of these cost a bug to learn.

### Why it polls the clipboard twice a second

macOS has no notification for "the clipboard changed". None. The only mechanism is
`NSPasteboard.general.changeCount`, an integer that increments on every write, which you have to
read and compare yourself. So `ClipboardMonitor` runs a timer at 0.5s and compares. Every macOS
clipboard manager does this; there is no better way, only different intervals.

### Why pasting has a 0.1-second delay in it

To paste, Pastie has to be frontmost (its panel has keyboard focus), then *not* be frontmost (so
the synthetic ⌘V lands in your app, not in the panel). `pasteSelection` therefore hides the
panel, calls `activate` on the app that was frontmost when the panel opened, and waits 0.1s
before posting the keystroke. Without the wait, the keystroke arrives before the window server
has finished moving focus, and it goes to the wrong place — or nowhere.

The `previousApp` reference exists for the same reason: by the time you press ↵, the frontmost
app *is* Pastie, so it has to have remembered who was in front before it appeared.

### Why the monitor has an `ignoringSelfWrite` flag

Pasting means writing to the clipboard. Writing to the clipboard bumps `changeCount`. The
monitor sees a change and captures it — so every paste would append a duplicate of itself to the
history, forever. `PasteEngine` takes a `beforeEachWrite` closure, the popup uses it to call
`monitor.ignoreNextChange()`, and the next observed change is swallowed instead of stored.

### Why there is a local key monitor as well as a delegate

The search field's `doCommandBy:` delegate handles ↑/↓/↵/Esc — but only while the search field
has focus. Clicking a row to multi-select moves first responder to the table view, and then ↵ did
nothing. A local `NSEvent` monitor catches Return and Escape regardless of who has focus. Both
mechanisms are live at once; that is intentional, not leftover.

### Why the app is not sandboxed, and never will be

The App Sandbox forbids posting synthetic events into other processes and restricts reading which
app is frontmost. Those are the two things Pastie is made of. A sandboxed build could not paste
and could not honour the excluded-app list, which is why distribution is direct download rather
than the Mac App Store.

### Why images get downsampled

A screenshot on a Retina display can be tens of megabytes, and 500 of those is a database nobody
wants. Above the configured limit (5MB by default), the image is redrawn at 400 points wide and
only the thumbnail is stored. The original is not kept — pasting such an entry gives you the
thumbnail. This is a real limitation, not a display optimisation.

### Why deduplication only checks the most recent entry

`ClipboardMonitor` compares a new clip against `store.mostRecent()`, not the whole history. Copy
A, then B, then A again, and you get two A entries. This is on purpose: copying the same thing
twice at different times is two events, and collapsing them would reorder your history in ways
that surprise you. Copying the same thing twice *in a row* is usually a double ⌘C, which is why
that one case is filtered.

### Why retention counts unsaved entries only

The cap is a limit on the stream, not on the library. Saved clips are excluded from both the count
and the eviction query, so saving 600 items with a cap of 500 keeps all 600 — the cap governs what
flows through, and saving is how you take something out of the flow.

### Why only bound slots register a global hotkey

Nine permanently registered hotkeys would take ⌥⌘1–9 away from every other app on the machine
whether or not Pastie had anything to paste with them. `SlotHotkeyManager` registers a hotkey only
for a slot that actually holds a clip, and re-registers the set whenever a binding changes. The
clip behind a slot is re-read when the key is pressed, not captured when it is registered, so a
slot whose clip was deleted beeps instead of pasting something stale.

### Why a transform never writes to the store

History is a record of what you actually copied. A transform and an edit-before-paste produce
something you never copied, so they are pasted and discarded — the stored clip is untouched. That
is also why a transform returning nil (malformed JSON, invalid base64) shows a message and pastes
nothing, rather than pasting an approximation.

### Why only RTF is kept as the rich payload

An `NSPasteboard` item can carry a dozen representations of the same text. Archiving all of them
would store an unbounded blob per clip, and HTML from a browser drags along styles and sometimes
remote references. RTF is one self-contained format that every macOS text control understands, so
it is the only one kept — under a size cap, and never at the cost of the plain string, which
remains the clip's identity for search and deduplication.

---

# Project status

| Track | State | Where |
| --- | --- | --- |
| Core clipboard manager (v1) | **Shipped** — capture, popup, search, paste, pin, retention, excluded apps, launch at login | This repo |
| Menu bar + Settings redesign | **Shipped** — four Settings tabs, hotkey remapping UI, per-type capture toggles, row count | This repo |
| Saved clips, quick-paste slots, transforms, release polish (v3) | **Shipped** — Saved section, slots 1–9 with global hotkeys, rich/plain paste, nine transforms, edit-before-paste, Accessibility onboarding, local crash logs | This repo |
| Multi-machine LAN sync (v2) | **Planned** — spec and task-level plan written, not started | Local docs, not in this repo |

The design documents for the planned track are deliberately kept out of version control, so
what you can clone is the software that exists rather than a description of software that does
not. Nothing above is a promise; it is a record of what has been thought through.

## Distribution

Releases are ad-hoc signed zips attached to GitHub releases. `Scripts/build-app.sh` signs the
bundle with `codesign --sign -` and packages it with `ditto`, which preserves the signature that
a plain `zip` would corrupt.

Ad-hoc is not Developer ID: it satisfies Apple Silicon's requirement that every binary carry a
signature, but it tells Gatekeeper nothing about who built it, so a downloaded copy is blocked
until the user allows it explicitly. Removing that friction needs a paid Apple Developer Program
membership for Developer ID signing and notarisation — which would also unlock in-app updates.
The build script takes a `SIGN_IDENTITY` environment variable so that switch is one variable and
a notarisation step, not a rewrite.

## Licence

None yet — all rights reserved by default. If you want to reuse any of this, ask.
