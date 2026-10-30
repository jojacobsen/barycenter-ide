import Foundation

/// How a project was last started, so the New Session sheet can pre-fill it.
struct LastLaunch {
    let profileName: String
    let launchCommand: String?
    let remoteControl: Bool
}

/// Remembers, per working directory, how the last session there was launched
/// (profile / command / remote-control). Persisted in UserDefaults so the next
/// "New Session" for that folder needs no manual re-entry.
enum LaunchMemory {
    private static let key = "launchMemory"
    private static var d: UserDefaults { .standard }

    /// Record how a session in `cwd` was started (ignores the AI manager).
    static func remember(cwd: String, profileName: String, launchCommand: String?, remoteControl: Bool) {
        var all = d.dictionary(forKey: key) as? [String: [String: Any]] ?? [:]
        all[cwd] = [
            "profile": profileName,
            "command": launchCommand ?? "",
            "rc": remoteControl,
        ]
        d.set(all, forKey: key)
    }

    /// The most recent launch recorded for `cwd`, if any.
    static func last(for cwd: String) -> LastLaunch? {
        guard let all = d.dictionary(forKey: key) as? [String: [String: Any]],
              let e = all[cwd] else { return nil }
        let cmd = e["command"] as? String
        return LastLaunch(profileName: e["profile"] as? String ?? "Shell",
                          launchCommand: (cmd?.isEmpty ?? true) ? nil : cmd,
                          remoteControl: e["rc"] as? Bool ?? false)
    }
}
