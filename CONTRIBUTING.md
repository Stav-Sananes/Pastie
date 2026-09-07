# Contributing to Pastie

Thanks for looking. Pastie is a small Swift app with a clear shape, and it is deliberately kept
that way; the notes below are what makes a contribution easy to take.

## Build and test

You need Xcode's command-line tools on macOS 13 or later.

```bash
git clone https://github.com/Stav-Sananes/Pastie.git
cd Pastie
swift test            # 158 tests, under a second
Scripts/build-app.sh  # produces build/Pastie.app, a zip and a DMG
open build/Pastie.app
```

The [README](README.md#for-developers) covers the layout of the code and what the tests do and
do not cover. Read [CONTEXT.md](CONTEXT.md) before you write anything: it defines the words
(Clip, History, Saved, slot, Transform, Capture) and the words to avoid. A change that says
"pinned" or "snippet" will be asked to say "Saved".

## Reporting a bug

Open an issue with the bug template. The things that make a report answerable: the Pastie version
(Settings → About), the macOS version, what you copied from or pasted into, and the steps. If it
crashed, the menu-bar icon → Reveal Logs in Finder has the record.

Pasting problems are almost always Accessibility: after every update of an ad-hoc signed build,
switch Pastie off and on again in System Settings → Privacy & Security → Accessibility. Check that
before reporting that ↵ "does nothing".

## Suggesting a feature

Open an issue with the feature template. Say what you are trying to do, not only what control you
want; the best answer is sometimes a different feature. Things that are unlikely to be taken:
anything that sends clipboard contents off the machine, cloud sync, accounts, analytics.

## Pull requests

- **Small and single-purpose.** One change per pull request, one idea per commit.
- **Tests come with the change.** Anything with a rule in it is a pure function in its own type,
  and it has a test. `swift test` must be green. If the change is in the untestable parts (global
  hotkeys, synthetic ⌘V, the popup's event handling), say in the description how you verified it by
  hand.
- **Follow the shape that is there.** Rules in pure types, AppKit classes as wiring, a protocol
  seam wherever a system framework would otherwise reach into a test.
- **Commit messages say what and why**, in the imperative, like the existing history.
- **Match the vocabulary** in CONTEXT.md.

Opening an issue first for anything larger than a fix saves both of us the work of a pull request
that goes a different way than the project.

## Licence

By contributing you agree that your contribution is licensed under the
[GNU GPL v3.0](LICENSE), the same as the rest of Pastie.
