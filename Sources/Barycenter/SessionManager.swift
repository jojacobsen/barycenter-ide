import AppKit

extension Notification.Name {
    /// Liste der Sessions oder ein Status hat sich geändert -> UI neu aufbauen.
    static let sessionsChanged = Notification.Name("BarycenterSessionsChanged")
    /// Nur die Auswahl hat sich geändert.
    static let selectionChanged = Notification.Name("BarycenterSelectionChanged")
    /// „Neue Session" wurde angefordert (＋ Button oder Cmd+T) -> Sheet zeigen.
    static let newSessionRequested = Notification.Name("BarycenterNewSessionRequested")
    /// „KI-Verwalter starten" wurde angefordert -> Konfig-Sheet (Ordner + AI) zeigen.
    static let managerRequested = Notification.Name("BarycenterManagerRequested")
}

enum ViewMode { case grid, focus }

/// Zentrale Quelle der Wahrheit: hält alle Sessions, Auswahl, Ansicht, Seite.
/// UI (Sidebar + Content) beobachtet via NotificationCenter.
final class SessionManager {
    static let shared = SessionManager()

    private(set) var sessions: [Session] = []
    var selectedID: UUID?
    var viewMode: ViewMode = .grid
    var page = 0
    let pageSize = 8   // ab 8 Kacheln -> neue Seite

    var selectedSession: Session? { sessions.first { $0.id == selectedID } }

    /// Normale Sessions (ohne den Manager — der hat einen eigenen Bereich).
    var workerSessions: [Session] { sessions.filter { !$0.isManager } }
    var managerSession: Session? { sessions.first { $0.isManager } }

    var pageCount: Int { max(1, Int(ceil(Double(workerSessions.count) / Double(pageSize)))) }

    func visibleSessions() -> [Session] {
        let w = workerSessions
        let start = page * pageSize
        guard start < w.count else { return [] }
        return Array(w[start ..< min(start + pageSize, w.count)])
    }

    // MARK: - Mutationen

    @discardableResult
    func addSession(title: String, cwd: String, launchCommand: String?, profileName: String,
                    remoteControl: Bool = false, isManager: Bool = false, extraArgs: [String] = []) -> Session {
        let s = Session(title: title, cwd: cwd, launchCommand: launchCommand,
                        profileName: profileName, remoteControl: remoteControl,
                        isManager: isManager, extraArgs: extraArgs)
        sessions.append(s)
        s.start()
        if !isManager {
            selectedID = s.id
            page = (workerSessions.count - 1) / pageSize   // auf die Seite der neuen Session springen
        }
        post(.sessionsChanged)
        return s
    }

    @discardableResult
    func addShellSession(title: String? = nil) -> Session {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return addSession(title: title ?? "\(sessions.count + 1) · shell",
                          cwd: home, launchCommand: nil, profileName: "Shell")
    }

    // MARK: - Layouts (welche Projekte/Sessions mit welchen Einstellungen laufen)

    var currentLayoutName: String? {
        get { UserDefaults.standard.string(forKey: "currentLayoutName") }
        set { UserDefaults.standard.set(newValue, forKey: "currentLayoutName") }
    }

    /// Specs der aktuellen Worker-Sessions (ohne Manager).
    func currentSpecs() -> [SessionSpec] {
        workerSessions.map {
            SessionSpec(title: $0.title, cwd: $0.cwd, launchCommand: $0.launchCommand,
                        profileName: $0.profileName, remoteControl: $0.remoteControl)
        }
    }

    func clearWorkers() {
        for s in workerSessions { remove(s.id) }
    }

    private func spawn(from spec: SessionSpec) {
        var cwd = spec.cwd
        if !FileManager.default.fileExists(atPath: cwd) {
            cwd = FileManager.default.homeDirectoryForCurrentUser.path
        }
        addSession(title: spec.title, cwd: cwd, launchCommand: spec.launchCommand,
                   profileName: spec.profileName, remoteControl: spec.remoteControl)
    }

    /// Ersetzt die aktuellen Worker-Sessions durch die des Layouts.
    func applyLayout(_ layout: Layout) {
        clearWorkers()
        for spec in layout.sessions { spawn(from: spec) }
        currentLayoutName = layout.name
        LayoutStore.lastName = layout.name
    }

    func saveCurrentLayout(name: String) {
        LayoutStore.save(Layout(name: name, sessions: currentSpecs()))
        currentLayoutName = name
        LayoutStore.lastName = name
    }

    var managerIsRunning: Bool { managerSession != nil }

