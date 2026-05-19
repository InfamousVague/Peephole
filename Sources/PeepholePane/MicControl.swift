import CoreAudio
import Foundation

/// Software microphone kill: hard-mutes the current default input device via
/// CoreAudio. Entitlement-free. Not an unbypassable hardware switch — an app
/// could fight it — so `PeepholeStore` re-asserts it on a short timer, which
/// wins the tug-of-war in practice.
enum MicControl {
    /// nonisolated(unsafe): only ever touched from the @MainActor store.
    nonisolated(unsafe) private static var priorVolume: [AudioDeviceID: Float32] = [:]

    @discardableResult
    static func apply(muted: Bool) -> Bool {
        guard let dev = defaultInputDevice() else { return false }
        let byMute = setMute(dev, muted)
        let byVol = setVolumeFallback(dev, muted: muted)
        return byMute || byVol
    }

    static func isMuted() -> Bool {
        guard let dev = defaultInputDevice() else { return false }
        if let m = readMute(dev) { return m }
        if let v = readVolume(dev) { return v <= 0.0001 }
        return false
    }

    // MARK: - device

    private static func defaultInputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultInputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let st = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev
        )
        return (st == noErr && dev != 0) ? dev : nil
    }

    /// Master (0) plus a generous span of per-channel elements; missing ones
    /// just report not-settable and are skipped.
    private static func elements() -> [AudioObjectPropertyElement] {
        [AudioObjectPropertyElement(kAudioObjectPropertyElementMain)]
            + (1...8).map { AudioObjectPropertyElement($0) }
    }

    // MARK: - mute

    private static func muteAddr(_ el: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyMute),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeInput),
            mElement: el
        )
    }

    private static func setMute(_ dev: AudioDeviceID, _ on: Bool) -> Bool {
        var applied = false
        for el in elements() {
            var a = muteAddr(el)
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(dev, &a, &settable) == noErr,
                  settable.boolValue else { continue }
            var v: UInt32 = on ? 1 : 0
            if AudioObjectSetPropertyData(
                dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v
            ) == noErr { applied = true }
        }
        return applied
    }

    private static func readMute(_ dev: AudioDeviceID) -> Bool? {
        for el in elements() {
            var a = muteAddr(el)
            guard AudioObjectHasProperty(dev, &a) else { continue }
            var v: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr {
                return v != 0
            }
        }
        return nil
    }

    // MARK: - volume fallback (devices without a settable mute)

    private static func volAddr(_ el: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeInput),
            mElement: el
        )
    }

    private static func setVolumeFallback(_ dev: AudioDeviceID, muted: Bool) -> Bool {
        var any = false
        for el in elements() {
            var a = volAddr(el)
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(dev, &a, &settable) == noErr,
                  settable.boolValue else { continue }
            if muted {
                var cur: Float32 = 0
                var sz = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectGetPropertyData(dev, &a, 0, nil, &sz, &cur) == noErr,
                   cur > 0.0001, priorVolume[dev] == nil {
                    priorVolume[dev] = cur
                }
                var z: Float32 = 0
                if AudioObjectSetPropertyData(
                    dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &z
                ) == noErr { any = true }
            } else {
                var restore: Float32 = priorVolume[dev] ?? 1.0
                if AudioObjectSetPropertyData(
                    dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &restore
                ) == noErr { any = true }
            }
        }
        if !muted { priorVolume[dev] = nil }
        return any
    }

    private static func readVolume(_ dev: AudioDeviceID) -> Float32? {
        for el in elements() {
            var a = volAddr(el)
            guard AudioObjectHasProperty(dev, &a) else { continue }
            var v: Float32 = 0
            var sz = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(dev, &a, 0, nil, &sz, &v) == noErr {
                return v
            }
        }
        return nil
    }
}
