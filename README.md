# Spotty

A small replacement for Spotlight that does two things: opens apps and does sums.
No file search, no AI, no web results.

## Build and run

Needs macOS 14 or later and Swift 6 (Xcode or just the Command Line Tools).

```sh
scripts/bundle.sh       # release build -> build/Spotty.app, ad-hoc signed
open build/Spotty.app
```

Spotty has no Dock icon. It lives in the menu bar (a magnifying glass) with Open Spotty, Settings… and Quit.
To keep it, drag `build/Spotty.app` to `/Applications` and turn on "Open at login" in Settings.

For development, `swift run Spotty` runs the debug build without a bundle, and `swift test` runs the core tests.
Debug builds can also render the panel to a PNG without screen-recording permission:

```sh
SPOTTY_SNAPSHOT='saf|/tmp/saf.png;1299*1.13|/tmp/sum.png' SPOTTY_APPEARANCE=light .build/debug/Spotty
```

## Make ⌘Space open Spotty

Spotty registers ⌘Space at launch. Spotlight's shortcut normally holds it, so turn that off once:
System Settings › Keyboard › Keyboard Shortcuts… › Spotlight, then untick "Show Spotlight search".
If the shortcut can't be registered, the menu and Settings say "⌘Space is taken by another app".

## Keys

| Key | Does |
| --- | --- |
| ↩ | Open the selected app, or copy the result of a sum |
| ⌘↩ | Reveal the selected app in Finder |
| ↑ ↓ | Move the selection |
| ⇥ | Accept the grey completion |
| esc | Clear the field; press again to close |
| ⌘1–⌘5 | Open a recent app while the field is empty |
| ⌘C | Copy the result of a sum |

## Files

`~/Library/Application Support/Spotty/` holds `usage.json` (what Spotty has learned, with a `.bak`
of the previous good copy) and, if you create it, `aliases.json`: extra names by bundle ID, such as
`{"com.microsoft.VSCode": ["vs", "editor"]}`. Settings › "Reset learned ranking" clears the first.

## Layout

- `Sources/LauncherCore`: the UI-free core (matching, ranking, what it learns, the calculator, the app
  scanner). Foundation only; `swift test` covers it.
- `Sources/Spotty`: the app. AppKit for the panel, hotkey, FSEvents and launching; SwiftUI for the views.
- `scripts/bundle.sh`: builds `build/Spotty.app`.
- `docs/implementation.md`: how every part works (indexing, re-indexing, matching, ranking, calculator, panel).
- `docs/design.md`: the "B · Quiet" design: sizes, type, colours, keys, motion and copy.
- `docs/plan.md`: the build plan.
