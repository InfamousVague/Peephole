import Foundation
import Observation
import AppKit
import PeepholeShared

/// One camera/mic usage session in the history list.
struct UsageEvent: Identifiable, Hashable {
    let id: String            // stable: device + token + start epoch
    let device: UsageDevice
    var app: String?          // nil → "unknown" (displayed honestly)
    let start: Date
    var end: Date?

    var isActive: Bool { end == nil }
}

@MainActor
@Observable
final class PeepholeStore {
    /// Reverse-chronological history (newest first).
    var events: [UsageEvent] = []
    var cameraActive = false
    var micActive = false
    /// Connected video devices + their quick stats (refreshed each poll).
    var cameras: [CameraInfo] = []
    /// Connected input-capable audio devices + their quick stats.
    var microphones: [MicInfo] = []
    var lastError: String?

    /// Kill-switch state.
    /// `micDisabled` — real, sticky software mute (CoreAudio), re-enforced.
    /// `cameraDisabled` — armed reactive kill: any app that opens the camera
    /// while on is terminated. `cameraUnknownGrabber` — camera is on but
    /// Peephole couldn't attribute an app, so it deliberately killed nothing.
    var micDisabled = false
    var cameraDisabled = false
    var cameraUnknownGrabber = false

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var enforceTimer: Timer?

    /// Event id the user asked to jump to (set from a notification click).
    var focusedKey: String?

