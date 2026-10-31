import AppKit
import UserNotifications
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var prefsController: PreferencesWindowController?
    private var aboutController: AboutWindowController?
    private var sidebar: SidebarViewController!
    private var toolItem: NSSplitViewItem!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        AttentionCenter.shared.start()   // attention event channel for hooks
        AgentsMonitor.shared.start()     // live status via `claude agents --json`
        ControlServer.shared.start()     // control channel for the AI manager
        if Notifier.isBundled {
            UNUserNotificationCenter.current().delegate = self
            Notifier.requestAuthorization()
        }

        NSApp.appearance = NSAppearance(named: .darkAqua)   // dark, modern look

        let split = NSSplitViewController()

        // Activity rail on the far left (toggle Sessions / Manager, extensible later)
        let rail = ActivityRailViewController()
        let railItem = NSSplitViewItem(viewController: rail)
        railItem.minimumThickness = 84
        railItem.maximumThickness = 84
        railItem.canCollapse = false

        // Tool panel (shows the selected tool)
        sidebar = SidebarViewController()
        toolItem = NSSplitViewItem(viewController: sidebar)   // normal column (not under the title bar) -> no offset at the top
        toolItem.minimumThickness = 260
        toolItem.maximumThickness = 480
        toolItem.canCollapse = true

        let contentItem = NSSplitViewItem(viewController: ContentViewController())

        split.addSplitViewItem(railItem)
        split.addSplitViewItem(toolItem)
        split.addSplitViewItem(contentItem)

        // Rail: toggle tools individually. Both active -> panel splits 50/50. None active -> panel collapsed.
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
                self.sidebar.showTools(tools)              // provide content first -> no pop-in
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
        window.minSize = NSSize(width: 900, height: 520)   // never collapse down to the toolbar
        // Note: NO setFrameAutosaveName — a previously saved mini frame made the
        // window collapse at launch. We always open at a sensible size.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame BarycenterMainWindow")
        window.setContentSize(NSSize(width: 1200, height: 760))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Menu-bar icon: fleet state + quick access, even when the window is not in front.
        menuBar = MenuBarController()
        menuBar.onShowWindow = { [weak self] in
            self?.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        menuBar.onNewSession = {
            NotificationCenter.default.post(name: .newSessionRequested, object: nil)
        }

        // NSSplitViewController forces its fitting size onto the window when shown.
        // So set the target size again AFTER showing it, and re-center.
        DispatchQueue.main.async {
            self.window.setContentSize(NSSize(width: 1200, height: 760))
            self.window.center()
            // At launch: layout picker (last used preselected) — or the New Session dialog.
            self.presentLayoutChooser(atLaunch: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Quit confirmation if sessions are still running; afterwards auto-save the current layout.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = SessionManager.shared.sessions.contains { $0.status == .running }
        let alert = NSAlert()
        alert.messageText = L("Barycenter beenden?")
        alert.informativeText = running
            ? L("Laufende Sessions werden beendet und ungespeicherte Notizen gehen verloren.")
            : L("Möchtest du Barycenter wirklich beenden?")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Beenden"))
        alert.addButton(withTitle: L("Abbrechen"))
        if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        // Keep the last-used layout up to date so it can be loaded on the next launch.
        if let n = SessionManager.shared.currentLayoutName {
            SessionManager.shared.saveCurrentLayout(name: n)
        }
        return .terminateNow
    }

    // Red window button: do NOT close directly, but route through the quit confirmation.
    // On "Cancel" the window stays open (we return false).
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

    // Show the banner even when Barycenter is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    // MARK: - Main menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        // App menu
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

        // Edit menu: wires up Cmd+X/C/V/A for terminals, notes & editors.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: L("Bearbeiten"))
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: L("Ausschneiden"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Kopieren"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Einfügen"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Alles auswählen"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Find submenu: drives the native find bar of the file editor (NSTextView).
        editMenu.addItem(.separator())
        let findParent = editMenu.addItem(withTitle: L("Suchen"), action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: L("Suchen"))
        findParent.submenu = findMenu
        func findItem(_ title: String, tag: Int, key: String, mask: NSEvent.ModifierFlags = .command) {
            let it = findMenu.addItem(withTitle: title,
                                      action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: key)
            it.tag = tag                 // NSTextFinder.Action raw value
            it.keyEquivalentModifierMask = mask
            it.target = nil              // routed to the first responder (the focused text view)
        }
        findItem(L("Suchen…"), tag: 1, key: "f")                               // showFindInterface
        findItem(L("Weitersuchen"), tag: 2, key: "g")                          // nextMatch
        findItem(L("Vorheriges suchen"), tag: 3, key: "g", mask: [.command, .shift]) // previousMatch
        findItem(L("Auswahl für Suche verwenden"), tag: 7, key: "e")           // setSearchString

        // Session menu
        let sessItem = NSMenuItem()
        main.addItem(sessItem)
        let sessMenu = NSMenu(title: L("Session"))
        sessItem.submenu = sessMenu
        add(sessMenu, L("Neue Session"), #selector(newSession), "t")
        add(sessMenu, L("KI-Verwalter starten"), #selector(startManager), "m")
        add(sessMenu, L("Session schließen"), #selector(closeSession), "w")

        // Layout menu
        let layoutItem = NSMenuItem()
        main.addItem(layoutItem)
        let layoutMenu = NSMenu(title: L("Layout"))
        layoutItem.submenu = layoutMenu
        add(layoutMenu, L("Layout speichern"), #selector(saveLayout), "")
        add(layoutMenu, L("Layout speichern unter…"), #selector(saveLayoutAs), "")
        add(layoutMenu, L("Layout laden…"), #selector(loadLayout), "")

        // View menu
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

    // MARK: - Menu actions

    @objc private func openPreferences() {
        if prefsController == nil { prefsController = PreferencesWindowController() }
        prefsController?.showWindow(nil)
        prefsController?.window?.center()
        prefsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func newSession()  { NotificationCenter.default.post(name: .newSessionRequested, object: nil) }
    @objc private func startManager() {
        guard AppSettings.shared.showManager else { return }
        NotificationCenter.default.post(name: .managerRequested, object: nil)
    }

    // Grey out "KI-Verwalter starten" while the manager is disabled in settings.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(startManager) { return AppSettings.shared.showManager }
        return true
    }
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
