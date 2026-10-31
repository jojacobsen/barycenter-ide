import AppKit

/// Sheet for starting the AI manager: pick a folder and choose the AI/profile.
/// The selection is remembered (AppSettings) and pre-filled next time.
final class ManagerSheetController: NSViewController, NSTextFieldDelegate {
    private let aiPopup     = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customField = NSTextField()
    private let folderLabel = NSTextField(labelWithString: "")
    private var grid: NSGridView!

    /// AIs that make sense as a manager (Shell excluded) + Custom.
    private let aiProfiles: [Profile] = Profile.builtins.filter { $0.command != nil }
    private var folderURL: URL

    init() {
        folderURL = URL(fileURLWithPath: AppSettings.shared.managerDir)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func loadView() {
        aiPopup.addItems(withTitles: aiProfiles.map { $0.name } + [Profile.customName])
        if aiPopup.itemTitles.contains(AppSettings.shared.managerProfile) {
            aiPopup.selectItem(withTitle: AppSettings.shared.managerProfile)
        }
        aiPopup.target = self
        aiPopup.action = #selector(aiChanged)

        customField.placeholderString = L("z. B. claude")
        customField.stringValue = AppSettings.shared.managerCommand
        customField.delegate = self
        customField.translatesAutoresizingMaskIntoConstraints = false
        customField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        folderLabel.stringValue = folderURL.path
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.translatesAutoresizingMaskIntoConstraints = false
        folderLabel.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let chooseButton = NSButton(title: L("Wählen…"), target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded
        let folderRow = NSStackView(views: [folderLabel, chooseButton])
        folderRow.orientation = .horizontal
        folderRow.spacing = 8

        let hint = NSTextField(labelWithString: L("Der Verwalter steuert Barycenter (Sessions starten/senden/fokussieren) über seine Shell."))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        hint.preferredMaxLayoutWidth = 320

        let cancelButton = NSButton(title: L("Abbrechen"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let startButton = NSButton(title: L("Starten"), target: self, action: #selector(start))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [cancelButton, startButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        grid = NSGridView(views: [
            [label(L("AI:")),     aiPopup],
            [label(L("Befehl:")), customField],
            [label(L("Ordner:")), folderRow],
            [NSGridCell.emptyContentView, hint],
            [NSGridCell.emptyContentView, buttonRow],
        ])
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 14
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.row(at: 1).isHidden = !isCustomSelected()   // "Command" only for Custom

        let root = NSView()
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            grid.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
        ])
        self.view = root
        preferredContentSize = NSSize(width: 460, height: 210)
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 13)
        return l
    }

    private func isCustomSelected() -> Bool { aiPopup.titleOfSelectedItem == Profile.customName }

    @objc private func aiChanged() {
        grid.row(at: 1).isHidden = !isCustomSelected()
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL
        panel.prompt = L("Wählen")
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
            folderLabel.stringValue = url.path
        }
    }

    @objc private func cancel() { close() }

    private func close() { (presentingViewController ?? self).dismiss(self) }

    @objc private func start() {
        let selected = aiPopup.titleOfSelectedItem ?? "Claude Code"
        let launch: String?
        if selected == Profile.customName {
            let c = customField.stringValue.trimmingCharacters(in: .whitespaces)
            launch = c.isEmpty ? "claude" : c
        } else {
            launch = aiProfiles.first { $0.name == selected }?.command ?? "claude"
        }

        // Remember the selection.
        let st = AppSettings.shared
        st.managerDir = folderURL.path
        st.managerProfile = selected
        st.managerCommand = customField.stringValue.trimmingCharacters(in: .whitespaces)

        SessionManager.shared.spawnManager(dir: folderURL.path, profileName: selected, launchCommand: launch)
        close()
    }

    func controlTextDidChange(_ obj: Notification) {}
}