    /// Startet den KI-Verwalter mit gewähltem Ordner + AI (oder fokussiert ihn, falls er schon läuft).
    /// `launchCommand == "claude"` bekommt die Aufgabe als System-Prompt-Datei; andere AIs
    /// (Codex/Gemini/Aider/Custom) bekommen sie als erste Nachricht „lies diese Datei".
    func spawnManager(dir: String, profileName: String, launchCommand: String?) {
        if let existing = managerSession {
            select(existing.id); setViewMode(.focus); return
        }
        var cwd = dir
        if !FileManager.default.fileExists(atPath: cwd) {
            cwd = FileManager.default.homeDirectoryForCurrentUser.path
        }
        let promptPath = writeManagerPrompt()
        var extra: [String] = []
        if launchCommand == "claude" {
            extra = ["--append-system-prompt-file", promptPath]
        }
        let s = addSession(title: L("KI-Verwalter"), cwd: cwd, launchCommand: launchCommand,
                           profileName: profileName, isManager: true, extraArgs: extra)
        if launchCommand != "claude" {
            // Andere AIs kennen kein --append-system-prompt-file: Aufgabe per erster Nachricht einspielen.
            let msg = String(format: L("Lies die Datei %@ — sie beschreibt deine Aufgabe als Barycenter-Verwalter und die Steuerbefehle (baryctl)."), promptPath)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                s.terminalView.send(txt: msg + "\r")
            }
        }
    }

    /// Bequemer Start mit den gespeicherten Verwalter-Einstellungen.
    func spawnManagerFromSettings() {
        let st = AppSettings.shared
        let launch: String?
        if st.managerProfile == Profile.customName {
            let c = st.managerCommand.trimmingCharacters(in: .whitespaces)
            launch = c.isEmpty ? "claude" : c
        } else {
            launch = Profile.builtins.first { $0.name == st.managerProfile }?.command ?? "claude"
        }
        spawnManager(dir: st.managerDir, profileName: st.managerProfile, launchCommand: launch)
    }

    private func writeManagerPrompt() -> String {
        let ctl = ControlServer.shared.baryctlPath
        let text = """
        Du bist der „KI-Verwalter" von Barycenter — einem Mission-Control für viele parallele Claude-Code-/CLI-Sessions.
        Du steuerst Barycenter über dein Bash-Tool mit diesem Kommando:
          \(ctl)

        Befehle:
          \(ctl) list
              -> JSON aller Sessions mit Status (busy/waiting/idle), Ordner, Profil, RC.
          \(ctl) spawn --profile "Claude Code" --dir <ordner> [--name <name>] [--rc] [--prompt "<auftrag>"]
              -> startet eine neue Session (bei --prompt wird der Auftrag nach dem Hochfahren abgeschickt).
          \(ctl) send --title <name> --text "<text>"
              -> schickt Text an eine Session (wird mit Enter abgeschickt). Alternativ --id <uuid>.
          \(ctl) focus --title <name>     -> Session groß anzeigen.
          \(ctl) close --title <name>     -> Session schließen.

        Profile: "Claude Code", "Codex (OpenAI)", "Gemini CLI", "Aider", "Shell".
        Beliebige CLI: spawn --command "<cmd>" --dir <ordner>.

        Arbeitsweise: Wenn der Nutzer dich bittet, Sessions zu starten/überwachen/steuern, nutze diese Befehle
        und fasse den Zustand per `list` zusammen. Spawne NICHT ungefragt viele Sessions; frage im Zweifel nach.
        Du bist selbst eine Session (Profil „Manager") — schließe dich nicht selbst.
        """
        let path = NSTemporaryDirectory() + "barycenter-manager-prompt.txt"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// Session schließen — mit Rückfrage, falls Prozess läuft oder Notizen vorhanden sind.
    func requestClose(_ id: UUID, window: NSWindow?) {
        guard let s = sessions.first(where: { $0.id == id }) else { return }
        let needsConfirm = (s.status == .running) || !s.notes.isEmpty
        guard needsConfirm else { remove(id); return }

        let alert = NSAlert()
        alert.messageText = String(format: L("Session %@ schließen?"), s.title)
        var info = L("Der laufende Prozess wird beendet.")
        if !s.notes.isEmpty { info += " " + L("Die Notizen dieser Session gehen verloren.") }
        info += " " + L("Ist alles gespeichert?")
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Schließen"))
        alert.addButton(withTitle: L("Abbrechen"))

        if let win = window ?? NSApp.keyWindow {
            alert.beginSheetModal(for: win) { [weak self] resp in
                if resp == .alertFirstButtonReturn { self?.remove(id) }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            remove(id)
        }
    }

    /// Status einer Session setzen (von Hooks/Bell). Bei „attention": Sound + Dock-Bounce.
    func setStatus(_ status: SessionStatus, for id: UUID) {
        guard let s = sessions.first(where: { $0.id == id }), s.status != status else { return }
        s.status = status
        if status == .attention {
            NSSound(named: "Ping")?.play()
            NSApp.requestUserAttention(.informationalRequest)   // Dock-Bounce
            Notifier.attention(sessionTitle: s.title)           // macOS-Banner (nur als .app)
        }
        post(.sessionsChanged)
    }

    func select(_ id: UUID) {
        selectedID = id
        // Beim Betrachten Attention löschen.
        var cleared = false
        if let s = sessions.first(where: { $0.id == id }), s.status == .attention {
            s.status = .running
            cleared = true
        }
        // Im Grid automatisch auf die Seite der Session springen (so kommt man z.B. zurück zu Seite 1).
        if let idx = workerSessions.firstIndex(where: { $0.id == id }) {
            let target = idx / pageSize
            if target != page {
                page = target
                post(.sessionsChanged)
                return
            }
        }
        post(cleared ? .sessionsChanged : .selectionChanged)
    }

    func remove(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let s = sessions.remove(at: idx)
        s.terminate()
        s.terminalView.removeFromSuperview()
        if selectedID == id { selectedID = sessions.first?.id }
        if page >= pageCount { page = pageCount - 1 }
        post(.sessionsChanged)
    }

    func setViewMode(_ m: ViewMode) {
        guard viewMode != m else { return }
        viewMode = m
        post(.sessionsChanged)
    }

    func nextPage() { if page < pageCount - 1 { page += 1; post(.sessionsChanged) } }
    func prevPage() { if page > 0 { page -= 1; post(.sessionsChanged) } }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
