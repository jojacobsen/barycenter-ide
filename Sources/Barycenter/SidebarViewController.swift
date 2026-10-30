import AppKit

/// Tool-Panel neben der Rail: zeigt entweder die Session-Liste oder den Verwalter
/// (volle Höhe), je nach Auswahl in der Activity-Rail.
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    private let tableView = NSTableView()
    private var updatingSelection = false

    // Optionaler Notizen-Bereich unten in der Sessions-Ansicht (per Einstellung).
    private let sidebarNotes = NSTextView()
    private let sidebarNotesScroll = NSScrollView()
    private let notesToggleButton = NSButton()
    private var sidebarNotesSection: NSView!
    private var notesShownConstraint: NSLayoutConstraint!
    private var notesHiddenConstraint: NSLayoutConstraint!
    private var notesExpandedHeight: NSLayoutConstraint!
    private var notesCollapsedHeight: NSLayoutConstraint!

    /// Notizen auf-/zugeklappt (persistiert). Der Toggle selbst ist nur verfügbar,
    /// wenn das Feature in den Einstellungen aktiviert ist (showSidebarNotes).
    private var notesExpanded: Bool {
        get { UserDefaults.standard.bool(forKey: "sidebarNotesExpanded") }
        set { UserDefaults.standard.set(newValue, forKey: "sidebarNotesExpanded") }
    }

    private var sessionsView: NSView!
    private var managerView: NSView!
    private var managerHost: NSView!
    private var managerTile: SessionTileView?
    private lazy var managerPlaceholder: NSView = buildManagerPlaceholder()
    private lazy var historyView = HistoryView(frame: .zero)

    private let toolStack = NSStackView()
    private var equalHeights: [NSLayoutConstraint] = []
    private var widthConstraints: [NSLayoutConstraint] = []
    private(set) var activeTools: [Tool] = [.sessions]

    override func loadView() {
        let container = NSView()
        sessionsView = buildSessionsView()
        managerView = buildManagerView()
        sessionsView.setContentHuggingPriority(.defaultLow, for: .vertical)
        managerView.setContentHuggingPriority(.defaultLow, for: .vertical)

        toolStack.orientation = .vertical
        toolStack.distribution = .fill
        toolStack.spacing = 0
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolStack)
        // Mindesthöhe: verhindert, dass die Fitting-Size der Sidebar (und damit das
        // ganze Fenster via NSSplitViewController) auf die Werkzeugleiste zusammenfällt.
        let minHeight = container.heightAnchor.constraint(greaterThanOrEqualToConstant: 480)
        minHeight.priority = .required
        NSLayoutConstraint.activate([
            toolStack.topAnchor.constraint(equalTo: container.topAnchor),
            toolStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            minHeight,
        ])
        self.view = container

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .sessionsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadSelection), name: .selectionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .agentsUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onSettingsChanged), name: .settingsChanged, object: nil)

        showTools([.sessions])
    }

    /// Zeigt die aktiven Werkzeuge gestapelt; bei zwei genau 50/50 (mit Trennlinie).
    func showTools(_ tools: [Tool]) {
        activeTools = tools
        equalHeights.forEach { $0.isActive = false }
        equalHeights.removeAll()
        widthConstraints.forEach { $0.isActive = false }
        widthConstraints.removeAll()
        for v in toolStack.arrangedSubviews {
            toolStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        let ordered = Tool.allCases.filter { tools.contains($0) }
        var toolViews: [NSView] = []
        for (i, t) in ordered.enumerated() {
            if i > 0 {
                let sep = NSView()
                sep.wantsLayer = true
                sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
                sep.translatesAutoresizingMaskIntoConstraints = false
                toolStack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                sep.widthAnchor.constraint(equalTo: toolStack.widthAnchor).isActive = true
            }
            let view = toolView(for: t)
            view.setContentHuggingPriority(.defaultLow, for: .vertical)
            toolStack.addArrangedSubview(view)
            let wc = view.widthAnchor.constraint(equalTo: toolStack.widthAnchor)
            wc.isActive = true
            widthConstraints.append(wc)
            toolViews.append(view)
        }
        if toolViews.count >= 2 {
            for v in toolViews.dropFirst() {
                let c = v.heightAnchor.constraint(equalTo: toolViews[0].heightAnchor)
                c.isActive = true
                equalHeights.append(c)
            }
        }
        if tools.contains(.sessions) { tableView.reloadData(); reloadSelection() }
        if tools.contains(.manager) { renderManager() }
        if tools.contains(.history) { historyView.refresh() }
    }

    private func toolView(for tool: Tool) -> NSView {
        switch tool {
        case .sessions: return sessionsView
        case .manager:  return managerView
        case .history:  return historyView
        }
    }

    // MARK: Sessions-Ansicht

    private func buildSessionsView() -> NSView {
        let v = NSView()
        let header = NSTextField(labelWithString: L("SESSIONS"))
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 50
        tableView.dataSource = self
        tableView.delegate = self
        tableView.addTableColumn(NSTableColumn(identifier: .init("session")))

        let menu = NSMenu()
        let closeItem = NSMenuItem(title: L("Session schließen"), action: #selector(closeClickedRow), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        tableView.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Notizen-Bereich (optional, per Einstellung)
        let section = buildSidebarNotesSection()
        sidebarNotesSection = section

        v.addSubview(header)
        v.addSubview(scroll)
        v.addSubview(section)
        notesShownConstraint = scroll.bottomAnchor.constraint(equalTo: section.topAnchor, constant: -8)
        notesHiddenConstraint = scroll.bottomAnchor.constraint(equalTo: v.bottomAnchor)
        // Liste behält Mindesthöhe (über der Notiz-Höhe): bei engem Panel + offenen Notizen
        // schrumpfen die Notizen, nicht die Liste.
        let listMinHeight = scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        listMinHeight.priority = .init(600)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: v.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            listMinHeight,
            section.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            section.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            section.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        applySidebarNotesVisibility()
        return v
    }

    private func buildSidebarNotesSection() -> NSView {
        let section = NSView()
        section.translatesAutoresizingMaskIntoConstraints = false   // sonst fixiert der 0×0-Startframe die Höhe auf 0
        let sep = NSBox(); sep.boxType = .separator

        // Klickbarer Header = Toggle zum Auf-/Zuklappen der Notizen.
        notesToggleButton.isBordered = false
        notesToggleButton.bezelStyle = .regularSquare
        notesToggleButton.setButtonType(.momentaryChange)
        notesToggleButton.alignment = .left
        notesToggleButton.focusRingType = .none
        notesToggleButton.contentTintColor = .secondaryLabelColor
        notesToggleButton.target = self
        notesToggleButton.action = #selector(toggleNotes)

        sidebarNotes.isRichText = false
        sidebarNotes.font = .systemFont(ofSize: 12)
        sidebarNotes.delegate = self
        sidebarNotes.string = UserDefaults.standard.string(forKey: "sidebarNotes") ?? ""
        sidebarNotes.textContainerInset = NSSize(width: 4, height: 4)
        sidebarNotes.isVerticallyResizable = true
        sidebarNotes.autoresizingMask = [.width]
        sidebarNotes.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        sidebarNotes.textContainer?.widthTracksTextView = true
        sidebarNotes.drawsBackground = false
        sidebarNotesScroll.documentView = sidebarNotes
        sidebarNotesScroll.hasVerticalScroller = true
        sidebarNotesScroll.borderType = .noBorder
        sidebarNotesScroll.drawsBackground = true
        sidebarNotesScroll.backgroundColor = NSColor(white: 1, alpha: 0.08)
        sidebarNotesScroll.wantsLayer = true
        sidebarNotesScroll.layer?.cornerRadius = 6
        sidebarNotesScroll.layer?.borderWidth = 1
        sidebarNotesScroll.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        [sep, notesToggleButton, sidebarNotesScroll].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false; section.addSubview($0)
        }
        let boxBottom = sidebarNotesScroll.bottomAnchor.constraint(equalTo: section.bottomAnchor, constant: -8)
        boxBottom.priority = .init(500)   // bricht sauber, wenn eingeklappt (Box versteckt)
        NSLayoutConstraint.activate([
            sep.topAnchor.constraint(equalTo: section.topAnchor),
            sep.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            notesToggleButton.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 4),
            notesToggleButton.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 10),
            notesToggleButton.trailingAnchor.constraint(lessThanOrEqualTo: section.trailingAnchor, constant: -10),
            sidebarNotesScroll.topAnchor.constraint(equalTo: notesToggleButton.bottomAnchor, constant: 6),
            sidebarNotesScroll.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 6),
            sidebarNotesScroll.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: -6),
            boxBottom,
        ])
        // Zwei Höhen: eingeklappt = nur der Toggle-Header; ausgeklappt = Header + Box.
        notesCollapsedHeight = section.heightAnchor.constraint(equalToConstant: 34)
        notesCollapsedHeight.priority = .init(500)
        notesExpandedHeight = section.heightAnchor.constraint(equalToConstant: 214)
        notesExpandedHeight.priority = .init(500)
        return section
    }

    /// Feature an/aus (Einstellung) steuert, ob der Toggle überhaupt da ist.
    private func applySidebarNotesVisibility() {
        let featureOn = AppSettings.shared.showSidebarNotes
        sidebarNotesSection?.isHidden = !featureOn
        notesShownConstraint?.isActive = featureOn
        notesHiddenConstraint?.isActive = !featureOn
        if featureOn {
            applyNotesExpansion()
        } else {
            notesExpandedHeight?.isActive = false
            notesCollapsedHeight?.isActive = false
        }
        sessionsView?.needsLayout = true
        sessionsView?.layoutSubtreeIfNeeded()
    }

    /// Auf-/zugeklappten Zustand auf Höhe, Box-Sichtbarkeit und Chevron anwenden.
    private func applyNotesExpansion() {
        let expanded = notesExpanded
        notesExpandedHeight?.isActive = expanded
        notesCollapsedHeight?.isActive = !expanded
        sidebarNotesScroll.isHidden = !expanded
        let chevron = expanded ? "▾" : "▸"
        notesToggleButton.attributedTitle = NSAttributedString(
            string: "\(chevron)  " + L("NOTIZEN"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
    }

    @objc private func toggleNotes() {
        notesExpanded.toggle()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            applyNotesExpansion()
            sessionsView?.layoutSubtreeIfNeeded()
        }
    }

    @objc private func onSettingsChanged() { applySidebarNotesVisibility() }

    func textDidChange(_ notification: Notification) {
        if (notification.object as? NSTextView) === sidebarNotes {
            UserDefaults.standard.set(sidebarNotes.string, forKey: "sidebarNotes")
        }
    }

    // MARK: Verwalter-Ansicht (volle Höhe)

    private func buildManagerView() -> NSView {
        let v = NSView()
        let label = NSTextField(labelWithString: L("LEITSTELLE"))
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .systemPurple
        label.translatesAutoresizingMaskIntoConstraints = false

        managerHost = NSView()
        managerHost.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(label)
        v.addSubview(managerHost)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: v.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            managerHost.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            managerHost.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6),
            managerHost.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6),
            managerHost.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -6),
        ])
        return v
    }

    private func renderManager() {
        let mgr = SessionManager.shared
        if let m = mgr.managerSession {
            if managerTile?.session.id != m.id {
                managerTile?.removeFromSuperview()
                managerTile = SessionTileView(session: m)
            }
            let tile = managerTile!
            tile.refresh()
            if tile.superview !== managerHost {
                managerHost.subviews.forEach { $0.removeFromSuperview() }
                pin(tile)
            }
        } else {
            managerTile = nil
            if managerPlaceholder.superview !== managerHost {
                managerHost.subviews.forEach { $0.removeFromSuperview() }
                pin(managerPlaceholder)
            }
        }
    }

    private func pin(_ v: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        managerHost.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: managerHost.topAnchor),
            v.leadingAnchor.constraint(equalTo: managerHost.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: managerHost.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: managerHost.bottomAnchor),
        ])
    }

    private func buildManagerPlaceholder() -> NSView {
        let v = NSView()
        let btn = NSButton(title: L("＋ KI-Verwalter starten"), target: self, action: #selector(startManager))
        btn.bezelStyle = .rounded
        btn.translatesAutoresizingMaskIntoConstraints = false
        let hint = NSTextField(labelWithString: L("Dein Leitstand-Agent"))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(btn); v.addSubview(hint)
        NSLayoutConstraint.activate([
            btn.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            btn.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            hint.topAnchor.constraint(equalTo: btn.bottomAnchor, constant: 8),
            hint.centerXAnchor.constraint(equalTo: v.centerXAnchor),
        ])
        return v
    }

    @objc private func startManager() { NotificationCenter.default.post(name: .managerRequested, object: nil) }

    // MARK: Updates

    @objc private func reload() {
        tableView.reloadData()
        reloadSelection()
        if activeTools.contains(.manager) { renderManager() }
    }

    @objc private func reloadSelection() {
        let mgr = SessionManager.shared
        guard let id = mgr.selectedID,
              let idx = mgr.workerSessions.firstIndex(where: { $0.id == id }) else { return }
        updatingSelection = true
        tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        updatingSelection = false
    }

    // MARK: Data source / delegate

    func numberOfRows(in tableView: NSTableView) -> Int { SessionManager.shared.workerSessions.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let s = SessionManager.shared.workerSessions[row]
        let cell = NSTableCellView()

        let name = NSTextField(labelWithString: s.title)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false

        let pills = NSStackView(views: s.statusBadges().map { makePill($0) })
        pills.orientation = .horizontal
        pills.spacing = 4
        pills.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(name)
        cell.addSubview(pills)
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            name.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            name.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
            pills.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            pills.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            pills.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 5),
        ])
        return cell
    }

    private func makePill(_ badge: SessionBadge) -> NSView {
        let label = NSTextField(labelWithString: badge.text)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = badge.color
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 4
        bg.layer?.backgroundColor = badge.color.withAlphaComponent(0.15).cgColor
        bg.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: bg.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -2),
        ])
        return bg
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < SessionManager.shared.workerSessions.count else { return }
        SessionManager.shared.select(SessionManager.shared.workerSessions[row].id)
    }

    @objc private func closeClickedRow() {
        let row = tableView.clickedRow
        guard row >= 0, row < SessionManager.shared.workerSessions.count else { return }
        SessionManager.shared.requestClose(SessionManager.shared.workerSessions[row].id, window: view.window)
    }
}

