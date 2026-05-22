import Foundation

/// Compact widget-facing snapshot of camera/mic activity.
/// Host writes whenever activity changes; widget reads on refresh.
public struct SharedPeephole: Codable, Sendable, Equatable {
    public var cameraActive: Bool
    public var micActive: Bool
    /// Names of currently-running camera devices (empty if none).
    public var activeCameras: [String]
    /// Names of currently-running mic devices (empty if none).
    public var activeMics: [String]
    public var sampledAt: Date

    public init(
        cameraActive: Bool = false,
        micActive: Bool = false,
        activeCameras: [String] = [],
        activeMics: [String] = [],
        sampledAt: Date = .distantPast
    ) {
        self.cameraActive = cameraActive
        self.micActive = micActive
        self.activeCameras = activeCameras
        self.activeMics = activeMics
        self.sampledAt = sampledAt
    }

    public var anyActive: Bool { cameraActive || micActive }
}
