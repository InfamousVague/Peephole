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
            await MainActor.run { self.apply(transitions) }
        }
    }

    func clearHistory() {
        // Keep sessions that are still active; drop the closed history.
        events.removeAll { !$0.isActive }
        focusedKey = nil
    }

    private func apply(_ transitions: [UsageTransition]) {
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

        recomputeActive()
        firstScanDone = true
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

    private func recomputeActive() {
        cameraActive = events.contains { $0.device == .camera && $0.isActive }
        micActive = events.contains { $0.device == .microphone && $0.isActive }
        let overall = cameraActive || micActive
        if overall != lastActiveOverall {
            lastActiveOverall = overall
            onActiveChange?(overall)
        }
    }
}
