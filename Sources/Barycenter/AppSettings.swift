import AppKit
import SwiftTerm

extension Notification.Name {
    static let settingsChanged = Notification.Name("BarycenterSettingsChanged")
}

/// Persistente Nutzer-Vorlieben (UserDefaults). Jeder stellt sich Theme/Schrift selbst ein.
/// Änderungen greifen sofort für alle bestehenden + neuen Sessions.
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    private enum Keys {
        static let theme = "theme"
        static let fontName = "fontName"
        static let fontSize = "fontSize"
    }

    var themeName: String {
        get { d.string(forKey: Keys.theme) ?? "Barycenter Dark" }
        set { d.set(newValue, forKey: Keys.theme); changed() }
    }
    var fontName: String {
        get { d.string(forKey: Keys.fontName) ?? "Menlo" }
        set { d.set(newValue, forKey: Keys.fontName); changed() }
    }
    var fontSize: CGFloat {
        get { let v = d.double(forKey: Keys.fontSize); return v == 0 ? 13 : CGFloat(v) }
        set { d.set(Double(newValue), forKey: Keys.fontSize); changed() }
    }

    /// Notizen-Bereich unten in der Seitenleiste ein-/ausblenden.
    var showSidebarNotes: Bool {
        get { d.bool(forKey: "showSidebarNotes") }
        set { d.set(newValue, forKey: "showSidebarNotes"); NotificationCenter.default.post(name: .settingsChanged, object: nil) }
    }

    var theme: Theme { Theme.named(themeName) }

    /// Auf ein einzelnes Terminal anwenden (z.B. beim Erzeugen einer Session).
    func apply(to tv: LocalProcessTerminalView) {
        theme.apply(to: tv, fontName: fontName, fontSize: fontSize)
    }

    /// Auf alle laufenden Sessions anwenden.
    func applyToAll() {
        for s in SessionManager.shared.sessions { apply(to: s.terminalView) }
    }

    private func changed() {
        applyToAll()
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
