import AppKit
import SwiftTerm

extension Notification.Name {
    static let settingsChanged = Notification.Name("BarycenterSettingsChanged")
}

/// Persistent user preferences (UserDefaults). Everyone sets their own theme/font.
/// Changes apply immediately to all existing + new sessions.
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

    /// Show/hide the notes area at the bottom of the sidebar.
    var showSidebarNotes: Bool {
        get { d.bool(forKey: "showSidebarNotes") }
        set { d.set(newValue, forKey: "showSidebarNotes"); NotificationCenter.default.post(name: .settingsChanged, object: nil) }
    }

    /// Show line numbers in the file editor (default: on).
    var showEditorLineNumbers: Bool {
        get { d.object(forKey: "showEditorLineNumbers") == nil ? true : d.bool(forKey: "showEditorLineNumbers") }
        set { d.set(newValue, forKey: "showEditorLineNumbers"); NotificationCenter.default.post(name: .settingsChanged, object: nil) }
    }

    /// Folder the AI manager starts in (default: home).
    var managerDir: String {
        get { d.string(forKey: "managerDir") ?? FileManager.default.homeDirectoryForCurrentUser.path }
        set { d.set(newValue, forKey: "managerDir") }
    }

    /// AI/profile the AI manager starts with (default: Claude Code).
    var managerProfile: String {
        get { d.string(forKey: "managerProfile") ?? "Claude Code" }
        set { d.set(newValue, forKey: "managerProfile") }
    }

    /// Custom launch command for the manager when profile is "Custom Command…" (otherwise empty).
    var managerCommand: String {
        get { d.string(forKey: "managerCommand") ?? "" }
        set { d.set(newValue, forKey: "managerCommand") }
    }

    var theme: Theme { Theme.named(themeName) }

    /// Apply to a single terminal (e.g. when creating a session).
    func apply(to tv: LocalProcessTerminalView) {
        theme.apply(to: tv, fontName: fontName, fontSize: fontSize)
    }

    /// Apply to all running sessions.
    func applyToAll() {
        for s in SessionManager.shared.sessions { apply(to: s.terminalView) }
    }

    private func changed() {
        applyToAll()
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
