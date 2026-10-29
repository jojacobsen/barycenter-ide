import AppKit
import UserNotifications

/// macOS-Banner-Notifications. Funktioniert nur, wenn Barycenter als .app-Bundle
/// läuft (Bundle-Identität vorhanden) — als nacktes Dev-Binary wird still übersprungen.
enum Notifier {
    static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func attention(sessionTitle: String) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Session braucht dich"
        content.body = sessionTitle
        content.sound = nil   // Ton spielen wir selbst (Ping) -> kein Doppelton
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
