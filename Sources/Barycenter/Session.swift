import AppKit
import SwiftTerm

/// Status of a session. Colors drive the sidebar dot + tile border.
enum SessionStatus {
    case running    // working / running
    case attention  // needs you (hooks / bell)
    case done       // process finished
    case idle       // waiting

    var color: NSColor {
        switch self {
        case .running:   return .systemGreen
        case .attention: return .systemRed
        case .done:      return .systemGray
        case .idle:      return .systemYellow
        }
    }
}

/// A color-coded status label for the sidebar/status page.
struct SessionBadge { let text: String; let color: NSColor }

/// Terminal view that intercepts the bell (`\a`) — a heuristic for "needs you"
/// on non-Claude sessions (shells, other agents).
final class BarycenterTerminalView: LocalProcessTerminalView {
    var onBell: (() -> Void)?
    override func bell(source: Terminal) {
        // No super.bell -> we handle sound/attention centrally in SessionManager.
        onBell?()
    }
}

/// A session = one process in its own PTY. `launchCommand == nil` => login shell.
final class Session: NSObject, LocalProcessTerminalViewDelegate {
    let id = UUID()
    var title: String
    var status: SessionStatus = .running
    let cwd: String
    let launchCommand: String?
    let profileName: String
    let remoteControl: Bool           // Claude started with --remote-control?
    let isManager: Bool               // the AI manager?
    let extraArgs: [String]           // extra claude arguments (e.g. --append-system-prompt-file)
    let startedAt = Date()
    var notes = ""                    // scratchpad, stays until closed
    var statusFilePath: String?       // Claude statusLine JSON (model/cost/context)
    let terminalView: BarycenterTerminalView

    /// PID of the child process (= Claude PID thanks to exec) — for matching with `claude agents --json`.
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
        AppSettings.shared.apply(to: terminalView)   // theme + font
        if isManager {
            // Compact font for the narrow control-center area -> more columns/rows.
            terminalView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        }

        terminalView.onBell = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                // Only report when the session is NOT currently being viewed.
                if SessionManager.shared.selectedID != self.id {
                    SessionManager.shared.setStatus(.attention, for: self.id)
                }
            }
        }
    }

    func start() {
        var inner = launchCommand
        // Claude Code: inject per-session hooks + statusLine (without touching the global config).
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

    /// Current terminal content (scrollback) as text — the last `maxLines` lines.
    /// Reads the SwiftTerm buffer directly; this lets the manager "see" what a session is doing.
    func terminalText(maxLines: Int = 200) -> String {
        let data = terminalView.getTerminal().getBufferAsData(kind: .active)
        let full = String(data: data, encoding: .utf8) ?? ""
        var lines = full.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        if maxLines > 0, lines.count > maxLines { lines = Array(lines.suffix(maxLines)) }
        return lines.joined(separator: "\n")
    }

    /// Read the current statusLine JSON (model/cost/context), if present.
    func readStatusJSON() -> [String: Any]? {
        guard let p = statusFilePath, let data = FileManager.default.contents(atPath: p),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    /// "Needs you" state for the Dock & menu bar: a hook/bell reported attention,
    /// or Claude is live-waiting on you (approval/prompt).
    var needsAttention: Bool {
        if status == .attention { return true }
        if launchCommand == "claude", let a = AgentsMonitor.shared.info(forPID: pid) {
            return a.status == "waiting"
        }
        return false
    }

    /// Status-dot color for the menu-bar menu (live status preferred).
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

    /// Short status text for the menu-bar menu.
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

    /// Color-coded labels for the sidebar: live status (+ reason) and an optional RC badge.
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
