import AppKit
import Foundation

/// Detect & remove the legacy `allowCamera=false` configuration profile that
/// older Peephole builds (the profile-based camera kill, before reactive)
/// asked the user to install. Removing the *code* that wrote that profile
/// doesn't remove a profile the user actually approved — only the user can,
/// so Peephole surfaces a one-click "remove" that goes through the proper
/// admin-authorization path.
///
/// Detection sources, in order:
///   1. The managed-prefs file the profile deposits — the actual enforcer;
///      readable by the user without sudo.
///   2. The user-domain profile registry (`profiles list -type configuration`).
enum LegacyProfileCleaner {
    /// Identifier the older Peephole `CameraControl` used.
    static let legacyIdentifier = "com.mattssoftware.peephole.cameraoff"

    static func isInstalled() -> Bool {
        if managedPrefForcesAllowCameraFalse() { return true }
        return userDomainHasLegacyProfile()
    }

    /// Returns true if `/Library/Managed Preferences/<user>/com.apple.applicationaccess.plist`
    /// exists AND sets `allowCamera = false`.
    private static func managedPrefForcesAllowCameraFalse() -> Bool {
        let path = "/Library/Managed Preferences/\(NSUserName())/com.apple.applicationaccess.plist"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization
                  .propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return false }
        if let allowCamera = plist["allowCamera"] as? Bool { return allowCamera == false }
        return false
    }

    private static func userDomainHasLegacyProfile() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/profiles")
        proc.arguments = ["list", "-type", "configuration"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.contains(legacyIdentifier)
    }

    /// Remove the profile via one admin password prompt
    /// (`do shell script with administrator privileges`). Also flushes the
    /// prefs cache and bounces `cameracaptured` so cameras come back without
    /// a reboot. Throws on user-cancel or non-zero exit.
    static func remove() throws {
        let user = NSUserName()
        let inner = """
        /usr/bin/profiles remove -identifier \(legacyIdentifier) -user \(user) ; \
        /usr/bin/killall cfprefsd 2>/dev/null ; \
        /usr/bin/killall cameracaptured 2>/dev/null ; \
        true
        """
        let source = """
        do shell script "\(inner)" with administrator privileges
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw NSError(
                domain: "Peephole.LegacyProfileCleaner",
                code: (error[NSAppleScript.errorNumber] as? Int) ?? 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        _ = result
    }
}
