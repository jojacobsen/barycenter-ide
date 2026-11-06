import AppKit

/// Preferences window (Cmd+,), organized like a native macOS settings window:
/// a toolbar of tabs (General · Terminal · Grid · Notifications), each a pane.
/// Everything takes effect immediately (except the UI language, which needs a restart).
final class PreferencesWindowController: NSWindowController, NSToolbarDelegate {
    // Terminal
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontPopup  = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizeField  = NSTextField()
    private let sizeStepper = NSStepper()
    // General
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let notesCheckbox = NSButton(checkboxWithTitle: L("Notizen in der Seitenleiste"), target: nil, action: nil)
    private let lineNumbersCheckbox = NSButton(checkboxWithTitle: L("Zeilennummern im Editor"), target: nil, action: nil)
    private let managerCheckbox = NSButton(checkboxWithTitle: L("KI-Verwalter anzeigen"), target: nil, action: nil)
    // Notifications
    private let notifyCheckbox = NSButton(checkboxWithTitle: L("Benachrichtigen, wenn eine Session fertig ist"), target: nil, action: nil)
    private let soundPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var soundNames: [String] = []
    // Grid
    private let pageSizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let tileStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statusDisplayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pageSizeValues = [4, 6, 8]
    private let tileStyleValues: [GridTileStyle] = [.uniform, .distinct]
    private let statusDisplayValues: [StatusDisplay] = [.border, .background]

    private let languageCodes: [String?] = [nil, "de", "en", "es", "fr", "it", "ja", "zh-Hans"]
    private let languageItemTitles = [L("System"), "Deutsch", "English", "Español", "Français", "Italiano", "日本語", "简体中文"]

    // MARK: Tabs

