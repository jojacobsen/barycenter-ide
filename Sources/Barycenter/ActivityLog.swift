import AppKit

/// Per-session activity timeline. Claude sessions append one line per hook event
/// (prompt / tool call / waiting / turn done) via injected hooks; Barycenter itself
/// appends start / exit / bell, so plain shells and other CLIs get a minimal
/// timeline too. Line format: `<unix-seconds>\t<hook JSON, newlines stripped, cut>`.
enum ActivityLog {
    enum Kind { case started, prompt, tool, waiting, done, exited, bell }

    struct Event {
        let date: Date
        let kind: Kind
        let label: String
        let detail: String
        var count = 1            // consecutive identical events are collapsed
    }

    /// Longest hook payload kept per line; tool inputs (e.g. a Write's file
    /// content) can be huge, and only the leading fields are shown anyway.
    static let maxLineChars = 3000

    static func path(for id: UUID) -> String { AttentionCenter.shared.activityFilePath(for: id) }

    /// Shell snippet for a Claude hook: reads the hook JSON from stdin and appends it
    /// as one timestamped line in a single write, so parallel tool calls don't interleave.
    static func hookCommand(for id: UUID) -> String {
        let file = shellQuote(path(for: id))
        return "l=$(tr -d '\\n' | cut -c1-\(maxLineChars)); printf '%s\\t%s\\n' \"$(date +%s)\" \"$l\" >> \(file)"
    }

