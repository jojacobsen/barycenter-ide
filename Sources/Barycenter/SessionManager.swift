import AppKit

extension Notification.Name {
    /// The session list or a status changed -> rebuild the UI.
    static let sessionsChanged = Notification.Name("BarycenterSessionsChanged")
    /// Only the selection changed.
    static let selectionChanged = Notification.Name("BarycenterSelectionChanged")
    /// "New session" was requested (＋ button or Cmd+T) -> show the sheet.
    static let newSessionRequested = Notification.Name("BarycenterNewSessionRequested")
    /// "Start AI manager" was requested -> show the config sheet (folder + AI).
    static let managerRequested = Notification.Name("BarycenterManagerRequested")
}

enum ViewMode { case grid, focus }

/// Central source of truth: holds all sessions, selection, view, page.
/// The UI (sidebar + content) observes via NotificationCenter.
final class SessionManager {
    static let shared = SessionManager()

    private(set) var sessions: [Session] = []
    var selectedID: UUID?
    var viewMode: ViewMode = .grid
    var page = 0
    let pageSize = 8   // from 8 tiles on -> new page

    var selectedSession: Session? { sessions.first { $0.id == selectedID } }

    /// Normal sessions (without the manager — it has its own area).
    var workerSessions: [Session] { sessions.filter { !$0.isManager } }
    var managerSession: Session? { sessions.first { $0.isManager } }

    var pageCount: Int { max(1, Int(ceil(Double(workerSessions.count) / Double(pageSize)))) }

    func visibleSessions() -> [Session] {
        let w = workerSessions
        let start = page * pageSize
        guard start < w.count else { return [] }
        return Array(w[start ..< min(start + pageSize, w.count)])
    }

    // MARK: - Mutations

    @discardableResult
    func addSession(title: String, cwd: String, launchCommand: String?, profileName: String,
                    remoteControl: Bool = false, resume: Bool = false,
                    isManager: Bool = false, extraArgs: [String] = []) -> Session {
        let s = Session(title: title, cwd: cwd, launchCommand: launchCommand,
                        profileName: profileName, remoteControl: remoteControl,
                        resume: resume, isManager: isManager, extraArgs: extraArgs)
        sessions.append(s)
        s.start()
        if !isManager {
            selectedID = s.id
            page = (workerSessions.count - 1) / pageSize   // jump to the page of the new session
            // Remember how this project was launched, to pre-fill the next New Session.
            LaunchMemory.remember(cwd: cwd, profileName: profileName,
                                  launchCommand: launchCommand, remoteControl: remoteControl)
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

    // MARK: - Layouts (which projects/sessions run with which settings)

    var currentLayoutName: String? {
        get { UserDefaults.standard.string(forKey: "currentLayoutName") }
        set { UserDefaults.standard.set(newValue, forKey: "currentLayoutName") }
    }

    /// Specs of the current worker sessions (without the manager).
    func currentSpecs() -> [SessionSpec] {
        workerSessions.map {
            SessionSpec(title: $0.title, cwd: $0.cwd, launchCommand: $0.launchCommand,
                        profileName: $0.profileName, remoteControl: $0.remoteControl, resume: $0.resume)
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
                   profileName: spec.profileName, remoteControl: spec.remoteControl,
                   resume: spec.resume ?? false)
    }

    /// Replaces the current worker sessions with those of the layout.
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

    /// Whether a manager ("Control Center") session was running — persisted so it can
    /// be auto-started on the next launch.
    private var managerWasRunning: Bool {
        get { UserDefaults.standard.bool(forKey: "managerWasRunning") }
        set { UserDefaults.standard.set(newValue, forKey: "managerWasRunning") }
    }

    /// On launch: re-start the manager if it was running last time (and still enabled).
    func restoreManagerIfNeeded() {
        guard managerWasRunning, AppSettings.shared.showManager, managerSession == nil else { return }
        spawnManagerFromSettings()
    }

    /// Starts the AI manager with the chosen folder + AI (or focuses it if it's already running).
    /// `launchCommand == "claude"` gets the task as a system-prompt file; other AIs
    /// (Codex/Gemini/Aider/Custom) get it as a first message "read this file".
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
        managerWasRunning = true   // remember so it auto-starts next launch
        if launchCommand != "claude" {
            // Other AIs don't know --append-system-prompt-file: feed the task via a first message.
            let msg = String(format: L("Lies die Datei %@ — sie beschreibt deine Aufgabe als Barycenter-Verwalter und die Steuerbefehle (baryctl)."), promptPath)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                s.terminalView.send(txt: msg + "\r")
            }
        }
    }

    /// Convenient start using the saved manager settings.
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
        You are the "AI manager" of Barycenter — a mission control for many parallel Claude Code / CLI sessions.
        You control Barycenter through your Bash tool with this command:
          \(ctl)

        Commands:
          \(ctl) list
              -> JSON of all sessions with status (busy/waiting/idle), folder, profile, RC.
          \(ctl) spawn --profile "Claude Code" --dir <folder> [--name <name>] [--rc] [--prompt "<task>"]
              -> starts a new session (with --prompt the task is sent after it has started up).
          \(ctl) send --title <name> --text "<text>"
              -> sends text to a session (submitted with Enter). Alternatively --id <uuid>.
          \(ctl) read --title <name> [--lines <n>]
              -> reads the current terminal content (scrollback) of a session, the last <n>
                 lines (default 200). This is how you see what a session is doing/asking. Alternatively --id <uuid>.
          \(ctl) focus --title <name>     -> show a session large.
          \(ctl) close --title <name>     -> close a session.
          \(ctl) notes                    -> reads the global todo/notes list (Markdown).
          \(ctl) note-add --text "<todo>" -> appends a new todo (- [ ] …) to the list.
          \(ctl) notes-set --text "<md>"  -> replaces the whole list (Markdown, checkboxes - [ ]/- [x]).

        The todo/notes list is the central, overarching list that the user also sees in the
        sidebar. Maintain it proactively: add open points as `- [ ]` and check off
        finished ones as `- [x]`, so the user does not have to keep it themselves.

        Profiles: "Claude Code", "Codex (OpenAI)", "Gemini CLI", "Aider", "Shell".
        Any CLI: spawn --command "<cmd>" --dir <folder>.

        How to work: when the user asks you to start/monitor/control sessions, use these commands
        and summarize the state via `list`. Do NOT spawn many sessions unprompted; ask when in doubt.
        You are a session yourself (profile "Manager") — do not close yourself.
        """
        let path = NSTemporaryDirectory() + "barycenter-manager-prompt.txt"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// Close a session — with a confirmation prompt if the process is running or notes exist.
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

    /// Set a session's status (from hooks/bell). On "attention": sound + Dock bounce.
    func setStatus(_ status: SessionStatus, for id: UUID) {
        guard let s = sessions.first(where: { $0.id == id }), s.status != status else { return }
        s.status = status
        if status == .attention, AppSettings.shared.notificationsEnabled {
            AppSettings.shared.playNotificationSound()          // chosen tone (or silent if "off")
            NSApp.requestUserAttention(.informationalRequest)   // Dock bounce
            Notifier.attention(sessionTitle: s.title)           // macOS banner (only as .app)
        }
        post(.sessionsChanged)
    }

    func select(_ id: UUID) {
        selectedID = id
        // Clear attention when viewing.
        var cleared = false
        if let s = sessions.first(where: { $0.id == id }), s.status == .attention {
            s.status = .running
            cleared = true
        }
        // In the grid, automatically jump to the session's page (e.g. to get back to page 1).
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
        if s.isManager { managerWasRunning = false }   // don't auto-start it next launch
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
