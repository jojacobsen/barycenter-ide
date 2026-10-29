import AppKit

/// Sheet zum Starten einer neuen Session: Profil wählen, Ordner wählen, benennen.
final class NewSessionSheetController: NSViewController, NSTextFieldDelegate {
    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customField  = NSTextField()
    private let folderLabel  = NSTextField(labelWithString: "")
    private let nameField    = NSTextField()
    private let rcCheckbox   = NSButton(checkboxWithTitle: "Remote Control (von anderem Gerät steuerbar)",
                                        target: nil, action: nil)
    private let worktreeCheckbox = NSButton(checkboxWithTitle: "Eigener Git-Worktree (Branch) – nur bei Git-Repo",
                                            target: nil, action: nil)
    private var grid: NSGridView!

    private var folderURL = FileManager.default.homeDirectoryForCurrentUser
    private var nameEdited = false

    override func loadView() {
        profilePopup.addItems(withTitles: Profile.builtins.map { $0.name } + [Profile.customName])
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged)

        customField.placeholderString = "z. B. htop"
        customField.delegate = self
        customField.translatesAutoresizingMaskIntoConstraints = false
        customField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        folderLabel.stringValue = folderURL.path
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.translatesAutoresizingMaskIntoConstraints = false
        folderLabel.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let chooseButton = NSButton(title: "Wählen…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded
        let folderRow = NSStackView(views: [folderLabel, chooseButton])
        folderRow.orientation = .horizontal
        folderRow.spacing = 8

        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        let cancelButton = NSButton(title: "Abbrechen", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let startButton = NSButton(title: "Starten", target: self, action: #selector(start))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [cancelButton, startButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        grid = NSGridView(views: [
            [label("Profil:"), profilePopup],
            [label("Befehl:"), customField],
            [NSGridCell.emptyContentView, rcCheckbox],
            [label("Ordner:"), folderRow],
            [label("Name:"),   nameField],
            [NSGridCell.emptyContentView, worktreeCheckbox],
            [NSGridCell.emptyContentView, buttonRow],
        ])
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 14
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.row(at: 1).isHidden = true                 // „Befehl" nur bei Custom
        grid.row(at: 2).isHidden = !isClaudeSelected()   // „Remote Control" nur bei Claude Code

        let root = NSView()
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            grid.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
        ])
        self.view = root
        preferredContentSize = NSSize(width: 460, height: 240)

        updateName()
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 13)
        return l
    }

    // MARK: Actions

    private func isClaudeSelected() -> Bool {
        Profile.builtins.first { $0.name == profilePopup.titleOfSelectedItem }?.command == "claude"
    }

    @objc private func profileChanged() {
        grid.row(at: 1).isHidden = (profilePopup.titleOfSelectedItem != Profile.customName)
        grid.row(at: 2).isHidden = !isClaudeSelected()
        updateName()
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL
        panel.prompt = "Wählen"
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
            folderLabel.stringValue = url.path
            updateName()
        }
    }

    @objc private func cancel() { close() }

    private func close() {
        // Korrekt über den Presenter schließen (sonst bleibt das Sheet intern „präsentiert").
        (presentingViewController ?? self).dismiss(self)
    }

    @objc private func start() {
        let selected = profilePopup.titleOfSelectedItem
        let launch: String?
        if selected == Profile.customName {
            let c = customField.stringValue.trimmingCharacters(in: .whitespaces)
            launch = c.isEmpty ? nil : c
        } else {
            launch = Profile.builtins.first { $0.name == selected }?.command
        }
        let profileName = (selected == Profile.customName) ? (launch ?? "Shell") : (selected ?? "Shell")
        let rc = isClaudeSelected() && rcCheckbox.state == .on
        let title = nameField.stringValue.isEmpty ? defaultName() : nameField.stringValue

        // Optional: eigenen Git-Worktree anlegen und darin starten.
        var cwd = folderURL.path
        if worktreeCheckbox.state == .on, let wt = Git.makeWorktree(in: cwd, name: title) {
            cwd = wt
        }

        SessionManager.shared.addSession(title: title, cwd: cwd,
                                         launchCommand: launch, profileName: profileName, remoteControl: rc)
        close()
    }

    // MARK: Namens-Vorschlag

    private func defaultName() -> String {
        let base = folderURL.lastPathComponent
        let p = profilePopup.titleOfSelectedItem ?? "Shell"
        if p == Profile.customName {
            let c = customField.stringValue.trimmingCharacters(in: .whitespaces)
            return "\(c.isEmpty ? "cmd" : c) · \(base)"
        }
        return "\(p) · \(base)"
    }

    private func updateName() {
        guard !nameEdited else { return }
        nameField.stringValue = defaultName()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField else { return }
        if tf == nameField {
            nameEdited = !nameField.stringValue.isEmpty
        } else if tf == customField {
            updateName()
        }
    }
}
