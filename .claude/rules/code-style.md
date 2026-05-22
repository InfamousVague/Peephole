# Code Style

- Follow the project's existing patterns and conventions
- Keep functions focused and small
- Prefer explicit over implicit
- Write self-documenting code — add comments only where logic isn't self-evident
- UI state lives in `PeepholeStore` (`@MainActor`, `@Observable`); views stay declarative.
- System calls live in the non-UI files: detection in `UsageMonitor`/`CameraState`/`MicState`; enforcement in `MicControl` (CoreAudio) and `CameraEnforcer` (`NSRunningApplication` terminate). Views and the store never call them directly except through these.
- Detection is best-effort and read-only. Enforcement (sticky mic mute, reactive camera-app termination) is real but strictly **user-initiated** via the kill switches — never automatic, and the UI must state honest ceilings (sticky-not-hardware for mic; reactive-and-disruptive for camera, and never kill an unidentified grabber).
