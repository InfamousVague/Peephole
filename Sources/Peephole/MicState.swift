import CoreAudio
import Foundation

/// Authoritative, entitlement-free "is any microphone actually capturing"
/// check — the CoreAudio analogue of `CameraState`.
///
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` on input-capable devices is
/// what the macOS mic indicator approximates. Honest limit: a single device
/// that exposes *both* input and output (some USB headsets) reports "running"
/// during playback too, so that case can over-report — still far better than
/// the stale-log heuristic it replaces.
enum MicState {
    static func isMicRunningSomewhere() -> Bool {
        for device in inputDevices() {
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var addr = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceIsRunningSomewhere),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
            let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running)
            if status == noErr, running != 0 { return true }
        }
        return false
    }

    private static func allDevices() -> [AudioDeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    /// Devices that expose at least one input stream (i.e. can be a mic).
    private static func inputDevices() -> [AudioDeviceID] {
        allDevices().filter { device in
            var addr = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreams),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeInput),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr
            else { return false }
            return size > 0
        }
    }
}
