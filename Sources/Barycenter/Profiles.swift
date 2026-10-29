import Foundation

/// Ein Session-Profil = was beim Spawnen gestartet wird.
/// `command == nil` => reine interaktive Login-Shell.
struct Profile {
    let name: String
    let command: String?

    static let customName = "Custom Command…"

    static let builtins: [Profile] = [
        Profile(name: "Claude Code",    command: "claude"),
        Profile(name: "Codex (OpenAI)", command: "codex"),
        Profile(name: "Gemini CLI",     command: "gemini"),
        Profile(name: "Aider",          command: "aider"),
        Profile(name: "Shell",          command: nil),
    ]

    /// executable + args für SwiftTerm.
    /// Agents werden über eine Login-/Interactive-Shell ge-exec't, damit PATH & rc
    /// geladen sind (so findet die Shell `claude`, `codex`, … wie dein Terminal).
    static func launchSpec(command: String?) -> (String, [String]) {
        if let c = command, !c.trimmingCharacters(in: .whitespaces).isEmpty {
            // Login-Shell (ohne -i: kein Logout-Rauschen) lädt PATH/rc, dann exec auf den Agent.
            return ("/bin/zsh", ["-l", "-c", "exec " + c])
        }
        return ("/bin/zsh", ["-l"])
    }
}

/// Pfad/Arg für die Shell sicher quoten (einfache Anführungszeichen).
func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Vollständige Umgebung des Barycenter-Prozesses an das Kind weiterreichen
/// (inkl. PATH), plus Terminal-Variablen.
func childEnvironment() -> [String] {
    var env = ProcessInfo.processInfo.environment
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
    return env.map { "\($0)=\($1)" }
}