#if DEBUG
// MARK: - Test-Hooks (nur Layout-Regressionstests; greifen auf private Member zu)
extension SidebarViewController {
    /// Höhe des Session-Listen-Scrollbereichs nach dem Layout. > 0 ⇒ Liste sichtbar.
    var test_sessionsListHeight: CGFloat { tableView.enclosingScrollView?.frame.height ?? 0 }

    /// Notizen-Toggle verfügbar (Section sichtbar mit echter Höhe)?
    var test_notesSectionVisible: Bool {
        guard let s = sidebarNotesSection else { return false }
        return !s.isHidden && s.frame.height > 1
    }

    /// Notiz-Textbox tatsächlich aufgeklappt und sichtbar?
    var test_notesBoxVisible: Bool {
        !sidebarNotesScroll.isHidden && sidebarNotesScroll.frame.height > 1
    }

    /// Notizen auf-/zuklappen (Test-Zugang) und Layout neu anwenden.
    func test_setNotesExpanded(_ expanded: Bool) {
        notesExpanded = expanded
        applyNotesExpansion()
    }

    /// Breiten aller echten Werkzeug-Ansichten (ohne die 1px-Trennlinien).
    var test_toolViewWidths: [CGFloat] {
        toolStack.arrangedSubviews.filter { $0.frame.height > 2 }.map { $0.frame.width }
    }

    /// Breite des Werkzeug-Stacks (Soll-Breite jeder Werkzeug-Ansicht).
    var test_panelWidth: CGFloat { toolStack.frame.width }

    /// Aktive Werkzeuge einstellen (Test-Zugang zur internen API).
    func test_showTools(_ tools: [Tool]) { showTools(tools) }
}
#endif
