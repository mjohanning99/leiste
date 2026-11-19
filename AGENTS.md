# Leiste, for coding agents

Notes for an AI coding agent (or a person) working on Leiste. The
[README](README.md) says what Leiste is and how to use it; this file says how
it is built, how to check a change and what to keep in mind.

## What it is

A task bar for macOS: a bar along the bottom of each screen with a button for
every window on the current desktop, pinned apps that open a new window on
the desktop you're on, badges, a desktop switcher and minimising into the
bar. Swift, AppKit for the panels and SwiftUI for what is in them.

## Principles

- **No network, ever.** Leiste never connects anywhere and collects nothing.
  Don't add update checks, analytics or crash reporting.
- **No dependencies.** It builds with Apple's Command Line Tools alone
  (`xcode-select --install`). Keep it that way. That also means no SwiftUI
  `@State`, whose macro plug-in comes only with Xcode; use a small
  `ObservableObject` instead, as the views already do.
- **Light.** At rest Leiste uses well under 1 % of the processor. It listens
  to apps' accessibility notifications instead of asking them over and over.
  Don't add fast timers. Never block the main thread on another app:
  some apps take seconds to answer accessibility questions.
- **Plain comments.** Every file starts with what it does and why; comments
  explain the reasons, in plain English, for readers who aren't Swift experts.

## Building and running

```sh
tools/build.sh                 # build/Leiste.app, Apple silicon and Intel, macOS 14+
open build/Leiste.app
```

Leiste needs the Accessibility permission. macOS ties it to the app's
signature, which changes with every ad hoc build; to keep it across builds,
put the name of a code-signing certificate of your own in `.signing-identity`.

## Checking a change

You can check much of Leiste without looking at the screen:

- `build/Leiste.app/Contents/MacOS/Leiste --snapshot bar.png [--dark] [--opt name=value]`
  draws the bar with sample windows (names as in `options.txt`). The glass
  doesn't show in pictures and buttons look dimmed; that is the renderer.
- **A change that shouldn't alter the look:** run `tools/snapshots.sh /tmp/before`,
  make the change and build, run `tools/snapshots.sh /tmp/after`, then
  `python3 tools/compare.py /tmp/before /tmp/after`. It must say ALL IDENTICAL.
- `~/Library/Logs/Leiste.log` notes new windows, odd desktop switches and
  full-screen hiding. When something misbehaves, add a log line, reproduce it
  once and read the log rather than guessing.
- Run picture options with a time limit; a build without the option would
  start a normal bar and keep running.

## Things that are true about macOS (learnt the hard way)

- Accessibility lists only the windows of the current desktop; the window
  server (`CGWindowListCopyWindowInfo`) knows all of them and answers at once.
- A window is really shown only if it is ordered in on a desktop. Apps keep
  invisible helper windows and closed windows for later.
- Things inside a window announce title changes too; go up to the `AXWindow`.
- macOS announces a desktop switch only after its slide (about a second) and
  keeps its own shortcuts, such as Control-arrow, from apps.
- Apps can't move windows between desktops without System Integrity
  Protection turned off. Leiste doesn't ask for that.
- The undocumented calls Leiste needs are declared in
  `Sources/CGSPrivate/include/CGSPrivate.h`. A macOS update may break them.

## Where things are

| File | What it holds |
|---|---|
| `Sources/Leiste/main.swift` | Start and a bar panel per screen |
| `Sources/Leiste/BarModel.swift` | The model: what the bar knows and when it looks again (with a map of the files below) |
| `Sources/Leiste/WindowReader.swift` | Reading the windows of this desktop |
| `Sources/Leiste/Watch.swift` | Listening to apps' announcements |
| `Sources/Leiste/Clicks.swift` | What clicks, groups, keys and dragging do |
| `Sources/Leiste/PinnedApps.swift` | Pinned apps and new windows on this desktop |
| `Sources/Leiste/DesktopSwitch.swift`, `Desktops.swift` | Switching desktops; reading them |
| `Sources/Leiste/FullScreen.swift`, `FitAboveBar.swift` | Stepping aside for full screen; keeping windows above the bar |
| `Sources/Leiste/Displays.swift` | The screens |
| `Sources/Leiste/Tuck.swift`, `Ghost.swift`, `YellowButton.swift` | Minimising into Leiste |
| `Sources/Leiste/MoveWindow.swift` | Moving a window to another desktop |
| `Sources/Leiste/Signals.swift`, `Badges.swift`, `Sound.swift` | Badges, calls for attention, sound |
| `Sources/Leiste/BarView.swift` | The bar, its glass and layout |
| `Sources/Leiste/WindowButtons.swift`, `LauncherButton.swift`, `DesktopSwitcher.swift` | The buttons |
| `Sources/Leiste/Menus.swift`, `Dragging.swift`, `Motion.swift` | Right-click menus; dragging (with the lift), the swell and hover; the small movements |
| `Sources/Leiste/Prefs.swift`, `SettingsWindow.swift`, `Settings.swift` | Options, the Settings window, the settings files |
| `Sources/Leiste/Welcome.swift`, `Hotkeys.swift` | The welcome checklist; Control-Option-1 to 9 |
| `Sources/Leiste/Accessibility.swift`, `Log.swift` | Helpers for asking apps questions; the log |
| `Sources/Leiste/TestTools.swift` | The picture and probe options |
| `Resources/` | `Info.plist`, the icon and the translations |
| `tools/` | Build, package, icon and picture scripts |

## Translations

`Resources/<language>.lproj/Localizable.strings`. The key is the English text
exactly as written in the code; interpolated names become `%@` and numbers
`%lld`. A text built in code needs `String(localized:)` or
`LocalizedStringKey`, or it stays English. Use macOS's own words for its
features (in German: Schreibtisch, Kennzeichen, Bedienungshilfen).

## Before a pull request

- It builds with `tools/build.sh`, with no new warnings of your own.
- The picture series is identical, or the change to the look is intended and
  described.
- New visible text is in English and, if you can, in German too.
- `CHANGELOG.md` has a line under "Unreleased" for anything a user notices.
