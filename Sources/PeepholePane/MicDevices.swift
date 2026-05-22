import CoreAudio
import Foundation

/// One input-capable CoreAudio device — what we show as a "microphone".
struct MicInfo: Identifiable, Hashable {
    let id: UInt32              // AudioDeviceID
    let name: String
    let manufacturer: String?
    let transport: String       // "Built-in", "USB", "Bluetooth", etc.
    let isRunning: Bool         // matches MicState's authoritative signal
    let channels: Int           // input channel count, 0 if unknown
    let sampleRate: Double      // Hz; 0 if unknown

    var channelsLabel: String? {
        switch channels {
        case 0: return nil
        case 1: return "Mono"
        case 2: return "Stereo"
        default: return "\(channels)ch"
        }
    }
    var sampleRateLabel: String? {
        guard sampleRate > 0 else { return nil }
        let khz = sampleRate / 1000.0
        let fmt = khz == khz.rounded() ? "%.0f kHz" : "%.1f kHz"
        return String(format: fmt, khz)
    }
}

/// Entitlement-free per-microphone inspection via CoreAudio.
enum MicDevices {
    static func all() -> [MicInfo] { inputDeviceIDs().map(info(for:)) }

    // MARK: enumeration

    private static func allDeviceIDs() -> [AudioDeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let n = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: n)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    /// Devices with at least one input stream (mic-capable).
    private static func inputDeviceIDs() -> [AudioDeviceID] {
        allDeviceIDs().filter { dev in
            var addr = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreams),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeInput),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr
            else { return false }
            return size > 0
        }
    }

    // MARK: per device

    private static func info(for dev: AudioDeviceID) -> MicInfo {
        let name = cfString(dev, kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
            ?? "Microphone \(dev)"
        let manufacturer = cfString(
            dev, kAudioObjectPropertyManufacturer, scope: kAudioObjectPropertyScopeGlobal
        )
        let transport = transportLabel(
            uint32(dev, kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal)
        )
        let running = (uint32(
            dev, kAudioDevicePropertyDeviceIsRunningSomewhere,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? 0) != 0
        let channels = inputChannelCount(for: dev)
        let rate = nominalSampleRate(for: dev) ?? 0
        return MicInfo(
            id: dev, name: name, manufacturer: manufacturer,
            transport: transport, isRunning: running,
            channels: channels, sampleRate: rate
        )
    }

    private static func inputChannelCount(for dev: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreamConfiguration),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeInput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr,
              size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, raw) == noErr
        else { return 0 }
        let abl = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        return abl.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func nominalSampleRate(for dev: AudioDeviceID) -> Double? {
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyNominalSampleRate),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &rate) == noErr
        else { return nil }
        return rate > 0 ? Double(rate) : nil
    }

    // MARK: helpers

    private static func cfString(
        _ dev: AudioDeviceID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr,
              size > 0 else { return nil }
        var cf: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &cf) == noErr,
              let s = cf?.takeRetainedValue() else { return nil }
        return s as String
    }

    private static func uint32(
        _ dev: AudioDeviceID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr
        else { return nil }
        return v
    }

    /// FourCC audio transport → friendly label, fallback to raw 4-char.
    private static func transportLabel(_ code: UInt32?) -> String {
        guard let code, code != 0 else { return "Unknown" }
        switch code {
        case fourCC("bltn"): return "Built-in"
        case fourCC("usb "): return "USB"
        case fourCC("blue"): return "Bluetooth"
        case fourCC("blea"): return "Bluetooth LE"
        case fourCC("airp"): return "AirPlay"
        case fourCC("hdmi"): return "HDMI"
        case fourCC("dprt"): return "DisplayPort"
        case fourCC("thun"): return "Thunderbolt"
        case fourCC("aggr"): return "Aggregate"
        case fourCC("virt"): return "Virtual"
        case fourCC("1394"): return "FireWire"
        case fourCC("eavb"): return "AVB"
        case fourCC("pci "): return "PCI"
        case fourCC("ccwd"): return "Continuity (wired)"
        case fourCC("ccwl"): return "Continuity (wireless)"
        default:
            let bytes = [
                UInt8(truncatingIfNeeded: code >> 24),
                UInt8(truncatingIfNeeded: code >> 16),
                UInt8(truncatingIfNeeded: code >> 8),
                UInt8(truncatingIfNeeded: code),
            ]
            return String(bytes: bytes, encoding: .ascii)?
                .trimmingCharacters(in: .whitespaces) ?? "Unknown"
        }
    }

    private static func fourCC(_ s: String) -> UInt32 {
        precondition(s.utf8.count == 4, "FourCC must be 4 bytes")
        var v: UInt32 = 0
        for b in s.utf8 { v = (v << 8) | UInt32(b) }
        return v
    }
}
