import Foundation
import CryptoKit

/// Caches and generates a project's status overview (summary / roadmap / open points).
/// The overview is produced on demand by a headless `claude -p` run in the project folder
/// and cached per folder, so switching tabs or sessions keeps the last result.
enum ProjectStatus {

    /// The prompt handed to `claude -p`. Asks for Markdown with three fixed sections.
    private static let prompt = """
    Analysiere das Projekt im aktuellen Ordner (ein Git-Repository) und erstelle eine knappe \
    Status-Übersicht. Nutze dafür die Projektdateien (README, Code) sowie `git log` und `git status`.
    Antworte AUSSCHLIESSLICH mit Markdown, ohne Vorrede, mit genau diesen drei Abschnitten:

    ## Zusammenfassung
    2–4 Sätze: Was ist das Projekt und wo steht es aktuell?

    ## Roadmap
    Die nächsten sinnvollen Schritte als kurze Liste.

    ## Offene Punkte
    Bekannte TODOs, Baustellen oder Risiken als kurze Liste.
    """

    /// Longest we wait for a generation before giving up.
    private static let timeout: TimeInterval = 180

    // MARK: - Cache

    private static var cacheDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Barycenter/project-status", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheURL(for cwd: String) -> URL {
        let digest = SHA256.hash(data: Data(cwd.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(digest + ".md")
    }

    /// The cached overview for a folder, with its generation date — or nil if none yet.
    static func cached(for cwd: String) -> (text: String, date: Date)? {
        let url = cacheURL(for: cwd)
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return nil }
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
        return (text, date ?? Date())
    }

    // MARK: - Generation

    /// Run `claude -p` in `cwd`, cache the Markdown it prints, and call back on the main queue.
    static func generate(for cwd: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error>
            do {
                let out = try run(cwd: cwd)
                let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw Err.empty }
                try? text.write(to: cacheURL(for: cwd), atomically: true, encoding: .utf8)
                result = .success(text)
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private enum Err: LocalizedError {
        case empty, timedOut, failed(String)
        var errorDescription: String? {
            switch self {
            case .empty:          return L("Keine Ausgabe erhalten.")
            case .timedOut:       return L("Zeitüberschreitung (claude -p).")
            case .failed(let s):  return s.isEmpty ? L("Generierung fehlgeschlagen.") : s
            }
        }
    }

    private static func run(cwd: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Login shell loads PATH/rc so it finds `claude` like your terminal does.
        p.arguments = ["-l", "-c", "exec claude -p " + shellQuote(prompt)]
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        p.environment = ProcessInfo.processInfo.environment

        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()

        // Guard against a headless run that blocks (e.g. on a permission prompt).
        let deadline = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        deadline.cancel()

        if p.terminationStatus != 0 {
            let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw p.terminationReason == .uncaughtSignal ? Err.timedOut : Err.failed(msg)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
