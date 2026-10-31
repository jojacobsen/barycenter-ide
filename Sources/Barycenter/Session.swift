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
    /// Fired when the terminal is clicked -> select its tile.
    var onFocus: (() -> Void)?
    override func bell(source: Terminal) {
        // No super.bell -> we handle sound/attention centrally in SessionManager.
        onBell?()
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onFocus?()
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
    let resume: Bool                  // Claude started with --continue (resume last conversation)?
    let isManager: Bool               // the AI manager?
    let extraArgs: [String]           // extra claude arguments (e.g. --append-system-prompt-file)
    let startedAt = Date()
    var notes = ""                    // scratchpad, stays until closed
    var statusFilePath: String?       // Claude statusLine JSON (model/cost/context)
    let terminalView: BarycenterTerminalView

    /// PID of the child process (= Claude PID thanks to exec) — for matching with `claude agents --json`.
    var pid: Int32 { terminalView.process?.shellPid ?? 0 }

    init(title: String, cwd: String, launchCommand: String?, profileName: String,
         remoteControl: Bool = false, resume: Bool = false, isManager: Bool = false, extraArgs: [String] = []) {
        self.title = title
        self.cwd = cwd
        self.launchCommand = launchCommand
        self.profileName = profileName
        self.remoteControl = remoteControl
        self.resume = resume
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
            // Claude sessions have real hooks (Stop/Notification/UserPromptSubmit) for
            // attention — Claude Code also rings the bell WHILE working, which would
            // wrongly flag a busy session. So the bell heuristic is for other CLIs only.
            guard self.launchCommand != "claude" else { return }
            DispatchQueue.main.async {
                // Only report when the session is NOT currently being viewed.
                if SessionManager.shared.selectedID != self.id {
                    SessionManager.shared.setStatus(.attention, for: self.id)
                }
            }
        }

        terminalView.onFocus = { [weak self] in
            guard let self else { return }
            // Clicking into the terminal selects its tile (so typing lands here).
            if SessionManager.shared.selectedID != self.id {
                SessionManager.shared.select(self.id)
            }
        }
    }

    func start() {
        var inner = launchCommand
        // Claude Code: inject per-session hooks + statusLine (without touching the global config).
        if launchCommand == "claude", let path = AttentionCenter.shared.writeClaudeHookSettings(sessionID: id) {
            inner = "claude --settings \(shellQuote(path))"
            if resume { inner! += " --continue" }   // resume last conversation, hooks stay injected
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

    /// The single status shown everywhere — sidebar dot/pill, tile border and status
    /// page — so the frame, the dot and the label can never disagree. It merges the
    /// hook/bell state with Claude's live `agents --json` status.
    struct DisplayState { let text: String; let color: NSColor; let needsYou: Bool }

    var displayState: DisplayState {
        // A finished process wins over any stale live info.
        if status == .done { return DisplayState(text: L("beendet"), color: .systemGray, needsYou: false) }

        // Claude with live status from `claude agents --json`.
        if launchCommand == "claude", let a = AgentsMonitor.shared.info(forPID: pid) {
            switch a.status {
            case "busy":
                return DisplayState(text: L("arbeitet"), color: .systemGreen, needsYou: false)
            case "waiting":
                return DisplayState(text: L("wartet") + (a.waitingFor.map { ": \($0)" } ?? ""),
                                    color: .systemRed, needsYou: true)
            default: // "idle": not actively working
                // A Stop/Notification hook flagged this as "your turn" and you haven't
                // looked yet -> keep it red instead of a muted (and misleading) "bereit".
                if status == .attention {
                    return DisplayState(text: L("braucht dich"), color: .systemRed, needsYou: true)
                }
                return DisplayState(text: L("bereit"), color: .systemGray, needsYou: false)
            }
        }

        // Non-Claude sessions (shells, other agents), or Claude not matched yet: the enum.
        switch status {
        case .running:   return DisplayState(text: L("läuft"), color: .systemGreen, needsYou: false)
        case .attention: return DisplayState(text: L("braucht dich"), color: .systemRed, needsYou: true)
        case .done:      return DisplayState(text: L("beendet"), color: .systemGray, needsYou: false)
        case .idle:      return DisplayState(text: L("wartet"), color: .systemYellow, needsYou: false)
        }
    }

    /// "Needs you" for the Dock & menu bar — derived from the single display state.
    var needsAttention: Bool { displayState.needsYou }

    /// Status-dot color for the menu-bar menu.
    var menuStatusColor: NSColor { displayState.color }

    /// Short status text for the menu-bar menu.
    var menuStatusText: String { displayState.text }

    /// Color-coded labels for the sidebar: the single live status + Manager/RC badges.
    func statusBadges() -> [SessionBadge] {
        var out: [SessionBadge] = []
        if isManager { out.append(SessionBadge(text: L("Manager"), color: .systemPurple)) }
        let st = displayState
        out.append(SessionBadge(text: st.text, color: st.color))
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