    private enum Tab: String, CaseIterable {
        case general, terminal, grid, notifications
        var title: String {
            switch self {
            case .general:       return L("Allgemein")
            case .terminal:      return L("Terminal")
            case .grid:          return L("Raster")
            case .notifications: return L("Benachrichtigung")
            }
        }
        var symbol: String {
            switch self {
            case .general:       return "gearshape"
            case .terminal:      return "terminal"
            case .grid:          return "square.grid.2x2"
            case .notifications: return "bell"
            }
        }
        var id: NSToolbarItem.Identifier { .init("pref.\(rawValue)") }
    }
    private var panes: [Tab: NSView] = [:]
    private static let paneWidth: CGFloat = 480

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.paneWidth, height: 240),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.init(window: window)
        buildControls()
        buildPanes()

        let toolbar = NSToolbar(identifier: "BarycenterPrefsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference

        loadValues()
        select(.general)
        window.center()
    }

    // MARK: Build controls

    private func buildControls() {
        themePopup.addItems(withTitles: Theme.presets.map { $0.name })
        themePopup.target = self; themePopup.action = #selector(themeChanged)

        fontPopup.addItems(withTitles: availableMonoFonts())
        fontPopup.target = self; fontPopup.action = #selector(fontChanged)

        sizeStepper.minValue = 9; sizeStepper.maxValue = 24; sizeStepper.increment = 1
        sizeStepper.valueWraps = false
        sizeStepper.target = self; sizeStepper.action = #selector(stepperChanged)
        sizeField.alignment = .right
        sizeField.formatter = {
            let f = NumberFormatter(); f.minimum = 9; f.maximum = 24; f.allowsFloats = false; return f
        }()
        sizeField.target = self; sizeField.action = #selector(sizeFieldChanged)
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        sizeField.widthAnchor.constraint(equalToConstant: 48).isActive = true

        languagePopup.addItems(withTitles: languageItemTitles)
        languagePopup.target = self; languagePopup.action = #selector(languageChanged)

        notesCheckbox.target = self; notesCheckbox.action = #selector(notesToggled)
        lineNumbersCheckbox.target = self; lineNumbersCheckbox.action = #selector(lineNumbersToggled)
        managerCheckbox.target = self; managerCheckbox.action = #selector(managerToggled)

        notifyCheckbox.target = self; notifyCheckbox.action = #selector(notifyToggled)
        soundNames = [AppSettings.soundOff] + AppSettings.availableSystemSounds()
        soundPopup.addItems(withTitles: [L("Aus")] + AppSettings.availableSystemSounds())
        soundPopup.target = self; soundPopup.action = #selector(soundChanged)

        pageSizePopup.addItems(withTitles: pageSizeValues.map { "\($0)" })
        pageSizePopup.target = self; pageSizePopup.action = #selector(pageSizeChanged)
        tileStylePopup.addItems(withTitles: [L("Einheitlich"), L("Unterschiedlich")])
        tileStylePopup.target = self; tileStylePopup.action = #selector(tileStyleChanged)
        statusDisplayPopup.addItems(withTitles: [L("Rahmen"), L("Hintergrund")])
        statusDisplayPopup.target = self; statusDisplayPopup.action = #selector(statusDisplayChanged)
    }

    // MARK: Build panes

    private func buildPanes() {
        let sizeRow = NSStackView(views: [sizeField, sizeStepper])
        sizeRow.orientation = .horizontal; sizeRow.spacing = 4

        panes[.terminal] = pane([
            [label(L("Theme:")),   themePopup],
            [label(L("Schrift:")), fontPopup],
            [label(L("Größe:")),   sizeRow],
            [NSGridCell.emptyContentView,
             note(L("Theme, Schrift und Größe gelten für die Terminals (Konsole) aller Sessions — nicht für die App-Oberfläche. Wirkt sofort."))],
        ])

        panes[.grid] = pane([
            [label(L("Sessions pro Seite:")), pageSizePopup],
            [label(L("Kacheln:")),            tileStylePopup],
            [label(L("Status anzeigen als:")), statusDisplayPopup],
            [NSGridCell.emptyContentView,
             note(L("„Unterschiedlich“ gibt jeder Kachel einen farbigen Streifen am linken Rand, damit du sie besser auseinanderhältst."))],
        ])

        panes[.general] = pane([
            [label(L("Sprache:")), languagePopup],
            [NSGridCell.emptyContentView, note(L("Neustart erforderlich, um die Sprache zu übernehmen."))],
            [NSGridCell.emptyContentView, notesCheckbox],
            [NSGridCell.emptyContentView, lineNumbersCheckbox],
            [NSGridCell.emptyContentView, managerCheckbox],
        ])

        panes[.notifications] = pane([
            [NSGridCell.emptyContentView, notifyCheckbox],
            [label(L("Ton:")), soundPopup],
        ])
    }

    /// A padded pane that wraps a 2-column grid at a fixed content width.
    private func pane(_ rows: [[NSView]]) -> NSView {
        let grid = NSGridView(views: rows)
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 14
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.paneWidth),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
        ])
        return container
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s); l.font = .systemFont(ofSize: 13); return l
    }
    private func note(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 3
        l.preferredMaxLayoutWidth = Self.paneWidth - 24 - 24 - 90
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    // MARK: Tab switching

    private func select(_ tab: Tab) {
        guard let pane = panes[tab], let window else { return }
        window.title = tab.title
        window.toolbar?.selectedItemIdentifier = tab.id
        let targetHeight = pane.fittingSize.height
        let newContent = NSSize(width: Self.paneWidth, height: targetHeight)
        let oldTop = window.frame.maxY
        window.contentView = pane
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: newContent))
        frame.origin.x = window.frame.origin.x
        frame.origin.y = oldTop - frame.height        // keep the title bar anchored
        window.setFrame(frame, display: true, animate: true)
    }

    @objc private func tabSelected(_ sender: NSToolbarItem) {
        if let tab = Tab.allCases.first(where: { $0.id == sender.itemIdentifier }) { select(tab) }
    }

    // MARK: NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = Tab.allCases.first(where: { $0.id == id }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(tabSelected(_:))
        return item
    }
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { Tab.allCases.map { $0.id } }
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { Tab.allCases.map { $0.id } }
    func toolbarSelectableItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { Tab.allCases.map { $0.id } }

    // MARK: Values

    private func loadValues() {
        let s = AppSettings.shared
        themePopup.selectItem(withTitle: s.themeName)
        if fontPopup.itemTitles.contains(s.fontName) { fontPopup.selectItem(withTitle: s.fontName) }
        sizeStepper.doubleValue = Double(s.fontSize)
        sizeField.stringValue = "\(Int(s.fontSize))"

        let current = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
        let idx = current.flatMap { code in languageCodes.firstIndex { $0 == code } } ?? 0
        languagePopup.selectItem(at: idx)

        notesCheckbox.state = s.showSidebarNotes ? .on : .off
        lineNumbersCheckbox.state = s.showEditorLineNumbers ? .on : .off
        managerCheckbox.state = s.showManager ? .on : .off
        notifyCheckbox.state = s.notificationsEnabled ? .on : .off
        soundPopup.selectItem(at: soundNames.firstIndex(of: s.notificationSound) ?? 0)
        soundPopup.isEnabled = s.notificationsEnabled

        pageSizePopup.selectItem(at: pageSizeValues.firstIndex(of: s.gridPageSize) ?? 2)
        tileStylePopup.selectItem(at: tileStyleValues.firstIndex(of: s.gridTileStyle) ?? 0)
        statusDisplayPopup.selectItem(at: statusDisplayValues.firstIndex(of: s.statusDisplay) ?? 0)
    }

    // MARK: Actions

    @objc private func themeChanged() { AppSettings.shared.themeName = themePopup.titleOfSelectedItem ?? "Barycenter Dark" }
    @objc private func fontChanged()  { if let f = fontPopup.titleOfSelectedItem { AppSettings.shared.fontName = f } }
    @objc private func stepperChanged() {
        let v = sizeStepper.doubleValue
        sizeField.stringValue = "\(Int(v))"
        AppSettings.shared.fontSize = CGFloat(v)
    }
    @objc private func sizeFieldChanged() {
        let v = max(9, min(24, sizeField.integerValue))
        sizeStepper.doubleValue = Double(v); sizeField.stringValue = "\(v)"
        AppSettings.shared.fontSize = CGFloat(v)
    }
    @objc private func languageChanged() {
        let idx = languagePopup.indexOfSelectedItem
        if let code = languageCodes[idx] { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
        else { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
    }
    @objc private func notesToggled()       { AppSettings.shared.showSidebarNotes = (notesCheckbox.state == .on) }
    @objc private func lineNumbersToggled() { AppSettings.shared.showEditorLineNumbers = (lineNumbersCheckbox.state == .on) }
    @objc private func managerToggled()     { AppSettings.shared.showManager = (managerCheckbox.state == .on) }
    @objc private func notifyToggled() {
        let on = (notifyCheckbox.state == .on)
        AppSettings.shared.notificationsEnabled = on
        soundPopup.isEnabled = on
    }
    @objc private func soundChanged() {
        AppSettings.shared.notificationSound = soundNames[soundPopup.indexOfSelectedItem]
        AppSettings.shared.playNotificationSound()
    }
    @objc private func pageSizeChanged()      { AppSettings.shared.gridPageSize = pageSizeValues[pageSizePopup.indexOfSelectedItem] }
    @objc private func tileStyleChanged()     { AppSettings.shared.gridTileStyle = tileStyleValues[tileStylePopup.indexOfSelectedItem] }
    @objc private func statusDisplayChanged() { AppSettings.shared.statusDisplay = statusDisplayValues[statusDisplayPopup.indexOfSelectedItem] }
}
