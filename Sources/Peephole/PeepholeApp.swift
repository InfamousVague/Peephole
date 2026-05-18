import SwiftUI
import AppKit
import UserNotifications

@main
struct PeepholeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Accessory app: the real UI is the NSStatusItem/NSPopover the
        // delegate manages. This scene stays empty/never shown.
        Settings { EmptyView() }
    }

    /// Idle menu-bar glyph (eye with a warning badge), set as a template so
    /// macOS tints it for the active menu-bar appearance.
    static let idleIcon: NSImage = symbol("eye.trianglebadge.exclamationmark")

    /// Active glyph — a filled eye — shown while the camera or mic is live so
    /// the menu bar itself reflects state without opening the popover.
    static let activeIcon: NSImage = symbol("eye.fill")

    private static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Peephole")
            ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = PeepholeStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = PeepholeApp.idleIcon
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environment(store)
        )

        store.onActiveChange = { [weak self] active in
            guard let button = self?.statusItem.button else { return }
            button.image = active ? PeepholeApp.activeIcon : PeepholeApp.idleIcon
        }
        store.start()

        UNUserNotificationCenter.current().delegate = self
        Notifier.requestAuthorization()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let key = response.notification.request.content.userInfo["peepKey"] as? String
        DispatchQueue.main.async {
            self.store.focusedKey = key
            self.showPopover()
        }
        completionHandler()
    }
}
