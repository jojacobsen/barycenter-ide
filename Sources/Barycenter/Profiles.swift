import Foundation

/// A session profile = what gets started when spawning.
/// `command == nil` => a plain interactive login shell.
struct Profile {
    let name: String
    let command: String?

    static let customName = L("Custom Command…")

    static let builtins: [Profile] = [
        Profile(name: "Claude Code",    command: "claude"),
        Profile(name: "Codex (OpenAI)", command: "codex"),
        Profile(name: "Gemini CLI",     command: "gemini"),
        Profile(name: "Aider",          command: "aider"),
        Profile(name: "Shell",          command: nil),
    ]

    /// executable + args for SwiftTerm.
    /// Agents are exec'd through a login/interactive shell so that PATH & rc
    /// are loaded (so the shell finds `claude`, `codex`, … like your terminal does).
    static func launchSpec(command: String?) -> (String, [String]) {
        if let c = command, !c.trimmingCharacters(in: .whitespaces).isEmpty {
            // Login shell (without -i: no logout noise) loads PATH/rc, then execs the agent.
            return ("/bin/zsh", ["-l", "-c", "exec " + c])
        }
        return ("/bin/zsh", ["-l"])
    }
}

/// Safely quote a path/arg for the shell (single quotes).
func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Pass the full environment of the Barycenter process through to the child
/// (incl. PATH), plus terminal variables.
func childEnvironment() -> [String] {
    var env = ProcessInfo.processInfo.environment
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
    return env.map { "\($0)=\($1)" }
}
