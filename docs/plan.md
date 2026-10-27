# Build plan

Spotty is a launcher with no Dock icon: ⌘Space opens a floating panel that opens apps and does sums.
`docs/implementation.md` explains how each part works and has sketches of the app code;
`docs/design.md` has the exact sizes, colours, keys, motion and copy. Where the two differ,
`docs/design.md` wins on anything visual and on wording.

## Ground rules

- Local git repo only, no remote yet. Commit after each milestone below (more often is fine),
  with a clear message. Keep `swift build` and `swift test` passing at every commit.
- No third-party dependencies. `LauncherCore` stays Foundation-only so its tests run anywhere.
- Don't change the ranking constants in `Ranker`/`Usage` without updating the golden tests.
- Don't change system settings (for example Spotlight's shortcut); document them in the README instead.
- Don't install tools globally without asking.

## Shape of the project

SwiftPM only, so it builds with Xcode or with just the Command Line Tools:

- `Sources/LauncherCore` (exists, tested): matching, ranking, learning, calculator.
- `Sources/Spotty` (new, executable): the app. AppKit + SwiftUI.
- `Tests/LauncherCoreTests` (exists).
- `scripts/bundle.sh` (new): `swift build -c release`, then assemble `build/Spotty.app`
  (`Contents/MacOS/Spotty`, `Contents/Info.plist`), then ad-hoc sign it with `codesign --force --sign -`.
  Info.plist: `CFBundleIdentifier` `com.hus.spotty`, `CFBundleName` Spotty, `LSUIElement` true,
  `LSMinimumSystemVersion` 14.0, version 0.1.
- Colours in code, not an asset catalogue (asset catalogues need Xcode's `actool`): one `Quiet`
  palette built with `NSColor(name:dynamicProvider:)` from the hex values in `docs/design.md`.

The app scanner only needs Foundation (`FileManager`, `PropertyListSerialization`,
`FileManager.displayName(atPath:)` for localized names), so put it in a Foundation-only target
that tests can reach, either inside `LauncherCore` or a small target of its own.

## Milestones

1. **Core on macOS.** Commit what is here. Run `swift test` on macOS; the 26 tests were verified on
   Linux, and Decimal rounding and string folding come from a different Foundation build on the Mac.
   Fix real differences in code, not by loosening tests. Commit.
2. **App shell.** `@main` App with a `Settings` scene and a `MenuBarExtra` (Settings…, Quit).
   `AppDelegate` creates a non-activating, borderless `NSPanel` subclass that can become key, hosts
   SwiftUI through `NSHostingView`, joins all Spaces and full-screen apps, and hides when it loses key.
   Carbon `RegisterEventHotKey` for ⌘Space toggles it. Show on the screen with the pointer, never
   call `NSApp.activate` for the panel. Commit.
3. **Finding apps.** Folder scan of the roots in `docs/implementation.md` (one level deep, skip
   hidden and `LSBackgroundOnly`, read `Info.plist` with `PropertyListSerialization`, de-duplicate by
   resolved path and bundle ID, modification-date cache). FSEvents watcher on the user folders
   (1 s latency, restart on wake), rescan off the main thread and swap in one assignment. Lazy icon
   cache. Tests with fake `.app` bundles in a temporary folder. Commit.
4. **The panel.** `SearchModel` and `SearchView` per `docs/design.md`: Recent on open (⌘1–⌘5),
   up to six rows with bold matched letters, Tab ghost completion, the why line, "Nothing matches",
   the math tray (expression line, 42 pt result, "So far" / "Keep typing", Copy button).
   Local key monitor for ↑ ↓ Tab Esc ⌘C ⌘1–⌘5 that steps aside while `hasMarkedText()` is true.
   Top-anchored resizing, open/close motion. Commit.
5. **Acting and remembering.** Launch with `NSWorkspace.openApplication`, ⌘↩ reveals in Finder,
   copy sums as plain ASCII, record launches in `UsageStore`, note app activations for Recent
   (`NSWorkspace.didActivateApplicationNotification`), save `usage.json` under
   `~/Library/Application Support/Spotty/` (debounced, atomic, keep a `.bak`). The capsule: a small
   borderless panel that ignores the mouse, holds 1.4 s and fades. Settings: "Open at login"
   (`SMAppService.mainApp`, off by default) and "Reset learned ranking". Commit.
6. **Package and smoke test.** `scripts/bundle.sh`, build `build/Spotty.app`, launch it once to check it
   starts and the panel opens, then quit it. README: how to build, run, and turn off Spotlight's
   ⌘Space (System Settings > Keyboard > Keyboard Shortcuts > Spotlight). Commit.

## Checks a person still has to do

Panel over a full-screen app, on a second display, with Stage Manager, with a Japanese input
method, after sleep; golden queries against the real `/Applications`.
