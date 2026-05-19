import SwiftUI
import AppKit
import UserNotifications
import PeepholePane
import SuiteKit

// Standalone Peephole. Post-split this is just a host shim — the
// whole sentinel (detection, mic/camera control, UI, notifier) lives
// in `PeepholePane` so the MattsSoftware launcher can load the same
// code out of an installed Peephole.app. Behaviour unchanged.
@main
struct PeepholeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate,
    UNUserNotificationCenterDelegate, NSPopoverDelegate
{
    private let pane = PeepholePaneProvider()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SuiteGuard.exitIfDeferring("peephole")

        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = pane.paneMenuBarImage()
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        pane.onMenuBarImageChange = { [weak self] img in
            self?.statusItem.button?.image = img
        }

        let vc = NSViewController()
        vc.view = pane.paneMakeView()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = vc

        pane.paneStart()
        UNUserNotificationCenter.current().delegate = self
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) }
        else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button,
                     preferredEdge: .minY)
        if let win = popover.contentViewController?.view.window {
            clampOnScreen(win, anchoredTo: button)
            win.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in self?.popover.performClose(nil) }
    }

    private func clampOnScreen(_ win: NSWindow, anchoredTo anchor: NSView) {
        guard let screen = anchor.window?.screen ?? NSScreen.main
        else { return }
        let vis = screen.visibleFrame
        let pad: CGFloat = 8
        var f = win.frame
        if f.maxX > vis.maxX - pad { f.origin.x = vis.maxX - pad - f.width }
        if f.minX < vis.minX + pad { f.origin.x = vis.minX + pad }
        if f.minY < vis.minY + pad { f.origin.y = vis.minY + pad }
        if f != win.frame { win.setFrame(f, display: true) }
    }

    func popoverDidClose(_ notification: Notification) {
        if let m = clickMonitor {
            NSEvent.removeMonitor(m); clickMonitor = nil
        }
    }

    // MARK: - UNUserNotificationCenterDelegate (standalone)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) { handler([.banner, .list]) }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler handler: @escaping () -> Void
    ) {
        let key = response.notification.request.content
            .userInfo["peepKey"] as? String
        DispatchQueue.main.async {
            if let key { self.pane.paneFocus(key) }
            self.showPopover()
        }
        handler()
    }
}
