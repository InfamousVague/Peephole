import AppKit

/// Peephole's menu-bar glyphs, relocated out of the thin `Peephole`
/// shim so the pane (what the launcher loads) and the standalone
/// app share one source. Template SF Symbols, no bundled assets.
enum PeepholeBrand {
    /// Idle — eye with a warning badge.
    static let idleIcon = symbol("eye.trianglebadge.exclamationmark")
    /// Active — filled eye, shown while camera/mic is live.
    static let activeIcon = symbol("eye.fill")

    private static func symbol(_ name: String) -> NSImage {
        // No forced size: stamping `size = 16×16` lies to SwiftUI
        // about the aspect ratio, so `.scaledToFit()` in the
        // launcher switcher squashes non-square glyphs (the eye
        // with the warning badge is taller than wide). Letting the
        // SF symbol keep its natural metrics fixes the squash.
        let image = NSImage(systemSymbolName: name,
                            accessibilityDescription: "Peephole")
            ?? NSImage()
        image.isTemplate = true
        return image
    }
}
