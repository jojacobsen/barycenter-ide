import AppKit
import SwiftTerm

// MARK: - Hex-Helfer

func hexRGB(_ s: String) -> (UInt8, UInt8, UInt8) {
    var h = s.hasPrefix("#") ? String(s.dropFirst()) : s
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    let v = UInt32(h, radix: 16) ?? 0
    return (UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff))
}

func stColor(_ hex: String) -> SwiftTerm.Color {
    let (r, g, b) = hexRGB(hex)
    // SwiftTerm nutzt 16-Bit-Kanäle (0..65535): 8-Bit * 257 skaliert exakt.
    return SwiftTerm.Color(red: UInt16(r) * 257, green: UInt16(g) * 257, blue: UInt16(b) * 257)
}

extension NSColor {
    convenience init(hex: String) {
        let (r, g, b) = hexRGB(hex)
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

/// Monospace-Font nach Name; behandelt „SF Mono" (PostScript-Name) gesondert, sonst Fallback.
func makeMonoFont(_ name: String, _ size: CGFloat) -> NSFont {
    if name == "SF Mono" {
        return NSFont(name: "SFMono-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    return NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
}

/// Kandidaten-Monospace-Fonts, gefiltert auf tatsächlich installierte.
func availableMonoFonts() -> [String] {
    let candidates = ["SF Mono", "Menlo", "Monaco", "Courier New", "Andale Mono",
                      "PT Mono", "Fira Code", "JetBrains Mono", "Hack", "Cascadia Code", "Source Code Pro"]
    return candidates.filter { name in
        if name == "SF Mono" { return NSFont(name: "SFMono-Regular", size: 12) != nil }
        return NSFont(name: name, size: 12) != nil
    }
}

// MARK: - Theme

/// Farbschema für die eingebetteten Terminals. Farben als Hex gespeichert,
/// damit Presets einfach les-/erweiterbar sind.
struct Theme {
    let name: String
    let background: String
    let foreground: String
    let cursor: String
    let ansi: [String]   // 16 ANSI-Farben (0-7 normal, 8-15 hell)

    func apply(to tv: LocalProcessTerminalView, fontName: String, fontSize: CGFloat) {
        tv.installColors(ansi.map { stColor($0) })
        tv.nativeBackgroundColor = NSColor(hex: background)
        tv.nativeForegroundColor = NSColor(hex: foreground)
        tv.caretColor = NSColor(hex: cursor)
        tv.font = makeMonoFont(fontName, fontSize)
    }

    static let presets: [Theme] = [
        Theme(name: "Barycenter Dark",
              background: "#282c34", foreground: "#abb2bf", cursor: "#528bff",
              ansi: ["#282c34", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
                     "#5c6370", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff"]),
        Theme(name: "Tokyo Night",
              background: "#1a1b26", foreground: "#c0caf5", cursor: "#c0caf5",
              ansi: ["#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
                     "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"]),
        Theme(name: "Solarized Dark",
              background: "#002b36", foreground: "#839496", cursor: "#93a1a1",
              ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                     "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]),
        Theme(name: "Solarized Light",
              background: "#fdf6e3", foreground: "#657b83", cursor: "#586e75",
              ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                     "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]),
        Theme(name: "Classic",
              background: "#000000", foreground: "#ffffff", cursor: "#ffffff",
              ansi: ["#000000", "#990000", "#00a600", "#999900", "#0000b2", "#b200b2", "#00a6b2", "#bfbfbf",
                     "#666666", "#e50000", "#00d900", "#e5e500", "#0000ff", "#e500e5", "#00e5e5", "#e5e5e5"]),
    ]

    static func named(_ n: String) -> Theme { presets.first { $0.name == n } ?? presets[0] }
}