    /// Called whenever overall active state flips, so the delegate can swap
    /// the menu-bar icon.
    @ObservationIgnored var onActiveChange: ((Bool) -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var firstScanDone = false
    @ObservationIgnored private var seenTransitionKeys: Set<String> = []
    /// token → index into `events` for the currently-open session on that token.
    @ObservationIgnored private var openByToken: [String: String] = [:]
    @ObservationIgnored private var lastActiveOverall = false

    private let pollInterval: TimeInterval = 4
    // Query a little more than the interval so nothing slips between polls.
    private var pollWindow: TimeInterval { pollInterval + 6 }

    func start() {
        // Camera kill is intentionally session-only — a destructive,
        // kill-other-processes feature must never silently re-arm at
        // launch. Mic mute is non-destructive, so it stays persisted.
        // Also purge legacy persisted keys from older builds.
        defaults.removeObject(forKey: "cameraKillArmed")
        defaults.removeObject(forKey: "cameraDisabledIntent")
        micDisabled = defaults.bool(forKey: "micDisabled")
        cameraDisabled = false
        if micDisabled { MicControl.apply(muted: true) }
        updateEnforce()
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let window = pollWindow
        Task.detached {
            let transitions = UsageMonitor.poll(window: window)
            let cameraOn = CameraState.isCameraRunningSomewhere()
            let micOn = MicState.isMicRunningSomewhere()
            let cameraList = CameraDevices.all()
            let micList = MicDevices.all()
            await MainActor.run {
                self.apply(transitions, cameraRunning: cameraOn, microphoneRunning: micOn)
                self.cameras = cameraList
                self.microphones = micList
            }
        }
    }

    // MARK: - Kill switches

    func setMicDisabled(_ on: Bool) {
        micDisabled = on
        defaults.set(on, forKey: "micDisabled")
        MicControl.apply(muted: on)
        updateEnforce()
    }

    /// Instant — no profile, nothing to approve. While armed, any app that
    /// opens the camera is terminated (reactive; honest ceilings in the UI).
    func setCameraDisabled(_ on: Bool) {
        cameraDisabled = on     // intentionally not persisted; see start()
        if on {
            enforceTick()               // act now, don't wait for the 1 s timer
        } else {
            CameraEnforcer.reset()
            cameraUnknownGrabber = false
        }
        updateEnforce()
    }

    private func updateEnforce() {
        if micDisabled || cameraDisabled {
            if enforceTimer == nil {
                enforceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.enforceTick() }
                }
            }
        } else {
            enforceTimer?.invalidate()
            enforceTimer = nil
        }
    }

    /// One enforcement pass: re-mute the mic, and reactively kill any app
    /// currently using the camera.
    private func enforceTick() {
        if micDisabled { MicControl.apply(muted: true) }

        guard cameraDisabled else { cameraUnknownGrabber = false; return }
        guard CameraState.isCameraRunningSomewhere() else {
            cameraUnknownGrabber = false
            return
        }
        let activeCam = events.filter { $0.device == .camera && $0.isActive }
        let targets = Set(activeCam.compactMap { $0.app })
        if targets.isEmpty {
            // Camera is on but the grabber can't be named → kill nothing.
            cameraUnknownGrabber = !activeCam.isEmpty
        } else {
            cameraUnknownGrabber = false
            CameraEnforcer.enforce(targets: targets)
        }
    }

    func clearHistory() {
        // Keep sessions that are still active; drop the closed history.
        events.removeAll { !$0.isActive }
        focusedKey = nil
    }

    private func apply(
        _ transitions: [UsageTransition],
        cameraRunning camOn: Bool,
        microphoneRunning micOn: Bool
    ) {
        for t in transitions {
            // De-dupe: each raw log transition is keyed by token+state+second.
            let secs = Int(t.date.timeIntervalSince1970)
            let dedupeKey = "\(t.token):\(t.active):\(secs)"
            guard !seenTransitionKeys.contains(dedupeKey) else { continue }
            seenTransitionKeys.insert(dedupeKey)

            if t.active {
                open(t)
            } else {
                close(t)
            }
        }
        // Bound the de-dupe set so it can't grow unbounded.
        if seenTransitionKeys.count > 4000 {
            seenTransitionKeys.removeAll(keepingCapacity: true)
        }

        reconcile(.camera, running: camOn, authToken: "cam:authoritative")
        reconcile(.microphone, running: micOn, authToken: "mic:authoritative")
        recomputeActive(cameraOn: camOn, micOn: micOn)
        firstScanDone = true
    }

    /// The unified log is best-effort and can leave a session "open" (its Stop
    /// fell outside the poll window, or was never logged). CMIO (camera) and
    /// CoreAudio (mic) `IsRunningSomewhere` are ground truth — the same signal
    /// the camera LED / mic indicator reflect — so use them to close stale
    /// sessions and, conversely, surface a session the log missed.
    private func reconcile(_ device: UsageDevice, running: Bool, authToken: String) {
        let hasActive = events.contains { $0.device == device && $0.end == nil }
        if running {
            if !hasActive {
                // Genuinely on but the log didn't attribute it → honest
                // "Unknown app" session so the UI/history stay truthful.
                let id = "\(device.rawValue):authoritative:\(Int(Date().timeIntervalSince1970))"
                events.insert(
                    UsageEvent(id: id, device: device, app: nil, start: Date(), end: nil),
                    at: 0
                )
                openByToken[authToken] = id
                if firstScanDone {
                    Notifier.postActive(key: id, device: device, app: nil)
                }
            }
        } else {
            // Not running (indicator off) → close any stale sessions.
            let now = Date()
            for i in events.indices where events[i].device == device && events[i].end == nil {
                events[i].end = now
            }
            openByToken = openByToken.filter { _, id in
                guard let e = events.first(where: { $0.id == id }) else { return false }
                return e.device != device
            }
        }
    }

    private func open(_ t: UsageTransition) {
        // Already tracking an open session on this token → just refine the app.
        if let existingID = openByToken[t.token],
           let idx = events.firstIndex(where: { $0.id == existingID }) {
            if events[idx].app == nil, let a = t.app { events[idx].app = a }
            return
        }
        let id = "\(t.device.rawValue):\(t.token):\(Int(t.date.timeIntervalSince1970))"
        let event = UsageEvent(id: id, device: t.device, app: t.app, start: t.date, end: nil)
        events.insert(event, at: 0)
        openByToken[t.token] = id

        if firstScanDone {
            Notifier.postActive(key: id, device: t.device, app: t.app)
        }
    }

    private func close(_ t: UsageTransition) {
        guard let openID = openByToken[t.token],
              let idx = events.firstIndex(where: { $0.id == openID }) else {
            return
        }
        if events[idx].end == nil {
            events[idx].end = t.date
        }
        openByToken[t.token] = nil
    }

    private func recomputeActive(cameraOn camOn: Bool, micOn: Bool) {
        // Both authoritative: camera = CMIO/LED-backed, mic = CoreAudio.
        cameraActive = camOn
        micActive = micOn
        let overall = cameraActive || micActive
        if overall != lastActiveOverall {
            lastActiveOverall = overall
            onActiveChange?(overall)
        }
        publishSharedSnapshot()
    }

    /// Publish a compact camera/mic-activity snapshot to the App
    /// Group container so the widget's TimelineProvider can render
    /// the latest state. SharedPeepholeStore debounces WidgetKit
    /// reloads internally.
    private func publishSharedSnapshot() {
        let activeCamNames = cameras
            .filter { $0.isRunning }
            .map { $0.name }
        let activeMicNames = microphones
            .filter { $0.isRunning }
            .map { $0.name }
        let snap = SharedPeephole(
            cameraActive: cameraActive,
            micActive: micActive,
            activeCameras: activeCamNames,
            activeMics: activeMicNames,
            sampledAt: Date()
        )
        SharedPeepholeStore.write(snap)
    }
}
