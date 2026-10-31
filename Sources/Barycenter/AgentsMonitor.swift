import AppKit

extension Notification.Name {
    static let agentsUpdated = Notification.Name("BarycenterAgentsUpdated")
}

/// Live info for a Claude session from `claude agents --json`.
struct AgentInfo {
    let status: String        // "busy" | "waiting" | "idle"
    let waitingFor: String?   // e.g. "permission prompt"
    let name: String?
    let sessionId: String?
}

/// Periodically polls `claude agents --json` and keeps a PID→AgentInfo map.
/// Barycenter launches Claude via `exec`, so the PID is identical -> exact matching.
final class AgentsMonitor {
    static let shared = AgentsMonitor()

    private(set) var byPID: [Int32: AgentInfo] = [:]
    private var timer: Timer?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
    }

    func info(forPID pid: Int32) -> AgentInfo? { pid > 0 ? byPID[pid] : nil }

    private func poll() {
        DispatchQueue.global(qos: .utility).async {
            let map = Self.run().flatMap(Self.parse) ?? [:]
            DispatchQueue.main.async {
                self.byPID = map
                NotificationCenter.default.post(name: .agentsUpdated, object: nil)
            }
        }
    }

    private static func run() -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-l", "-c", "claude agents --json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    private static func parse(_ data: Data) -> [Int32: AgentInfo]? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var map: [Int32: AgentInfo] = [:]
        for r in arr {
            guard let pid = r["pid"] as? Int else { continue }
            map[Int32(pid)] = AgentInfo(
                status: r["status"] as? String ?? "idle",
                waitingFor: r["waitingFor"] as? String,
                name: r["name"] as? String,
                sessionId: r["sessionId"] as? String
            )
        }
        return map
    }
}
