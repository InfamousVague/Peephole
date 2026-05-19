import AppKit

/// Peephole's menu-bar glyphs, relocated out of the thin `Peephole`
/// shim so the pane (what the launcher loads) and the standalone
/// app share one source. Template SF Symbols, no bundled assets.
enum PeepholeBrand {
    /// Idle — camera glyph.
    static let idleIcon = symbol("camera")
    /// Active — filled camera, shown while camera/mic is live.
    static let activeIcon = symbol("camera.fill")

    private static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name,
                            accessibilityDescription: "Peephole")
            ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }
}
