import AppKit

/// Sheet for starting a new session. Left: a list of recently used projects
/// (rich rows, like the session list). Right: the launch form. You can also pick
/// any other folder or create a brand-new project folder on the fly.
final class NewSessionSheetController: NSViewController, NSTextFieldDelegate,
                                       NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customField  = NSTextField()
    private let folderValue  = NSTextField(labelWithString: "")
    private let nameField    = NSTextField()
    private let rcCheckbox   = NSButton(checkboxWithTitle: L("Remote Control (von anderem Gerät steuerbar)"),
                                        target: nil, action: nil)
    private let resumeCheckbox = NSButton(checkboxWithTitle: L("Letzte Unterhaltung fortsetzen (-c)"),
                                          target: nil, action: nil)
    private let worktreeCheckbox = NSButton(checkboxWithTitle: L("Eigener Git-Worktree (Branch) – nur bei Git-Repo"),
                                            target: nil, action: nil)
    private var grid: NSGridView!

    private var folderURL = FileManager.default.homeDirectoryForCurrentUser
    private var nameEdited = false
    private var recentProjects: [RecentProject] = []

    override func loadView() {
        recentProjects = ProjectScanner.recent()

        let root = NSView()
        let left = buildProjectList()
        let right = buildForm()
        left.translatesAutoresizingMaskIntoConstraints = false
        right.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(left)
        root.addSubview(right)

        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            left.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            left.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            left.widthAnchor.constraint(equalToConstant: 268),

            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 20),
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            right.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            right.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])
        self.view = root
        preferredContentSize = NSSize(width: 680, height: 440)

        // Preselect the most recent project so the form is immediately usable.
        if !recentProjects.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            applySelection(0)
        } else {
            folderValue.stringValue = folderURL.path
            updateName()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(table)   // arrow keys navigate the project list right away
    }

    // MARK: - Left: project list

    private func buildProjectList() -> NSView {
        let header = NSTextField(labelWithString: L("Zuletzt genutzte Projekte"))
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor

        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 56
        table.dataSource = self
        table.delegate = self
        table.addTableColumn(NSTableColumn(identifier: .init("project")))
        table.doubleAction = #selector(start)      // double-click a project to start right away
        table.target = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let newButton = NSButton(title: L("Neues Projekt…"), target: self, action: #selector(newProject))
        newButton.bezelStyle = .rounded
        let otherButton = NSButton(title: L("Anderer Ordner…"), target: self, action: #selector(chooseFolder))
        otherButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [newButton, otherButton])
        buttons.orientation = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 8

        let stack = NSStackView(views: [header, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill          // let the list stretch to fill the height
        stack.spacing = 8
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    func numberOfRows(in tableView: NSTableView) -> Int { recentProjects.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let p = recentProjects[row]
        let cell = NSTableCellView()

        let name = NSTextField(labelWithString: p.name)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingTail

        let path = NSTextField(labelWithString: prettyPath(p.path))
        path.font = .systemFont(ofSize: 10)
        path.textColor = .secondaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle

        let meta = NSTextField(labelWithString: p.hasClaudeHistory
            ? "\(shortRelTime(p.lastActive))  ·  Claude"
            : shortRelTime(p.lastActive))
        meta.font = .systemFont(ofSize: 10)
        meta.textColor = p.hasClaudeHistory ? .systemOrange : .tertiaryLabelColor

        for v in [name, path, meta] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                v.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            ])
        }
        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
            path.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            meta.topAnchor.constraint(equalTo: path.bottomAnchor, constant: 2),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0 else { return }
        applySelection(row)
    }

    /// Fill folder + profile from the picked project (how it was last started,
    /// else Claude Code if it has Claude history, else leave the current profile).
    private func applySelection(_ row: Int) {
        guard row >= 0, row < recentProjects.count else { return }
        let project = recentProjects[row]
        folderURL = URL(fileURLWithPath: project.path)
        folderValue.stringValue = project.path

        if let last = LaunchMemory.last(for: project.path) {
            if profilePopup.itemTitles.contains(last.profileName) {
                profilePopup.selectItem(withTitle: last.profileName)
            }
            if last.profileName == Profile.customName { customField.stringValue = last.launchCommand ?? "" }
            rcCheckbox.state = last.remoteControl ? .on : .off
        } else if project.hasClaudeHistory, profilePopup.itemTitles.contains("Claude Code") {
            profilePopup.selectItem(withTitle: "Claude Code")
        }
        profileChanged()
        // A project with past Claude conversations -> default to resuming the last one.
        if isClaudeSelected(), project.hasClaudeHistory {
            resumeCheckbox.state = .on
            worktreeCheckbox.state = .off
        } else {
            resumeCheckbox.state = .off
        }
    }

    // MARK: - Right: launch form

    private func buildForm() -> NSView {
        profilePopup.addItems(withTitles: Profile.builtins.map { $0.name } + [Profile.customName])
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged)

        customField.placeholderString = L("z. B. htop")
        customField.delegate = self
        customField.translatesAutoresizingMaskIntoConstraints = false
        customField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        folderValue.font = .systemFont(ofSize: 12)
        folderValue.textColor = .secondaryLabelColor
        folderValue.lineBreakMode = .byTruncatingMiddle
        folderValue.translatesAutoresizingMaskIntoConstraints = false
        folderValue.widthAnchor.constraint(equalToConstant: 240).isActive = true

        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        // Resume and worktree are mutually exclusive: you can't continue a past
        // conversation inside a brand-new worktree folder.
        resumeCheckbox.target = self; resumeCheckbox.action = #selector(resumeToggled)
        worktreeCheckbox.target = self; worktreeCheckbox.action = #selector(worktreeToggled)

        grid = NSGridView(views: [
            [label(L("Ordner:")), folderValue],
            [label(L("Profil:")), profilePopup],
            [label(L("Befehl:")), customField],
            [NSGridCell.emptyContentView, rcCheckbox],
            [NSGridCell.emptyContentView, resumeCheckbox],
            [label(L("Name:")),   nameField],
            [NSGridCell.emptyContentView, worktreeCheckbox],
        ])
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 14
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.row(at: 2).isHidden = true                  // "Befehl" only for Custom
        grid.row(at: 3).isHidden = !isClaudeSelected()    // "Remote Control" only for Claude Code
        grid.row(at: 4).isHidden = !isClaudeSelected()    // "Fortsetzen" only for Claude Code

        let cancelButton = NSButton(title: L("Abbrechen"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let startButton = NSButton(title: L("Starten"), target: self, action: #selector(start))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [cancelButton, startButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let container = NSView()
        for v in [grid, buttonRow] { v!.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v!) }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 13)
        return l
    }

    // MARK: - Actions

    private func isClaudeSelected() -> Bool {
        Profile.builtins.first { $0.name == profilePopup.titleOfSelectedItem }?.command == "claude"
    }

    @objc private func profileChanged() {
        grid.row(at: 2).isHidden = (profilePopup.titleOfSelectedItem != Profile.customName)
        grid.row(at: 3).isHidden = !isClaudeSelected()
        grid.row(at: 4).isHidden = !isClaudeSelected()
        updateName()
    }

    @objc private func resumeToggled()   { if resumeCheckbox.state == .on { worktreeCheckbox.state = .off } }
    @objc private func worktreeToggled() { if worktreeCheckbox.state == .on { resumeCheckbox.state = .off } }

    /// Create a brand-new project folder (navigate to a parent, type the name).
    @objc private func newProject() {
        let panel = NSSavePanel()
        panel.title = L("Neues Projekt")
        panel.prompt = L("Anlegen")
        panel.nameFieldLabel = L("Projektname:")
        panel.canCreateDirectories = true
        panel.directoryURL = ProjectScanner.roots().first
            ?? FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        table.deselectAll(nil)
        folderURL = url
        folderValue.stringValue = url.path
        // A new project most commonly starts with an AI agent.
        if profilePopup.itemTitles.contains("Claude Code") { profilePopup.selectItem(withTitle: "Claude Code") }
        profileChanged()
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL
        panel.prompt = L("Wählen")
        if panel.runModal() == .OK, let url = panel.url {
            table.deselectAll(nil)
            folderURL = url
            folderValue.stringValue = url.path
            updateName()
        }
    }

    @objc private func cancel() { close() }

    private func close() {
        // Dismiss through the presenter (otherwise the sheet stays "presented").
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
        let claude = isClaudeSelected()
        let rc = claude && rcCheckbox.state == .on
        let wantWorktree = worktreeCheckbox.state == .on
        // Resume only makes sense for Claude in an existing folder (not a fresh worktree).
        let resume = claude && resumeCheckbox.state == .on && !wantWorktree
        let title = nameField.stringValue.isEmpty ? defaultName() : nameField.stringValue

        // Optionally create a dedicated git worktree and start inside it.
        var cwd = folderURL.path
        if wantWorktree, let wt = Git.makeWorktree(in: cwd, name: title) {
            cwd = wt
        }

        SessionManager.shared.addSession(title: title, cwd: cwd, launchCommand: launch,
                                         profileName: profileName, remoteControl: rc, resume: resume)
        close()
    }

    // MARK: - Name suggestion

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

    /// Show paths relative to home with a leading "~" for readability.
    private func prettyPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
