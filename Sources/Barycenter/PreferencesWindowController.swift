import AppKit

/// Einstellungs-Fenster (Cmd+,): Theme, Schriftart, Schriftgröße. Wirkt sofort.
final class PreferencesWindowController: NSWindowController {
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontPopup  = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizeField  = NSTextField()
    private let sizeStepper = NSStepper()
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    /// Sprach-Codes passend zu den Einträgen des Sprach-Popups.
    /// `nil` = „System" (kein Override). Reihenfolge muss zu `languageItemTitles` passen.
    private let languageCodes: [String?] = [nil, "de", "en", "es", "fr", "it", "ja", "zh-Hans"]
    private let languageItemTitles = [L("System"), "Deutsch", "English", "Español", "Français", "Italiano", "日本語", "简体中文"]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = L("Terminal-Einstellungen")
        self.init(window: window)
        buildUI()
        loadValues()
    }

    private func buildUI() {
        let settings = AppSettings.shared

        themePopup.addItems(withTitles: Theme.presets.map { $0.name })
        themePopup.target = self
        themePopup.action = #selector(themeChanged)

        fontPopup.addItems(withTitles: availableMonoFonts())
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged)

        sizeStepper.minValue = 9
        sizeStepper.maxValue = 24
        sizeStepper.increment = 1
        sizeStepper.valueWraps = false
        sizeStepper.target = self
        sizeStepper.action = #selector(stepperChanged)

        sizeField.alignment = .right
        sizeField.formatter = {
            let f = NumberFormatter(); f.minimum = 9; f.maximum = 24; f.allowsFloats = false; return f
        }()
        sizeField.target = self
        sizeField.action = #selector(sizeFieldChanged)
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        sizeField.widthAnchor.constraint(equalToConstant: 48).isActive = true

        let sizeRow = NSStackView(views: [sizeField, sizeStepper])
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 4

        languagePopup.addItems(withTitles: languageItemTitles)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)

        let note = NSTextField(labelWithString: L("Theme/Schrift gelten für die Terminals (Konsole) aller Sessions — nicht für die App-Oberfläche. Wirkt sofort."))
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 2
        note.preferredMaxLayoutWidth = 340
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        let restartNote = NSTextField(labelWithString: L("Neustart erforderlich, um die Sprache zu übernehmen."))
        restartNote.lineBreakMode = .byWordWrapping
        restartNote.maximumNumberOfLines = 2
        restartNote.preferredMaxLayoutWidth = 340
        restartNote.font = .systemFont(ofSize: 11)
        restartNote.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [label(L("Theme:")),  themePopup],
            [label(L("Schrift:")), fontPopup],
            [label(L("Größe:")),   sizeRow],
            [NSGridCell.emptyContentView, note],
            [label(L("Sprache:")), languagePopup],
            [NSGridCell.emptyContentView, restartNote],
        ])
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 14
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
        ])
        window?.contentView = content
        _ = settings // (nur zur Klarheit; Werte folgen in loadValues)
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 13)
        return l
    }

    private func loadValues() {
        let s = AppSettings.shared
        themePopup.selectItem(withTitle: s.themeName)
        if fontPopup.itemTitles.contains(s.fontName) {
            fontPopup.selectItem(withTitle: s.fontName)
        }
        sizeStepper.doubleValue = Double(s.fontSize)
        sizeField.stringValue = "\(Int(s.fontSize))"

        // Aktuell aktiven Sprach-Override vorwählen (erster Eintrag der AppleLanguages-Liste).
        let current = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
        let idx = current.flatMap { code in languageCodes.firstIndex { $0 == code } } ?? 0
        languagePopup.selectItem(at: idx)
    }

    // MARK: Actions

    @objc private func themeChanged() {
        AppSettings.shared.themeName = themePopup.titleOfSelectedItem ?? "Barycenter Dark"
    }
    @objc private func fontChanged() {
        if let f = fontPopup.titleOfSelectedItem { AppSettings.shared.fontName = f }
    }
    @objc private func stepperChanged() {
        let v = sizeStepper.doubleValue
        sizeField.stringValue = "\(Int(v))"
        AppSettings.shared.fontSize = CGFloat(v)
    }
    @objc private func sizeFieldChanged() {
        let v = max(9, min(24, sizeField.integerValue))
        sizeStepper.doubleValue = Double(v)
        sizeField.stringValue = "\(v)"
        AppSettings.shared.fontSize = CGFloat(v)
    }
    @objc private func languageChanged() {
        let idx = languagePopup.indexOfSelectedItem
        if let code = languageCodes[idx] {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")   // „System": kein Override
        }
    }
}
