# peephole (native)

Native macOS menu-bar sentinel for camera & microphone access. Shows which
apps are using the camera/mic, keeps a history, notifies on access, and can
**kill switch** them: a sticky software mic mute and a profile-based camera
disable. Swift + SwiftUI, `NSStatusItem` + `NSPopover`, no third-party
dependencies, **no special entitlements**.

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
- `Sources/Peephole/MicControl.swift` — CoreAudio hard-mute of the default
  input device (settable mute, input-volume fallback). Sticky: the store
  re-asserts it every second while disabled.
- `Sources/Peephole/CameraEnforcer.swift` — reactive camera kill: while
  armed, terminates (`NSRunningApplication.terminate` → `forceTerminate`) any
  app Peephole attributes to an active camera session. No profile.
- `Sources/Peephole/ContentView.swift` — the popover UI (status pills +
  kill-switch controls + history list + footer).

## Controls: honest limits

The kill switches are user-initiated and entitlement-free, with real ceilings:

- **Mic**: a genuine software mute, re-enforced on a 1 s timer so an app that
  unmutes loses the tug-of-war. It is *not* an unbypassable hardware switch.
- **Camera**: macOS gives apps **no** silent *preventive* camera-disable API
  (a config profile would work but needs per-toggle user approval). So the
  camera kill is **reactive**: armed instantly with no profile, and any app
  that opens the camera while armed is terminated. Ceilings: reactive (a frame
  or two may leak in the ~1 s before it reacts), disruptive (the grabbing app
  is quit), and identification is heuristic — if the grabber can't be named,
  Peephole kills nothing and the UI says so rather than nuking blindly.

## Detection: honest limits

Detection observes Apple's **undocumented** unified-log messages, which vary
by macOS version. It is best-effort:

- Responsible-app attribution is heuristic. The log frequently only names a
  system daemon (`coreaudiod`, the CMIO assistant); those are filtered out and
  the event is shown as "Unknown app" rather than fabricating a name.
- Output-audio noise is filtered by requiring an input/recording hint, so some
  short mic sessions could be missed or, rarely, mislabeled.
- Detection itself only observes and reports. Enforcement is separate,
  explicit, and user-initiated (the kill switches above) — never automatic.

## Running

```
swift build
swift run                 # menu-bar item appears; no Dock icon
bash scripts/make-app.sh  # assembles Peephole.app (LSUIElement), Developer ID signed
open Peephole.app         # run the bundled menu-bar agent
```
