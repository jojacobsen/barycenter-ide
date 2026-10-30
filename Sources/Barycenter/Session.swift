import AppKit
import SwiftTerm

/// Status einer Session. Farben steuern Sidebar-Punkt + Kachel-Rahmen.
enum SessionStatus {
    case running    // arbeitet / läuft
    case attention  // braucht dich (Hooks / Bell)
    case done       // Prozess beendet
    case idle       // wartet

    var color: NSColor {
        switch self {
        case .running:   return .systemGreen
        case .attention: return .systemRed
        case .done:      return .systemGray
        case .idle:      return .systemYellow
        }
    }
}

/// Ein color-coded Status-Label für Sidebar/Status-Seite.
struct SessionBadge { let text: String; let color: NSColor }

/// Terminal-View, das den Bell (`\a`) abfängt — Heuristik für „braucht dich"
/// bei Nicht-Claude-Sessions (Shells, andere Agents).
final class BarycenterTerminalView: LocalProcessTerminalView {
    var onBell: (() -> Void)?
    override func bell(source: Terminal) {
        // Kein super.bell -> Sound/Attention steuern wir zentral in SessionManager.
        onBell?()
    }
}

/// Eine Session = ein Prozess in eigenem PTY. `launchCommand == nil` => Login-Shell.
final class Session: NSObject, LocalProcessTerminalViewDelegate {
    let id = UUID()
    var title: String
    var status: SessionStatus = .running
    let cwd: String
    let launchCommand: String?
    let profileName: String
    let remoteControl: Bool           // Claude mit --remote-control gestartet?
    let isManager: Bool               // der KI-Verwalter?
    let extraArgs: [String]           // zusätzliche claude-Argumente (z.B. --append-system-prompt-file)
    let startedAt = Date()
    var notes = ""                    // Scratchpad, bleibt bis zum Schließen
    var statusFilePath: String?       // Claude-statusLine-JSON (Modell/Kosten/Context)
    let terminalView: BarycenterTerminalView

    /// PID des Kind-Prozesses (= Claude-PID dank exec) — für Matching mit `claude agents --json`.
    var pid: Int32 { terminalView.process?.shellPid ?? 0 }

