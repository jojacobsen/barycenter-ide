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

    /// Sentinel stored in `notificationSound` to mean "no tone" (banner may still show).
    static let soundOff = "__off__"

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

    /// Show the AI manager ("Verwalter") in the activity rail & menu (default: on).
    var showManager: Bool {
        get { d.object(forKey: "showManager") == nil ? true : d.bool(forKey: "showManager") }
        set { d.set(newValue, forKey: "showManager"); NotificationCenter.default.post(name: .settingsChanged, object: nil) }
    }

    /// Notify (banner + Dock bounce + sound) when a session needs attention / is done (default: on).
    var notificationsEnabled: Bool {
        get { d.object(forKey: "notificationsEnabled") == nil ? true : d.bool(forKey: "notificationsEnabled") }
        set { d.set(newValue, forKey: "notificationsEnabled"); NotificationCenter.default.post(name: .settingsChanged, object: nil) }
    }

    /// Name of the system sound played on attention. `AppSettings.soundOff` = silent.
    /// Default: "Ping".
    var notificationSound: String {
        get { d.string(forKey: "notificationSound") ?? "Ping" }
        set { d.set(newValue, forKey: "notificationSound"); NotificationCenter.default.post(name: .settingsChanged, object: nil) }
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

    /// Names of the built-in macOS alert sounds (e.g. "Ping", "Glass"), sorted.
    /// These are exactly the names `NSSound(named:)` understands.
    static func availableSystemSounds() -> [String] {
        let dir = "/System/Library/Sounds"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir))?
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted() ?? []
        // Fallback to a sensible default set if the directory could not be read.
        return names.isEmpty
            ? ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
               "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
            : names
    }

    /// Play the configured attention sound once (respects "off"). Used for preview & on attention.
    func playNotificationSound() {
        guard notificationSound != AppSettings.soundOff else { return }
        NSSound(named: notificationSound)?.play()
    }
}
