import CoreMediaIO
import Foundation

/// One CMIO video device — what we show as a "camera" in the UI.
struct CameraInfo: Identifiable, Hashable {
    let id: UInt32                // CMIOObjectID
    let name: String
    let manufacturer: String?
    let transport: String         // "Built-in", "USB", "Virtual", etc.
    let isRunning: Bool           // matches CameraState's authoritative signal
}

/// Entitlement-free per-camera inspection via CoreMediaIO.
///
/// Hard-learned constraint: enumerating CMIO **streams** or reading
/// `kCMIOStreamPropertyFormatDescriptions` per poll can wake/hold the
/// underlying device (notably Continuity Camera through `cameracaptured`)
/// and starve other apps from acquiring it. We therefore:
///   • read only cheap, scalar device properties (no streams, no formats),
///   • cache the static ones (name, manufacturer, transport) once per
///     device id and reuse forever, and
///   • re-read only `IsRunningSomewhere` on each tick — the same single
///     property `CameraState` already polled safely before this file
///     existed.
enum CameraDevices {
    static func all() -> [CameraInfo] { deviceIDs().map(info(for:)) }

    // MARK: enumeration

    private static func deviceIDs() -> [CMIOObjectID] {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0,
              size > 0 else { return [] }
        let n = Int(size) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: n)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == 0
        else { return [] }
        return ids
    }

    // MARK: per device

    private struct Static {
        let name: String
        let manufacturer: String?
        let transport: String
    }

    nonisolated(unsafe) private static var cache: [CMIOObjectID: Static] = [:]
    private static let cacheLock = NSLock()

    private static func info(for dev: CMIOObjectID) -> CameraInfo {
        let s = cachedStatic(for: dev)
        let running = (uint32(
            dev, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        ) ?? 0) != 0
        return CameraInfo(
            id: dev, name: s.name, manufacturer: s.manufacturer,
            transport: s.transport, isRunning: running
        )
    }

    private static func cachedStatic(for dev: CMIOObjectID) -> Static {
        cacheLock.lock()
        if let s = cache[dev] {
            cacheLock.unlock()
            return s
        }
        cacheLock.unlock()
        // Read outside the lock so a slow CMIO call can't block other callers.
        let name = cfString(dev, CMIOObjectPropertySelector(kCMIOObjectPropertyName))
            ?? "Camera \(dev)"
        let manufacturer = cfString(
            dev, CMIOObjectPropertySelector(kCMIOObjectPropertyManufacturer)
        )
        let transport = transportLabel(
            uint32(dev, CMIOObjectPropertySelector(kCMIODevicePropertyTransportType))
        )
        let s = Static(name: name, manufacturer: manufacturer, transport: transport)
        cacheLock.lock()
        cache[dev] = s
        cacheLock.unlock()
        return s
    }

    // MARK: helpers

    private static func cfString(
        _ dev: CMIOObjectID, _ selector: CMIOObjectPropertySelector
    ) -> String? {
        var addr = CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == 0,
              size > 0 else { return nil }
        var cf: Unmanaged<CFString>?
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(dev, &addr, 0, nil, size, &used, &cf) == 0,
              let s = cf?.takeRetainedValue() else { return nil }
        return s as String
    }

    private static func uint32(
        _ dev: CMIOObjectID, _ selector: CMIOObjectPropertySelector
    ) -> UInt32? {
        var addr = CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(dev, &addr, 0, nil, size, &used, &v) == 0
        else { return nil }
        return v
    }

    /// FourCC transport code → friendly label, fallback to the raw 4-char.
    private static func transportLabel(_ code: UInt32?) -> String {
        guard let code, code != 0 else { return "Unknown" }
        switch code {
        case fourCC("bltn"): return "Built-in"
        case fourCC("usb "): return "USB"
        case fourCC("virt"): return "Virtual"
        case fourCC("ndev"): return "Network"
        case fourCC("aggr"): return "Aggregate"
        case fourCC("fwir"): return "FireWire"
        case fourCC("thnd"): return "Thunderbolt"
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
