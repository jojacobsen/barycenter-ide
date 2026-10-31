import AppKit

/// Menu-bar icon (`NSStatusItem`). Shows the fleet state as a Barycenter glyph
/// (core + orbit) — red with a counter as soon as sessions are waiting on you — and offers a
/// quick menu to focus/show, even when the window is not in the foreground.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let glyph = MenuBarController.makeGlyph()

    /// Brings the main window to the front (set by AppDelegate).
    var onShowWindow: (() -> Void)?
    /// Requests a new session (set by AppDelegate).
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

    // MARK: - Glyph & state

    /// Mirrors the fleet state into the icon: red tint + counter when something is waiting.
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
            btn.contentTintColor = nil            // follow the menu-bar appearance again
            btn.title = ""
            btn.toolTip = "Barycenter"
        }
    }

    /// The Barycenter mark: ring (orbit), filled core, small satellite on the ring.
    /// Template image ⇒ adapts to a light/dark menu bar; `refresh()` controls the tint.
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
        // Satellite at the top right on the ring: first punch out a gap, then fill it,
        // so it stands out clearly from the orbit.
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

    // MARK: - Menu (rebuilt fresh on every open)

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

    /// Small colored status dot (not a template ⇒ keeps its color).
    private static func dot(_ color: NSColor, d: CGFloat = 9) -> NSImage {
        let img = NSImage(size: NSSize(width: d, height: d))
        img.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: d, height: d)).fill()
        img.unlockFocus()
        return img
    }

    // MARK: - Actions

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
