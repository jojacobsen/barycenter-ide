import AppKit

/// Per-session settings: rename (live) + change the launch config (folder, profile,
/// Remote Control, resume). Changing a launch option restarts the session to apply
/// it — for a Claude session in the same folder, with `--continue` so the
/// conversation is kept.
final class SessionSettingsSheetController: NSViewController {
    private let session: Session

    private let nameField     = NSTextField()
    private let folderValue   = NSTextField(labelWithString: "")
    private let profilePopup  = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customField   = NSTextField()
    private let rcCheckbox    = NSButton(checkboxWithTitle: L("Remote Control (von anderem Gerät steuerbar)"),
                                         target: nil, action: nil)
    private let resumeCheckbox = NSButton(checkboxWithTitle: L("Letzte Unterhaltung fortsetzen (-c)"),
                                          target: nil, action: nil)
    private var grid: NSGridView!
    private var folderURL: URL

    init(session: Session) {
        self.session = session
        self.folderURL = URL(fileURLWithPath: session.cwd)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        profilePopup.addItems(withTitles: Profile.builtins.map { $0.name } + [Profile.customName])
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged)

        customField.placeholderString = L("z. B. npm run dev")
        customField.translatesAutoresizingMaskIntoConstraints = false
        customField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        folderValue.font = .systemFont(ofSize: 12)
        folderValue.textColor = .secondaryLabelColor
        folderValue.lineBreakMode = .byTruncatingMiddle
        folderValue.translatesAutoresizingMaskIntoConstraints = false
        folderValue.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let folderButton = NSButton(title: L("Ändern…"), target: self, action: #selector(chooseFolder))
        folderButton.bezelStyle = .rounded
        folderButton.controlSize = .small
        let folderRow = NSStackView(views: [folderValue, folderButton])
        folderRow.orientation = .horizontal
        folderRow.spacing = 6

        rcCheckbox.target = self; rcCheckbox.action = #selector(noop)
        resumeCheckbox.target = self; resumeCheckbox.action = #selector(noop)

        let note = NSTextField(labelWithString: L("Ordner, Profil, Remote Control und Resume gelten beim Start — beim Ändern wird die Session neu gestartet (Claude: mit --continue)."))
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 3
        note.preferredMaxLayoutWidth = 320
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        grid = NSGridView(views: [
            [label(L("Name:")),   nameField],
            [label(L("Ordner:")), folderRow],
            [label(L("Profil:")), profilePopup],
            [label(L("Befehl:")), customField],
            [NSGridCell.emptyContentView, rcCheckbox],
            [NSGridCell.emptyContentView, resumeCheckbox],
            [NSGridCell.emptyContentView, note],
        ])
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 14
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: L("Abbrechen"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let applyButton = NSButton(title: L("Übernehmen"), target: self, action: #selector(apply))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [cancelButton, applyButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let container = NSView()
        for v in [grid, buttonRow] { v!.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v!) }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            buttonRow.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            buttonRow.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
        ])
        self.view = container
        loadValues()
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 13)
        return l
    }

    private func loadValues() {
        nameField.stringValue = session.title
        folderValue.stringValue = prettyPath(session.cwd)
        // Pick the profile: a builtin by name, else "Custom Command…".
        if Profile.builtins.contains(where: { $0.name == session.profileName }) {
            profilePopup.selectItem(withTitle: session.profileName)
        } else {
            profilePopup.selectItem(withTitle: Profile.customName)
            customField.stringValue = session.launchCommand ?? session.profileName
        }
        rcCheckbox.state = session.remoteControl ? .on : .off
        // Default resume ON for a Claude restart so the conversation is kept.
        resumeCheckbox.state = (isClaudeSelected() ? .on : .off)
        updateRowVisibility()
    }

    private func isClaudeSelected() -> Bool {
        Profile.builtins.first { $0.name == profilePopup.titleOfSelectedItem }?.command == "claude"
    }

    private func updateRowVisibility() {
        grid.row(at: 3).isHidden = (profilePopup.titleOfSelectedItem != Profile.customName)  // Befehl
        grid.row(at: 4).isHidden = !isClaudeSelected()                                        // Remote Control
        grid.row(at: 5).isHidden = !isClaudeSelected()                                        // Resume
    }

    @objc private func profileChanged() { updateRowVisibility() }
    @objc private func noop() {}

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL
        panel.prompt = L("Wählen")
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
            folderValue.stringValue = prettyPath(url.path)
        }
    }

    @objc private func cancel() { (presentingViewController ?? self).dismiss(self) }

    @objc private func apply() {
        let selected = profilePopup.titleOfSelectedItem
        let launch: String?
        if selected == Profile.customName {
            let c = customField.stringValue.trimmingCharacters(in: .whitespaces)
            launch = c.isEmpty ? nil : c
        } else {
            launch = Profile.builtins.first { $0.name == selected }?.command
        }
        let profileName = (selected == Profile.customName) ? (launch ?? "Shell") : (selected ?? "Shell")
        let claude = isClaudeSelected()
        let rc = claude && rcCheckbox.state == .on
        let cwd = folderURL.path
        let title = nameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
            ? session.title : nameField.stringValue
        // Resume only when it's safe (Claude, same folder) — otherwise --continue
        // could find no conversation and leave a dead session.
        let resume = claude && resumeCheckbox.state == .on && cwd == session.cwd

        let launchChanged = cwd != session.cwd
            || launch != session.launchCommand
            || profileName != session.profileName
            || rc != session.remoteControl

        if !launchChanged {
            SessionManager.shared.rename(session.id, to: title)   // no-op if unchanged
            cancel()
            return
        }

        let confirm = NSAlert()
        confirm.messageText = L("Session neu starten, um die Änderungen zu übernehmen?")
        confirm.informativeText = claude
            ? L("Der laufende Prozess wird beendet und neu gestartet. Mit „Resume“ wird die Claude-Unterhaltung fortgesetzt.")
            : L("Der laufende Prozess wird beendet und neu gestartet. Nicht gespeicherter Zustand geht verloren.")
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: L("Neu starten"))
        confirm.addButton(withTitle: L("Abbrechen"))
        let go = { [weak self] in
            guard let self else { return }
            SessionManager.shared.reconfigure(self.session.id, title: title, cwd: cwd,
                                              launchCommand: launch, profileName: profileName,
                                              remoteControl: rc, resume: resume)
            self.cancel()
        }
        if let win = view.window {
            confirm.beginSheetModal(for: win) { if $0 == .alertFirstButtonReturn { go() } }
        } else if confirm.runModal() == .alertFirstButtonReturn {
            go()
        }
    }

    private func prettyPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