    /// Append an event written by Barycenter itself (start / exit / bell).
    static func append(_ id: UUID, event: String, _ extra: [String: Any] = [:]) {
        var obj = extra
        obj["hook_event_name"] = event
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let json = String(data: data, encoding: .utf8) else { return }
        let line = "\(Int(Date().timeIntervalSince1970))\t\(json)\n"
        let p = path(for: id)
        if let h = FileHandle(forWritingAtPath: p) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            FileManager.default.createFile(atPath: p, contents: Data(line.utf8))
        }
    }

    /// Carry the history over when a session is restarted under a new id.
    static func transfer(from old: UUID, to new: UUID) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path(for: old)) else { return }
        try? fm.removeItem(atPath: path(for: new))
        try? fm.moveItem(atPath: path(for: old), toPath: path(for: new))
    }

    /// Size of the log file, to cheaply detect changes before re-reading it.
    static func size(for id: UUID) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: path(for: id)))?[.size] as? UInt64) ?? 0
    }

    /// Parsed events, newest first, with consecutive duplicates collapsed.
    static func events(for session: Session, limit: Int = 300) -> [Event] {
        guard let data = FileManager.default.contents(atPath: path(for: session.id)) else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        var out: [Event] = []
        for line in text.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t"),
                  let ts = Double(line[..<tab]) else { continue }
            let raw = String(line[line.index(after: tab)...])
            guard let e = parse(raw, date: Date(timeIntervalSince1970: ts), cwd: session.cwd) else { continue }
            if let last = out.last, last.kind == e.kind, last.label == e.label, last.detail == e.detail {
                out[out.count - 1].count += 1
            } else {
                out.append(e)
            }
        }
        return Array(out.suffix(limit).reversed())
    }

    // MARK: Parsing

    private static func parse(_ raw: String, date: Date, cwd: String) -> Event? {
        guard let name = field("hook_event_name", in: raw) else { return nil }
        switch name {
        case "UserPromptSubmit":
            return Event(date: date, kind: .prompt, label: L("Prompt"),
                         detail: oneLine(field("prompt", in: raw) ?? ""))
        case "PreToolUse":
            let tool = field("tool_name", in: raw) ?? "?"
            return Event(date: date, kind: .tool, label: toolLabel(tool),
                         detail: toolDetail(tool, raw: raw, cwd: cwd))
        case "Notification":
            return Event(date: date, kind: .waiting, label: L("Wartet"),
                         detail: oneLine(field("message", in: raw) ?? ""))
        case "Stop":
            return Event(date: date, kind: .done, label: L("Fertig"), detail: L("bereit für dich"))
        case "BarycenterStart":
            let resumed = raw.contains("\"resume\":true")
            return Event(date: date, kind: .started, label: L("Gestartet"),
                         detail: (field("profile", in: raw) ?? "") + (resumed ? " · " + L("fortgesetzt") : ""))
        case "BarycenterExit":
            let detail = field("code", in: raw).map { String(format: L("Exit-Code %@"), $0) } ?? ""
            return Event(date: date, kind: .exited, label: L("Beendet"), detail: detail)
        case "BarycenterBell":
            return Event(date: date, kind: .bell, label: L("Signal"), detail: L("Terminal-Glocke"))
        default:
            return nil
        }
    }

    private static func toolLabel(_ tool: String) -> String {
        // mcp__server__tool -> "server · tool"
        if tool.hasPrefix("mcp__") {
            let parts = tool.dropFirst(5).components(separatedBy: "__")
            return parts.joined(separator: " · ")
        }
        return tool
    }

    private static func toolDetail(_ tool: String, raw: String, cwd: String) -> String {
        switch tool {
        case "Bash":
            return oneLine(field("command", in: raw) ?? "")
        case "Read", "Write", "Edit", "MultiEdit", "NotebookEdit":
            let p = field("file_path", in: raw) ?? field("notebook_path", in: raw) ?? ""
            return relative(p, to: cwd)
        case "Grep", "Glob":
            return oneLine(field("pattern", in: raw) ?? "")
        case "WebFetch":
            return field("url", in: raw) ?? ""
        case "WebSearch":
            return oneLine(field("query", in: raw) ?? "")
        case "Task", "Agent":
            return oneLine(field("description", in: raw) ?? "")
        case "TodoWrite":
            return L("Todo-Liste aktualisiert")
        default:
            // Unknown/MCP tools: the first string value of the input is usually telling.
            return oneLine(firstInputString(raw) ?? "")
        }
    }

    private static func relative(_ p: String, to cwd: String) -> String {
        let base = cwd.hasSuffix("/") ? cwd : cwd + "/"
        return p.hasPrefix(base) ? String(p.dropFirst(base.count)) : p
    }

    private static func oneLine(_ s: String, max: Int = 160) -> String {
        let flat = s.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > max ? String(flat.prefix(max)) + "…" : flat
    }

    /// First string value of a JSON key anywhere in `raw`. Regex instead of a JSON
    /// parser because lines may be cut mid-object (see `maxLineChars`).
    static func field(_ key: String, in raw: String) -> String? {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*(\"((?:[^\"\\\\]|\\\\.)*)\"?|-?[0-9]+|true|false)"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
        if let r = Range(m.range(at: 2), in: raw) { return unescape(String(raw[r])) }
        if let r = Range(m.range(at: 1), in: raw) { return String(raw[r]) }
        return nil
    }

    private static func firstInputString(_ raw: String) -> String? {
        guard let r = raw.range(of: "\"tool_input\"") else { return nil }
        let rest = String(raw[r.upperBound...])
        let re = try? NSRegularExpression(pattern: "\"[^\"]+\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)")
        guard let m = re?.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
              let vr = Range(m.range(at: 1), in: rest) else { return nil }
        return unescape(String(rest[vr]))
    }

    private static func unescape(_ s: String) -> String {
        var body = s
        // A cut line can end inside an escape sequence; drop a dangling backslash.
        while body.hasSuffix("\\") && !body.hasSuffix("\\\\") { body.removeLast() }
        if let data = "\"\(body)\"".data(using: .utf8),
           let v = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String {
            return v
        }
        return s
    }

    // MARK: Rendering

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f
    }()

    static func timeString(_ d: Date) -> String {
        Calendar.current.isDateInToday(d)
            ? timeFmt.string(from: d)
            : dayFmt.string(from: d) + " " + timeFmt.string(from: d)
    }

    static func color(for kind: Kind) -> NSColor {
        switch kind {
        case .prompt:  return .controlAccentColor
        case .tool:    return .labelColor
        case .waiting: return .systemRed
        case .done:    return .secondaryLabelColor
        case .started: return .systemGreen
        case .exited:  return .secondaryLabelColor
        case .bell:    return .systemOrange
        }
    }

    /// Plain-text rendering for `baryctl activity` (newest first).
    static func plainText(_ events: [Event]) -> String {
        events.map { e in
            let n = e.count > 1 ? " ×\(e.count)" : ""
            return "\(timeString(e.date))  \(e.label)\(n)  \(e.detail)"
        }.joined(separator: "\n")
    }
}
