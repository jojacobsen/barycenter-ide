import Foundation
import Darwin
import AppKit

/// Lokaler Kontroll-Kanal (Unix-Socket), über den der KI-Verwalter Barycenter steuert.
/// Protokoll: eine JSON-Zeile rein (`{"cmd":...}`), eine JSON-Zeile raus.
final class ControlServer {
    static let shared = ControlServer()

    let socketPath: String
    let baryctlPath: String
    private var listenFD: Int32 = -1

    private init() {
        let pid = ProcessInfo.processInfo.processIdentifier
        socketPath = "/tmp/barycenter-\(pid).sock"   // kurz halten (sun_path-Limit)
        baryctlPath = NSTemporaryDirectory() + "barycenter-\(pid)-baryctl"
    }

    func start() {
        writeBarycenterctl()

        unlink(socketPath)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: 104) { dst in _ = strcpy(dst, socketPath) }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, len) }
        }
        guard bound == 0, listen(listenFD, 8) == 0 else { close(listenFD); listenFD = -1; return }

        DispatchQueue.global(qos: .utility).async { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 { if errno == EINTR { continue } else { break } }
            handle(fd)
        }
    }

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !data.contains(0x0a) {       // bis zur ersten Zeile lesen (kein half-close nötig)
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
        }
        var result: [String: Any] = ["ok": false, "error": "bad request"]
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cmd = obj["cmd"] as? String {
            if cmd == "list" || cmd == "read" {
                // Lesend: synchron, da wir die Daten zurückgeben.
                DispatchQueue.main.sync { result = BarycenterControl.execute(cmd: cmd, args: obj) }
            } else {
                // Mutierend: auf Main async ausführen (wie der ＋-Button) -> Client nicht blockieren.
                DispatchQueue.main.async { _ = BarycenterControl.execute(cmd: cmd, args: obj) }
                result = ["ok": true, "queued": true]
                if let t = (obj["name"] ?? obj["title"]) as? String { result["title"] = t }
            }
        }
        var out = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{\"ok\":false}".utf8)
        out.append(0x0a)
        out.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
    }

    /// Erzeugt das `baryctl`-Skript (Socket-Pfad eingebacken) für den Manager.
    private func writeBarycenterctl() {
        let script = """
        #!/bin/bash
        # Von Barycenter generiert. Steuert Barycenter über den lokalen Socket.
        SOCK='\(socketPath)'
        python3 - "$@" <<'PY' | nc -U "$SOCK"
        import json,sys
        a=sys.argv[1:]
        if not a:
            print(json.dumps({"cmd":"list"})); sys.exit()
        d={"cmd":a[0]}; i=1
        while i<len(a):
            k=a[i]
            if k.startswith("--"):
                key=k[2:]
                if i+1<len(a) and not a[i+1].startswith("--"):
                    d[key]=a[i+1]; i+=2
                else:
                    d[key]=True; i+=1
            else:
                i+=1
        print(json.dumps(d))
        PY
        """
        try? script.write(toFile: baryctlPath, atomically: true, encoding: .utf8)
        chmod(baryctlPath, 0o755)
    }
}

/// Führt die Kommandos des Verwalters auf dem SessionManager aus (immer auf dem Main-Thread).
enum BarycenterControl {
    static func execute(cmd: String, args: [String: Any]) -> [String: Any] {
        let mgr = SessionManager.shared
        switch cmd {
        case "list":
            let arr: [[String: Any]] = mgr.sessions.map { s in
                var d: [String: Any] = [
                    "id": s.id.uuidString, "title": s.title, "profile": s.profileName,
                    "cwd": s.cwd, "remoteControl": s.remoteControl, "manager": s.isManager, "pid": Int(s.pid),
                ]
                if s.launchCommand == "claude", let a = AgentsMonitor.shared.info(forPID: s.pid) {
                    d["status"] = a.status
                    if let w = a.waitingFor { d["waitingFor"] = w }
                } else {
                    d["status"] = (s.status == .done ? "done" : "running")
                }
                return d
            }
            return ["ok": true, "sessions": arr]

        case "spawn":
            guard let dir = args["dir"] as? String else { return ["ok": false, "error": "dir required"] }
            let profileName = (args["profile"] as? String) ?? "Shell"
            let launch: String?
            if let c = args["command"] as? String { launch = c }
            else { launch = Profile.builtins.first { $0.name == profileName }?.command }
            let name = (args["name"] as? String) ?? profileName
            let rc = (args["rc"] as? Bool) ?? false
            let s = mgr.addSession(title: name, cwd: (dir as NSString).expandingTildeInPath,
                                   launchCommand: launch, profileName: profileName, remoteControl: rc)
            if let prompt = args["prompt"] as? String, !prompt.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    s.terminalView.send(txt: prompt + "\r")
                }
            }
            return ["ok": true, "id": s.id.uuidString, "title": s.title]

        case "send":
            guard let s = resolve(args) else { return ["ok": false, "error": "session not found"] }
            s.terminalView.send(txt: ((args["text"] as? String) ?? "") + "\r")
            return ["ok": true]

        case "read":
            guard let s = resolve(args) else { return ["ok": false, "error": "session not found"] }
            // --lines kommt als Zahl oder (über baryctl) als String an.
            let lines = (args["lines"] as? Int) ?? (args["lines"] as? String).flatMap { Int($0) } ?? 200
            return ["ok": true, "id": s.id.uuidString, "title": s.title,
                    "text": s.terminalText(maxLines: lines)]

        case "focus":
            guard let s = resolve(args) else { return ["ok": false, "error": "session not found"] }
            mgr.select(s.id); mgr.setViewMode(.focus)
            return ["ok": true]

        case "close":
            guard let s = resolve(args) else { return ["ok": false, "error": "session not found"] }
            mgr.remove(s.id)
            return ["ok": true]

        default:
            return ["ok": false, "error": "unknown cmd: \(cmd)"]
        }
    }

    private static func resolve(_ args: [String: Any]) -> Session? {
        let sessions = SessionManager.shared.sessions
        if let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) {
            return sessions.first { $0.id == id }
        }
        if let title = args["title"] as? String {
            return sessions.first { $0.title == title }
        }
        return nil
    }
}
