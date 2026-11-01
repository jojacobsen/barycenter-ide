import Foundation

extension Notification.Name {
    /// The global notes/todo file changed (edited here, by the AI manager, or externally).
    static let notesChanged = Notification.Name("BarycenterNotesChanged")
}

/// The global "overarching" notes, kept as a Markdown file so the AI manager (Leitstelle)
/// and the user edit the very same todo list. Backed by
/// `~/Library/Application Support/Barycenter/notes.md`, watched for external changes.
final class NotesStore {
    static let shared = NotesStore()

    private let q = DispatchQueue(label: "barycenter.notes", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    /// The Markdown file (directory shared with the project-status cache).
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Barycenter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.md")
    }

    private init() {
        migrateFromUserDefaultsIfNeeded()
        startWatching()
    }

    // MARK: - Read / write

    func read() -> String {
        (try? String(contentsOf: Self.fileURL, encoding: .utf8)) ?? ""
    }

    /// Write new content. `notify` posts `.notesChanged` immediately (so the UI that
    /// triggered the write updates without waiting for the file watcher).
    func write(_ text: String, notify: Bool = true) {
        try? text.write(to: Self.fileURL, atomically: true, encoding: .utf8)
        if notify { postChanged() }
    }

    /// Append a todo line (`- [ ] …`) to the end of the list.
    func addTodo(_ text: String) {
        var current = read()
        if !current.isEmpty && !current.hasSuffix("\n") { current += "\n" }
        current += "- [ ] " + text + "\n"
        write(current)
    }

    /// Flip the n-th task-list checkbox (0-based, in document order). The ordering
    /// matches how marked.js renders checkboxes (fenced code skipped, ordered and
    /// bulleted list markers both recognized), so a click maps to the right line.
    func toggleTask(at index: Int) {
        var out = read().components(separatedBy: "\n")
        let tasks = Self.taskLineIndices(in: out)
        guard index >= 0, index < tasks.count else { return }
        let i = tasks[index]
        guard let box = Self.taskBoxRange(in: out[i]) else { return }
        let line = out[i]
        let checked = line[box].lowercased() == "x"
        var chars = Array(line)
        chars[line.distance(from: line.startIndex, to: box.lowerBound)] = checked ? " " : "x"
        out[i] = String(chars)
        write(out.joined(separator: "\n"))
    }

    /// Indices of the lines that render as task-list checkboxes, in document order,
    /// skipping fenced code blocks (``` / ~~~) — mirrors marked.js's task list.
    static func taskLineIndices(in lines: [String]) -> [Int] {
        var result: [Int] = []
        var inFence = false
        var fence: Character = "`"
        for (i, line) in lines.enumerated() {
            let t = line.drop { $0 == " " || $0 == "\t" }
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                let marker = t.first!
                if !inFence { inFence = true; fence = marker }
                else if marker == fence { inFence = false }
                continue
            }
            if inFence { continue }
            if taskBoxRange(in: line) != nil { result.append(i) }
        }
        return result
    }

    /// Range of the single character inside `[ ]` / `[x]` for a task-list line, else nil.
    /// Accepts an indent, a bullet (`-`/`*`/`+`) or an ordered marker (`1.` / `2)`),
    /// whitespace, then `[ ]` / `[x]` / `[X]`.
    static func taskBoxRange(in line: String) -> Range<String.Index>? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard let first = trimmed.first else { return nil }
        var idx: Substring.Index
        if first == "-" || first == "*" || first == "+" {
            idx = trimmed.index(after: trimmed.startIndex)
        } else if first.isNumber {
            // ordered list: one or more digits, then '.' or ')'
            var j = trimmed.startIndex
            while j < trimmed.endIndex, trimmed[j].isNumber { j = trimmed.index(after: j) }
            guard j < trimmed.endIndex, trimmed[j] == "." || trimmed[j] == ")" else { return nil }
            idx = trimmed.index(after: j)
        } else {
            return nil
        }
        // require at least one space after the marker
        guard idx < trimmed.endIndex, trimmed[idx] == " " else { return nil }
        while idx < trimmed.endIndex, trimmed[idx] == " " { idx = trimmed.index(after: idx) }
        guard idx < trimmed.endIndex, trimmed[idx] == "[" else { return nil }
        let boxChar = trimmed.index(after: idx)
        guard boxChar < trimmed.endIndex else { return nil }
        let closing = trimmed.index(after: boxChar)
        guard closing < trimmed.endIndex, trimmed[closing] == "]" else { return nil }
        let c = trimmed[boxChar]
        guard c == " " || c == "x" || c == "X" else { return nil }
        return boxChar..<trimmed.index(after: boxChar)
    }

    // MARK: - Watching

    private func startWatching() {
        // Ensure the file exists so we can open an fd on it.
        if !FileManager.default.fileExists(atPath: Self.fileURL.path) {
            write("", notify: false)
        }
        q.async { [weak self] in self?.arm() }
    }

    private func arm() {
        source?.cancel()
        fd = open(Self.fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: q)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            // Atomic writes replace the inode -> re-arm on the new file, then notify.
            self.q.asyncAfter(deadline: .now() + 0.15) { self.arm() }
            self.postChanged()
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd); self?.fd = -1 }
        }
        source = src
        src.resume()
    }

    private func postChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .notesChanged, object: nil)
        }
    }

    // MARK: - Migration

    private func migrateFromUserDefaultsIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: Self.fileURL.path) else { return }
        let old = UserDefaults.standard.string(forKey: "sidebarNotes") ?? ""
        try? old.write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }
}
