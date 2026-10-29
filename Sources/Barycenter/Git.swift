import Foundation

/// Kleiner Git-Helfer (ruft /usr/bin/git auf).
enum Git {
    @discardableResult
    static func run(_ args: [String], cwd: String? = nil) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = (cwd.map { ["-C", $0] } ?? []) + args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice   // Fehler NICHT in die Ausgabe mischen
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func isRepo(_ cwd: String) -> Bool {
        run(["rev-parse", "--is-inside-work-tree"], cwd: cwd)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// Top-Level-Verzeichnis des Repos (für Worktree-Anlage), oder nil.
    static func topLevel(_ cwd: String) -> String? {
        let s = run(["rev-parse", "--show-toplevel"], cwd: cwd).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix("/") ? s : nil   // nur echte Pfade (kein Fehlertext)
    }

    /// Legt für `folder` (muss in einem Git-Repo liegen) einen neuen Worktree + Branch an.
    /// Gibt den Worktree-Pfad zurück, oder nil bei Fehler/kein Repo.
    static func makeWorktree(in folder: String, name: String) -> String? {
        guard let repo = topLevel(folder) else { return nil }
        let repoName = (repo as NSString).lastPathComponent
        let short = String(UUID().uuidString.prefix(6)).lowercased()
        let safe = name.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let branch = "barycenter/\(safe)-\(short)"
        let base = (NSHomeDirectory() as NSString).appendingPathComponent(".barycenter-worktrees")
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        let wt = (base as NSString).appendingPathComponent("\(repoName)-\(short)")
        _ = run(["worktree", "add", "-b", branch, wt], cwd: repo)
        return FileManager.default.fileExists(atPath: wt) ? wt : nil
    }
}
