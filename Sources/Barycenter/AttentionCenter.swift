import Foundation

/// Lokaler Event-Kanal für „Session braucht Aufmerksamkeit".
/// Claude-Code-Sessions bekommen per `--settings` Hooks injiziert, die in eine
/// Append-Datei schreiben (`<id> attention` / `<id> running`). Barycenter beobachtet
/// die Datei und aktualisiert den Session-Status. Append-Datei statt FIFO, damit
/// ein Hook niemals blockiert, falls Barycenter mal nicht lauscht.
final class AttentionCenter {
    static let shared = AttentionCenter()

    private let runtimeDir: URL
    private let eventsURL: URL
    private var evtFD: Int32 = -1
    private var readFD: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var offset: off_t = 0

    private init() {
        runtimeDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("barycenter-\(ProcessInfo.processInfo.processIdentifier)")
        eventsURL = runtimeDir.appendingPathComponent("events.log")
    }

    func start() {
        try? FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: eventsURL.path, contents: nil)

        readFD = open(eventsURL.path, O_RDONLY)
        evtFD = open(eventsURL.path, O_EVTONLY)
        guard evtFD >= 0, readFD >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: evtFD, eventMask: [.write, .extend], queue: .global())
        src.setEventHandler { [weak self] in self?.drain() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.evtFD, fd >= 0 { close(fd) }
            if let fd = self?.readFD, fd >= 0 { close(fd) }
        }
        source = src
        src.resume()
        drain()
    }

    private func drain() {
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buf.withUnsafeMutableBytes { pread(readFD, $0.baseAddress, $0.count, offset) }
            if n <= 0 { break }
            offset += off_t(n)
            if let s = String(bytes: buf[0 ..< n], encoding: .utf8) {
                for line in s.split(separator: "\n") { handle(String(line)) }
            }
            if n < buf.count { break }
        }
    }

    private func handle(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])) else { return }
        let status: SessionStatus = (String(parts[1]) == "running") ? .running : .attention
        DispatchQueue.main.async { SessionManager.shared.setStatus(status, for: id) }
    }

    /// Pfad der per-Session statusLine-JSON-Datei (Modell/Kosten/Context).
    func statusFilePath(for id: UUID) -> String {
        runtimeDir.appendingPathComponent("\(id.uuidString).status.json").path
    }

    /// Schreibt per-Session-Hook-Settings (+ statusLine) für Claude Code und gibt den Dateipfad zurück.
    func writeClaudeHookSettings(sessionID: UUID) -> String? {
        let path = runtimeDir.appendingPathComponent("\(sessionID.uuidString).json")
        let events = shellQuote(eventsURL.path)
        func hook(_ ev: String) -> [String: Any] {
            ["hooks": [["type": "command",
                        "command": "echo '\(sessionID.uuidString) \(ev)' >> \(events)"]]]
        }
        let settings: [String: Any] = [
            "hooks": [
                "Notification":     [hook("attention")],  // wartet auf dich / Freigabe
                "Stop":             [hook("attention")],  // Zug fertig -> bereit für dich
                "UserPromptSubmit": [hook("running")],     // du hast getippt -> arbeitet wieder
            ],
            // statusLine schreibt das Status-JSON in die Datei (stdout bleibt leer).
            "statusLine": [
                "type": "command",
                "command": "cat > \(shellQuote(statusFilePath(for: sessionID)))",
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted]),
              (try? data.write(to: path)) != nil else { return nil }
        return path.path
    }
}
