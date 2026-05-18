import AppKit
import SwiftUI

/// Glass scrollbars — force every `NSScrollView` in this view's
/// window to the translucent **overlay** scroller with no opaque
/// track, so the menu-bar popover matches the MattsSoftware
/// launcher instead of AppKit's legacy black scrollbar (which it
/// renders when the system "Show scroll bars" is *Always* or inside
/// a material/glass panel). No SwiftUI API exposes the overlay
/// style, so a zero-size companion view reaches the window and
/// fixes the scrollers. No-ops until the window exists; never
/// crashes. Attach once with `.glassScrollers()` on the popover's
/// root view.
private struct ScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        func pass() {
            guard let root = nsView.window?.contentView else { return }
            apply(in: root)
        }
        DispatchQueue.main.async(execute: pass)
        // A second deferred pass covers scroll views created after
        // the first layout (e.g. lazily, or once data arrives).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15,
                                      execute: pass)
    }

    private func apply(in view: NSView) {
        if let sv = view as? NSScrollView {
            sv.scrollerStyle = .overlay
            sv.drawsBackground = false
            sv.backgroundColor = .clear
            sv.contentView.drawsBackground = false
            sv.verticalScroller?.scrollerStyle = .overlay
            sv.horizontalScroller?.scrollerStyle = .overlay
        }
        for sub in view.subviews { apply(in: sub) }
    }
}

extension View {
    /// Glass-ify every scroller in the popover window (translucent
    /// overlay, no opaque track) — matches the launcher's style.
    /// Attach once on the root view.
    func glassScrollers() -> some View {
        background(ScrollViewConfigurator())
    }
}
