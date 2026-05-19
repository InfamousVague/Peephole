import AppKit
import SwiftUI
import SuiteKit

/// Peephole as a SuiteKit pane. Owns the store, vends the UI, and
/// drives the idle⇄active menu-bar glyph (camera/mic live). Both the
/// standalone shim and the launcher host talk to Peephole only
/// through this object.
@MainActor
public final class PeepholePaneProvider: NSObject, SuitePane {
    private let store = PeepholeStore()
    private var active = false

    /// Standalone shim / host segment icon refresh.
    public var onMenuBarImageChange: ((NSImage) -> Void)?

    public override init() {
        super.init()
        store.onActiveChange = { [weak self] live in
            guard let self else { return }
            self.active = live
            self.onMenuBarImageChange?(self.paneMenuBarImage())
        }
    }

    public var suiteABIVersion: Int { SuiteKitABI.current }
    public var paneID: String { "peephole" }
    public var paneTitle: String { "PEEPHOLE" }
    public var paneTintHex: String { "#34C7B5" }

    public func paneMenuBarImage() -> NSImage {
        active ? PeepholeBrand.activeIcon : PeepholeBrand.idleIcon
    }

    public func paneMakeView() -> NSView {
        NSHostingView(rootView: ContentView().environment(store))
    }

    public func paneStart() {
        store.start()
        Notifier.requestAuthorization()
    }

    public func paneStop() {
        // Detection is a unified-log tail; harmless to leave running.
    }

    public func paneFocus(_ key: String) {
        store.focusedKey = key
    }
}

@_cdecl("suitePaneCreate")
public func suitePaneCreate() -> Unmanaged<AnyObject> {
    MainActor.assumeIsolated {
        Unmanaged.passRetained(PeepholePaneProvider())
    }
}
