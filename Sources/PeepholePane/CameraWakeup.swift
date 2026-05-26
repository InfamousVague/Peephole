import AVFoundation
import Foundation

/// Best-effort camera "wakeup" at launch.
///
/// Runs a single `AVCaptureDevice.DiscoverySession.devices` query — the
/// documented Apple path for enumerating cameras — to refresh the system's
/// view of available capture devices. This is intentionally a *light touch*:
///   • It only enumerates (no opens, no streams, no format reads — the
///     pattern that caused real damage earlier).
///   • It's run once at launch, off the main actor, no timers, no retries.
///   • It's entitlement-free; device discovery doesn't require camera
///     permission (capture would).
///
/// Honest limit: if the system camera broker (`cameracaptured`) is in a
/// wedged state, this can't fix that — that daemon runs as a system uid
/// and can only be restarted with `sudo killall cameracaptured` or a
/// reboot. The wakeup is a nudge, not a recovery.
enum CameraWakeup {
    static func nudge() {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .external,
            .continuityCamera,
            .deskViewCamera,
        ]
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        _ = session.devices
    }
}
