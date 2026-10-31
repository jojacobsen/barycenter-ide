import Foundation

/// Specification of a session within a layout (enough to restart it).
struct SessionSpec: Codable {
    var title: String
    var cwd: String
    var launchCommand: String?   // nil = Shell
    var profileName: String
    var remoteControl: Bool
    var resume: Bool?            // Claude --continue; optional so older layouts still decode
    // (Screen/window assignment comes with multi-window support.)
}

/// A named layout = which projects/sessions run with which settings.
struct Layout: Codable {
    var name: String
    var sessions: [SessionSpec]
}

/// Persists layouts as JSON under Application Support.
enum LayoutStore {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Barycenter/layouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func fileURL(_ name: String) -> URL {
        let safe = name.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return dir.appendingPathComponent("\(safe.isEmpty ? "layout" : safe).json")
    }

    static func save(_ layout: Layout) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(layout) { try? data.write(to: fileURL(layout.name)) }
    }

    static func all() -> [Layout] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Layout.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func load(named name: String) -> Layout? { all().first { $0.name == name } }

    static func delete(named name: String) { try? FileManager.default.removeItem(at: fileURL(name)) }

    static var lastName: String? {
        get { UserDefaults.standard.string(forKey: "lastLayoutName") }
        set { UserDefaults.standard.set(newValue, forKey: "lastLayoutName") }
    }
}
