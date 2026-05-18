import Foundation
import Observation
import AppKit

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
    var lastError: String?

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
            await MainActor.run {
                self.apply(transitions, cameraRunning: cameraOn, microphoneRunning: micOn)
            }
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
    }
}
