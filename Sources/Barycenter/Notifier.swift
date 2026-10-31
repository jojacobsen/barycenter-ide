import AppKit
import UserNotifications

/// macOS banner notifications. Only works when Barycenter runs as a .app bundle
/// (bundle identity present) — as a bare dev binary it is silently skipped.
enum Notifier {
    static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func attention(sessionTitle: String) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Session braucht dich")
        content.body = sessionTitle
        content.sound = nil   // we play the sound ourselves (Ping) -> no double tone
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
