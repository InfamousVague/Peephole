# peephole (native)

Native macOS menu-bar sentinel for camera & microphone access. Shows which
apps are using the camera/mic, keeps a history, and notifies on access.
Swift + SwiftUI, `NSStatusItem` + `NSPopover`, no third-party dependencies,
**no special entitlements**.

## Commit Convention
Angular commits required with scope. See @.claude/rules/commit-rules.md for details.

## Code Style
See @.claude/rules/code-style.md

## Architecture

- `Sources/Peephole/PeepholeApp.swift` — `@main` SwiftUI app: `NSStatusItem` +
  `NSPopover` + `.accessory` activation (no Dock icon). Swaps the menu-bar
  glyph between idle (`eye.trianglebadge.exclamationmark`) and active
  (`eye.fill`).
- `Sources/Peephole/Models.swift` — `UsageEvent` + `PeepholeStore`
  (`@Observable`, `@MainActor`): Timer poll, start↔stop pairing, new-event
  notifications behind a `firstScanDone` guard.
- `Sources/Peephole/UsageMonitor.swift` — entitlement-free detection: runs
  `/usr/bin/log show --style ndjson` with a camera/mic predicate and parses
  CoreMediaIO DAL stream Start/Stop + coreaudiod input IO Start/Stop.
- `Sources/Peephole/Notifier.swift` — `UserNotifications` wrapper.
- `Sources/Peephole/ContentView.swift` — the popover UI (status pills +
  history list + footer).

## Detection: honest limits

Detection observes Apple's **undocumented** unified-log messages, which vary
by macOS version. It is best-effort:

- Responsible-app attribution is heuristic. The log frequently only names a
  system daemon (`coreaudiod`, the CMIO assistant); those are filtered out and
  the event is shown as "Unknown app" rather than fabricating a name.
- Output-audio noise is filtered by requiring an input/recording hint, so some
  short mic sessions could be missed or, rarely, mislabeled.
- This is a transparency tool, not a security boundary — it only observes and
  reports; it never blocks or kills anything.

## Running

```
swift build
swift run                 # menu-bar item appears; no Dock icon
bash scripts/make-app.sh  # assembles Peephole.app (LSUIElement), Developer ID signed
open Peephole.app         # run the bundled menu-bar agent
```
