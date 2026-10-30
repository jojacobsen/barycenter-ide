import AppKit
import UserNotifications
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var prefsController: PreferencesWindowController?
    private var aboutController: AboutWindowController?
    private var sidebar: SidebarViewController!
    private var toolItem: NSSplitViewItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        AttentionCenter.shared.start()   // Attention-Event-Kanal für Hooks
        AgentsMonitor.shared.start()     // Live-Status via `claude agents --json`
        ControlServer.shared.start()     // Kontroll-Kanal für den KI-Verwalter
        if Notifier.isBundled {
            UNUserNotificationCenter.current().delegate = self
            Notifier.requestAuthorization()
        }

        NSApp.appearance = NSAppearance(named: .darkAqua)   // dunkles, modernes Design

        let split = NSSplitViewController()

        // Activity-Rail ganz links (Toggle Sessions / Verwalter, später erweiterbar)
        let rail = ActivityRailViewController()
        let railItem = NSSplitViewItem(viewController: rail)
        railItem.minimumThickness = 84
        railItem.maximumThickness = 84
        railItem.canCollapse = false

        // Tool-Panel (zeigt das gewählte Werkzeug)
        sidebar = SidebarViewController()
        toolItem = NSSplitViewItem(viewController: sidebar)   // normale Spalte (nicht unter die Titelleiste) -> kein Versatz oben
        toolItem.minimumThickness = 260
        toolItem.maximumThickness = 480
        toolItem.canCollapse = true

        let contentItem = NSSplitViewItem(viewController: ContentViewController())

        split.addSplitViewItem(railItem)
        split.addSplitViewItem(toolItem)
        split.addSplitViewItem(contentItem)

        // Rail: Werkzeuge einzeln an/aus. Beide aktiv -> Panel teilt sich 50/50. Keins aktiv -> Panel eingeklappt.
        rail.onChange = { [weak self] tools in
            guard let self, let item = self.toolItem else { return }
            func animate(_ body: () -> Void) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    body()
                }
            }
            if tools.isEmpty {
                animate { item.animator().isCollapsed = true }
            } else {
                self.sidebar.showTools(tools)              // Inhalt zuerst bereitstellen -> kein Pop-in
                animate { item.animator().isCollapsed = false }
            }
        }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Barycenter"
        window.delegate = self
        window.contentViewController = split
        window.setFrameAutosaveName("BarycenterMainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Beim Start: Layout-Auswahl (zuletzt genutztes vorgewählt) — oder Neue-Session-Dialog, wenn es keine Layouts gibt.
        DispatchQueue.main.async { self.presentLayoutChooser(atLaunch: true) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Beenden-Abfrage, wenn noch Sessions laufen; danach aktuelles Layout automatisch sichern.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = SessionManager.shared.sessions.contains { $0.status == .running }
        if running {
            let alert = NSAlert()
            alert.messageText = L("Barycenter beenden?")
            alert.informativeText = L("Laufende Sessions werden beendet und ungespeicherte Notizen gehen verloren.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("Beenden"))
            alert.addButton(withTitle: L("Abbrechen"))
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        // Zuletzt genutztes Layout aktuell halten, damit es beim nächsten Start geladen werden kann.
        if let n = SessionManager.shared.currentLayoutName {
            SessionManager.shared.saveCurrentLayout(name: n)
        }
        return .terminateNow
    }

    // Roter Fenster-Button: NICHT direkt schließen, sondern über die Beenden-Abfrage leiten.
    // Bei „Abbrechen" bleibt das Fenster offen (wir geben false zurück).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    // MARK: - Layouts

    private func presentLayoutChooser(atLaunch: Bool) {
        let layouts = LayoutStore.all()
        if layouts.isEmpty {
            NotificationCenter.default.post(name: .newSessionRequested, object: nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = L("Layout laden")
        alert.informativeText = atLaunch
            ? L("Welches Layout möchtest du öffnen? (oder leer starten)")
            : L("Welches Layout laden? Die aktuellen Sessions werden ersetzt.")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        popup.addItems(withTitles: layouts.map { $0.name })
        if let last = LayoutStore.lastName, popup.itemTitles.contains(last) { popup.selectItem(withTitle: last) }
        alert.accessoryView = popup
        alert.addButton(withTitle: L("Laden"))
        if atLaunch { alert.addButton(withTitle: L("Neu (leer)")) }
        alert.addButton(withTitle: L("Abbrechen"))

        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            if let layout = layouts.first(where: { $0.name == popup.titleOfSelectedItem }) {
                SessionManager.shared.applyLayout(layout)
            }
        } else if atLaunch, resp == .alertSecondButtonReturn {
            NotificationCenter.default.post(name: .newSessionRequested, object: nil)
        }
    }

    @objc private func saveLayout() {
        if let n = SessionManager.shared.currentLayoutName { SessionManager.shared.saveCurrentLayout(name: n) }
        else { saveLayoutAs() }
    }
    @objc private func saveLayoutAs() {
        let alert = NSAlert()
        alert.messageText = L("Layout speichern unter…")
        alert.informativeText = L("Name des Layouts:")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        tf.stringValue = SessionManager.shared.currentLayoutName ?? L("Mein Layout")
        alert.accessoryView = tf
        alert.addButton(withTitle: L("Speichern"))
        alert.addButton(withTitle: L("Abbrechen"))
        if alert.runModal() == .alertFirstButtonReturn {
            let name = tf.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { SessionManager.shared.saveCurrentLayout(name: name) }
        }
    }
    @objc private func loadLayout() { presentLayoutChooser(atLaunch: false) }

    @objc private func showAbout() {
        if aboutController == nil { aboutController = AboutWindowController() }
        aboutController?.showWindow(nil)
        aboutController?.window?.center()
        aboutController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Banner auch zeigen, wenn Barycenter im Vordergrund ist.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    // MARK: - Hauptmenü

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        // App-Menü
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        add(appMenu, L("Über Barycenter"), #selector(showAbout), "")
        appMenu.addItem(.separator())
        add(appMenu, L("Einstellungen…"), #selector(openPreferences), ",")
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: L("Barycenter beenden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp

        // Bearbeiten-Menü: verdrahtet Cmd+X/C/V/A für Terminals, Notizen & Editoren.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: L("Bearbeiten"))
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: L("Ausschneiden"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Kopieren"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Einfügen"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Alles auswählen"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Session-Menü
        let sessItem = NSMenuItem()
        main.addItem(sessItem)
        let sessMenu = NSMenu(title: L("Session"))
        sessItem.submenu = sessMenu
        add(sessMenu, L("Neue Session"), #selector(newSession), "t")
        add(sessMenu, L("KI-Verwalter starten"), #selector(startManager), "m")
        add(sessMenu, L("Session schließen"), #selector(closeSession), "w")

        // Layout-Menü
        let layoutItem = NSMenuItem()
        main.addItem(layoutItem)
        let layoutMenu = NSMenu(title: L("Layout"))
        layoutItem.submenu = layoutMenu
        add(layoutMenu, L("Layout speichern"), #selector(saveLayout), "")
        add(layoutMenu, L("Layout speichern unter…"), #selector(saveLayoutAs), "")
        add(layoutMenu, L("Layout laden…"), #selector(loadLayout), "")

        // Ansicht-Menü
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: L("Ansicht"))
        viewItem.submenu = viewMenu
        add(viewMenu, L("Grid"), #selector(showGrid), "1")
        add(viewMenu, L("Fokus"), #selector(showFocus), "2")

        return main
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Menü-Aktionen

    @objc private func openPreferences() {
        if prefsController == nil { prefsController = PreferencesWindowController() }
        prefsController?.showWindow(nil)
        prefsController?.window?.center()
        prefsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func newSession()  { NotificationCenter.default.post(name: .newSessionRequested, object: nil) }
    @objc private func startManager() { SessionManager.shared.spawnManager() }
    @objc private func closeSession() {
        if let id = SessionManager.shared.selectedID {
            SessionManager.shared.requestClose(id, window: window)
        }
    }
    @objc private func showGrid()  { SessionManager.shared.setViewMode(.grid) }
    @objc private func showFocus() { SessionManager.shared.setViewMode(.focus) }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
