import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var window: NSWindow!
    private var prefsController: PreferencesWindowController?
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
        toolItem = NSSplitViewItem(sidebarWithViewController: sidebar)
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
            if tools.isEmpty {
                item.animator().isCollapsed = true
            } else {
                item.animator().isCollapsed = false
                self.sidebar.showTools(tools)
            }
        }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Barycenter"
        window.contentViewController = split
        window.setFrameAutosaveName("BarycenterMainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Beim Start keine Auto-Session, sondern den „Neue Session"-Dialog öffnen.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .newSessionRequested, object: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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
        add(appMenu, "Einstellungen…", #selector(openPreferences), ",")
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Barycenter beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp

        // Bearbeiten-Menü: verdrahtet Cmd+X/C/V/A für Terminals, Notizen & Editoren.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Bearbeiten")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Einfügen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Session-Menü
        let sessItem = NSMenuItem()
        main.addItem(sessItem)
        let sessMenu = NSMenu(title: "Session")
        sessItem.submenu = sessMenu
        add(sessMenu, "Neue Session", #selector(newSession), "t")
        add(sessMenu, "KI-Verwalter starten", #selector(startManager), "m")
        add(sessMenu, "Session schließen", #selector(closeSession), "w")

        // Ansicht-Menü
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "Ansicht")
        viewItem.submenu = viewMenu
        add(viewMenu, "Grid", #selector(showGrid), "1")
        add(viewMenu, "Fokus", #selector(showFocus), "2")

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
