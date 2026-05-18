import CoreMediaIO
import Foundation

/// Authoritative, entitlement-free "is any camera actually streaming" check.
///
/// `kCMIODevicePropertyDeviceIsRunningSomewhere` is the same signal the macOS
/// camera indicator (and, for the built-in camera, the hardware LED) reflects.
/// Peephole's log scraping is best-effort and can leave stale "active"
/// sessions; this is the ground truth used to gate camera state.
enum CameraState {
    static func isCameraRunningSomewhere() -> Bool {
        for device in devices() {
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var used: UInt32 = 0
            var addr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            let status = CMIOObjectGetPropertyData(device, &addr, 0, nil, size, &used, &running)
            if status == 0, running != 0 { return true }
        }
        return false
    }

    private static func devices() -> [CMIOObjectID] {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &dataSize) == 0,
              dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, dataSize, &used, &ids) == 0
        else { return [] }
        return ids
    }
}
