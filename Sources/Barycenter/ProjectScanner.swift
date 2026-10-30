import Foundation

/// A discovered project folder with its "last active" time — powers the quick
/// project picker in the New Session sheet so paths need not be typed by hand.
struct RecentProject {
    let name: String
    let path: String
    let lastActive: Date
    let hasClaudeHistory: Bool
}

/// Finds recently used projects by scanning the usual project roots
/// (~/Projects, ~/dev, …) and deriving "last active" from the folder's own
/// modification date plus Claude Code's transcript store
/// (`~/.claude/projects/<path with "/" replaced by "-">`).
enum ProjectScanner {
    /// Project roots that actually exist.
    static func roots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Projects", "WebstormProjects", "dev", "code", "src", "repos", "git"]
            .map { home.appendingPathComponent($0) }
            .filter { isDir($0.path) }
    }

    /// Recently used projects, most-recently-active first (at most `limit`).
    static func recent(limit: Int = 24) -> [RecentProject] {
        let fm = FileManager.default
        let claudeDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        var out: [RecentProject] = []
        var seen = Set<String>()

        for root in roots() {
            let entries = (try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for url in entries {
                let path = url.path
                guard isDir(path), seen.insert(path).inserted else { continue }
                let (date, claude) = activity(path: path, claudeDir: claudeDir)
                out.append(RecentProject(name: url.lastPathComponent, path: path,
                                         lastActive: date, hasClaudeHistory: claude))
            }
        }
        out.sort { $0.lastActive > $1.lastActive }
        return Array(out.prefix(limit))
    }

    /// "Last active" = newest of the folder's mtime and its Claude transcript files.
    private static func activity(path: String, claudeDir: URL) -> (Date, Bool) {
        let fm = FileManager.default
        var best = Date.distantPast
        if let m = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date {
            best = m
        }
        // Claude stores one folder per working directory: path with "/" turned into "-".
        let sanitized = path.replacingOccurrences(of: "/", with: "-")
        let dir = claudeDir.appendingPathComponent(sanitized)
        var hasClaude = false
        if let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []),
           !files.isEmpty {
            hasClaude = true
            for f in files {
                if let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate, m > best { best = m }
            }
        }
        return (best, hasClaude)
    }
}

/// Is the path a directory?
func isDir(_ path: String) -> Bool {
    var d: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
}

/// Compact, language-neutral relative time (e.g. "now", "3m", "2h", "4d", "3w").
func shortRelTime(_ date: Date) -> String {
    if date == .distantPast { return "—" }
    let s = max(0, -date.timeIntervalSinceNow)
    switch s {
    case ..<60:          return "now"
    case ..<3600:        return "\(Int(s / 60))m"
    case ..<86400:       return "\(Int(s / 3600))h"
    case ..<(7*86400):   return "\(Int(s / 86400))d"
    case ..<(30*86400):  return "\(Int(s / (7*86400)))w"
    case ..<(365*86400): return "\(Int(s / (30*86400)))mo"
    default:             return "\(Int(s / (365*86400)))y"
    }
}
