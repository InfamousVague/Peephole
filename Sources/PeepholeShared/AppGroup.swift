import Foundation

/// Shared App Group id for the Peephole host + widget extension.
/// Must match `PeepholeWidgets.entitlements` and `Peephole.entitlements`.
public enum AppGroup {
    public static let id =
        "F6ZAL7ANAD.group.com.mattssoftware.peephole"
    public static var containerURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}
