import AppKit

/// Menüleisten-Icon (`NSStatusItem`). Zeigt den Flotten-Zustand als Barycenter-Glyph
/// (Kern + Orbit) — rot mit Zähler, sobald Sessions auf dich warten — und bietet ein
/// schnelles Menü zum Fokussieren/Anzeigen, auch wenn das Fenster nicht im Vordergrund ist.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let glyph = MenuBarController.makeGlyph()

    /// Holt das Hauptfenster nach vorn (von AppDelegate gesetzt).
    var onShowWindow: (() -> Void)?
    /// Fordert eine neue Session an (von AppDelegate gesetzt).
    var onNewSession: (() -> Void)?

    override init() {
        super.init()
        if let btn = statusItem.button {
            btn.image = glyph
            btn.imagePosition = .imageLeading
            btn.toolTip = "Barycenter"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        for name in [Notification.Name.sessionsChanged, .selectionChanged, .agentsUpdated] {
            NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                                   name: name, object: nil)
        }
        refresh()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Glyph & Zustand

    /// Spiegelt den Flotten-Zustand ins Icon: rote Tönung + Zähler, wenn etwas wartet.
    @objc private func refresh() {
        guard let btn = statusItem.button else { return }
        let waiting = SessionManager.shared.sessions.filter { $0.needsAttention }.count
        if waiting > 0 {
            btn.contentTintColor = .systemRed
            btn.attributedTitle = NSAttributedString(string: " \(waiting)", attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            ])
            btn.toolTip = "\(waiting) · \(L("braucht dich"))"
        } else {
            btn.contentTintColor = nil            // folgt wieder der Menüleisten-Darstellung
            btn.title = ""
            btn.toolTip = "Barycenter"
        }
    }

    /// Das Barycenter-Zeichen: Ring (Orbit), gefüllter Kern, kleiner Trabant auf dem Ring.
    /// Template-Bild ⇒ passt sich heller/dunkler Menüleiste an; Tönung steuert `refresh()`.
    private static func makeGlyph() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let cx = size.width / 2, cy = size.height / 2
        let ringR: CGFloat = 6
        let ring = NSBezierPath(ovalIn: NSRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2))
        ring.lineWidth = 1.2
        ring.stroke()
        let coreR: CGFloat = 2.6
        NSBezierPath(ovalIn: NSRect(x: cx - coreR, y: cy - coreR, width: coreR * 2, height: coreR * 2)).fill()
        // Trabant oben rechts auf dem Ring: erst einen Freiraum ausstanzen, dann füllen,
        // damit er sich klar vom Orbit abhebt.
        let ang = CGFloat.pi / 4
        let sx = cx + cos(ang) * ringR, sy = cy + sin(ang) * ringR
        let satR: CGFloat = 2.2
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: sx - satR - 0.7, y: sy - satR - 0.7,
                                    width: (satR + 0.7) * 2, height: (satR + 0.7) * 2)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: sx - satR, y: sy - satR, width: satR * 2, height: satR * 2)).fill()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    // MARK: - Menü (bei jedem Öffnen frisch aufgebaut)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let mgr = SessionManager.shared

        let ordered = mgr.workerSessions + (mgr.managerSession.map { [$0] } ?? [])
        if ordered.isEmpty {
            let empty = menu.addItem(withTitle: L("Keine aktiven Sessions"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
        } else {
            for s in ordered {
                let title = "\(s.title)  —  \(s.menuStatusText)"
                let item = menu.addItem(withTitle: title, action: #selector(focusSession(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = s.id.uuidString
                item.image = Self.dot(s.needsAttention ? .systemRed : s.menuStatusColor)
                if s.id == mgr.selectedID { item.state = .on }
            }
        }

        menu.addItem(.separator())
        add(menu, L("Barycenter anzeigen"), #selector(showWindow))
        add(menu, L("Neue Session"), #selector(newSession))
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: L("Barycenter beenden"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Kleiner farbiger Statuspunkt (kein Template ⇒ behält seine Farbe).
    private static func dot(_ color: NSColor, d: CGFloat = 9) -> NSImage {
        let img = NSImage(size: NSSize(width: d, height: d))
        img.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: d, height: d)).fill()
        img.unlockFocus()
        return img
    }

    // MARK: - Aktionen

    @objc private func focusSession(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String, let id = UUID(uuidString: idStr) else { return }
        SessionManager.shared.select(id)
        SessionManager.shared.setViewMode(.focus)
        onShowWindow?()
    }

    @objc private func showWindow() { onShowWindow?() }

    @objc private func newSession() {
        onShowWindow?()
        onNewSession?()
    }
}