    init(title: String, cwd: String, launchCommand: String?, profileName: String,
         remoteControl: Bool = false, isManager: Bool = false, extraArgs: [String] = []) {
        self.title = title
        self.cwd = cwd
        self.launchCommand = launchCommand
        self.profileName = profileName
        self.remoteControl = remoteControl
        self.isManager = isManager
        self.extraArgs = extraArgs
        self.terminalView = BarycenterTerminalView(frame: NSRect(x: 0, y: 0, width: 720, height: 460))
        super.init()
        terminalView.processDelegate = self
        AppSettings.shared.apply(to: terminalView)   // Theme + Schrift
        if isManager {
            // Kompakte Schrift für den schmalen Leitstellen-Bereich -> mehr Spalten/Zeilen.
            terminalView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        }

        terminalView.onBell = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                // Nur melden, wenn die Session gerade NICHT betrachtet wird.
                if SessionManager.shared.selectedID != self.id {
                    SessionManager.shared.setStatus(.attention, for: self.id)
                }
            }
        }
    }

    func start() {
        var inner = launchCommand
        // Claude Code: per-Session Hooks + statusLine injizieren (ohne globale Config anzufassen).
        if launchCommand == "claude", let path = AttentionCenter.shared.writeClaudeHookSettings(sessionID: id) {
            inner = "claude --settings \(shellQuote(path))"
            if remoteControl { inner! += " --remote-control" }
            for a in extraArgs { inner! += " " + shellQuote(a) }
            statusFilePath = AttentionCenter.shared.statusFilePath(for: id)
        }
        let (exe, args) = Profile.launchSpec(command: inner)
        terminalView.startProcess(executable: exe, args: args,
                                  environment: childEnvironment(), currentDirectory: cwd)
    }

    func terminate() { terminalView.process?.terminate() }

    /// Aktueller Terminal-Inhalt (Scrollback) als Text — die letzten `maxLines` Zeilen.
    /// Liest direkt den SwiftTerm-Puffer; damit „sieht" der Verwalter, was eine Session tut.
    func terminalText(maxLines: Int = 200) -> String {
        let data = terminalView.getTerminal().getBufferAsData(kind: .active)
        let full = String(data: data, encoding: .utf8) ?? ""
        var lines = full.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        if maxLines > 0, lines.count > maxLines { lines = Array(lines.suffix(maxLines)) }
        return lines.joined(separator: "\n")
    }

    /// Aktuelles statusLine-JSON (Modell/Kosten/Context) lesen, falls vorhanden.
    func readStatusJSON() -> [String: Any]? {
        guard let p = statusFilePath, let data = FileManager.default.contents(atPath: p),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    /// „Braucht dich"-Zustand für Dock & Menüleiste: Hook/Bell meldete attention,
    /// oder Claude wartet live auf dich (Freigabe/Prompt).
    var needsAttention: Bool {
        if status == .attention { return true }
        if launchCommand == "claude", let a = AgentsMonitor.shared.info(forPID: pid) {
            return a.status == "waiting"
        }
        return false
    }

    /// Statuspunkt-Farbe fürs Menüleisten-Menü (Live-Status bevorzugt).
    var menuStatusColor: NSColor {
        if launchCommand == "claude", let a = AgentsMonitor.shared.info(forPID: pid) {
            switch a.status {
            case "busy":    return .systemGreen
            case "waiting": return .systemRed
            default:        return .systemGray
            }
        }
        return status.color
    }

    /// Kurzer Statustext fürs Menüleisten-Menü.
    var menuStatusText: String {
        if launchCommand == "claude", let a = AgentsMonitor.shared.info(forPID: pid) {
            switch a.status {
            case "busy":    return L("arbeitet")
            case "waiting": return L("wartet") + (a.waitingFor.map { ": \($0)" } ?? "")
            case "idle":    return L("bereit")
            default:        return a.status
            }
        }
        switch status {
        case .running:   return L("läuft")
        case .attention: return L("braucht dich")
        case .done:      return L("beendet")
        case .idle:      return L("wartet")
        }
    }

    /// Color-coded Labels für die Sidebar: Live-Status (+ Grund) und ggf. RC-Badge.
    func statusBadges() -> [SessionBadge] {
        var out: [SessionBadge] = []
        if isManager { out.append(SessionBadge(text: L("Manager"), color: .systemPurple)) }
        if launchCommand == "claude", let a = AgentsMonitor.shared.info(forPID: pid) {
            switch a.status {
            case "busy":    out.append(SessionBadge(text: L("arbeitet"), color: .systemGreen))
            case "waiting": out.append(SessionBadge(text: L("wartet") + (a.waitingFor.map { ": \($0)" } ?? ""), color: .systemRed))
            case "idle":    out.append(SessionBadge(text: L("bereit"), color: .systemGray))
            default:        out.append(SessionBadge(text: a.status, color: .systemGray))
            }
        } else {
            switch status {
            case .running:   out.append(SessionBadge(text: L("läuft"), color: .systemGreen))
            case .attention: out.append(SessionBadge(text: L("braucht dich"), color: .systemRed))
            case .done:      out.append(SessionBadge(text: L("beendet"), color: .systemGray))
            case .idle:      out.append(SessionBadge(text: L("wartet"), color: .systemYellow))
            }
        }
        if remoteControl { out.append(SessionBadge(text: "RC", color: .systemBlue)) }
        return out
    }

    // MARK: - LocalProcessTerminalViewDelegate
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        status = .done
        NotificationCenter.default.post(name: .sessionsChanged, object: nil)
    }
}
