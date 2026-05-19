import Foundation
import UserNotifications

/// Thin wrapper over UserNotifications for "camera/mic just went active" alerts.
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func postActive(key: String, device: UsageDevice, app: String?) {
        let content = UNMutableNotificationContent()
        let who = (app?.isEmpty == false) ? app! : "an unknown app"
        switch device {
        case .camera:
            content.title = "Camera in use"
            content.body = "\(who) started using the camera. Click to view in Peephole."
        case .microphone:
            content.title = "Microphone in use"
            content.body = "\(who) started using the microphone. Click to view in Peephole."
        }
        content.userInfo = ["peepKey": key, "suitePane": "peephole", "suiteFocus": key]
        send(id: "peep-\(key)", content: content)
    }

    private static func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
