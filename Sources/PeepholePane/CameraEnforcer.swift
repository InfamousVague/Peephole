import AppKit
import Foundation

/// Reactive camera kill: while armed, terminate any app that is actively
/// using the camera. Entitlement-free (we only signal same-user apps via
/// `NSRunningApplication`). Honest ceilings:
///   • Reactive — an app may grab a frame or two before we react.
///   • Identification is by Peephole's heuristic app attribution; if the
///     grabber can't be named we deliberately kill nothing (no blind nuking).
///   • Two-stage: polite `terminate()` first, `forceTerminate()` if it
///     ignores us and is still on the camera next tick.
enum CameraEnforcer {
    /// bundleIDs/names we've already asked to quit (escalate next tick).
    nonisolated(unsafe) private static var warned: Set<String> = []

    /// `targets` = heuristic app names of currently-active camera sessions
    /// (Peephole's `event.app`, daemons already filtered out, nil dropped).
    static func enforce(targets: Set<String>) {
        guard !targets.isEmpty else { return }
        let wanted = targets.map { $0.lowercased() }
        let me = ProcessInfo.processInfo.processIdentifier
        let myBundle = Bundle.main.bundleIdentifier

        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != me,
                  app.bundleIdentifier != myBundle else { continue }
            guard let id = appIdentity(app) else { continue }
            guard wanted.contains(where: { id.names.contains($0) }) else { continue }

            if warned.contains(id.key) {
                app.forceTerminate()              // escalate — it ignored us
            } else {
                warned.insert(id.key)
                if !app.terminate() { app.forceTerminate() }
            }
        }
    }

    /// Camera was re-allowed → forget escalation state.
    static func reset() { warned.removeAll() }

    private static func appIdentity(_ app: NSRunningApplication)
        -> (key: String, names: Set<String>)? {
        var names = Set<String>()
        if let n = app.localizedName?.lowercased() { names.insert(n) }
        if let b = app.bundleIdentifier?.lowercased() {
            names.insert(b)
            if let last = b.split(separator: ".").last { names.insert(String(last)) }
        }
        if let exe = app.executableURL?.deletingPathExtension().lastPathComponent.lowercased() {
            names.insert(exe)
        }
        if names.isEmpty { return nil }
        let key = app.bundleIdentifier ?? String(app.processIdentifier)
        return (key, names)
    }
}
