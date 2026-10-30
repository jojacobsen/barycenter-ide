import AppKit

/// Container, der seine Kacheln in einem Raster per Frame positioniert.
final class TileContainerView: NSView {
    var columns: Int = 1
    override var isFlipped: Bool { true }   // (0,0) oben links

    override func layout() {
        super.layout()
        let tiles = subviews
        guard !tiles.isEmpty else { return }
        let cols = max(1, columns)
        let rows = Int(ceil(Double(tiles.count) / Double(cols)))
        let gap: CGFloat = 8
        let w = (bounds.width  - gap * CGFloat(cols + 1)) / CGFloat(cols)
        let h = (bounds.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
        for (i, tile) in tiles.enumerated() {
            let c = i % cols, r = i / cols
            tile.frame = NSRect(x: gap + CGFloat(c) * (w + gap),
                                y: gap + CGFloat(r) * (h + gap),
                                width: max(1, w), height: max(1, h))
        }
    }
}

/// Eine Kachel = Kopfzeile + Seiten-Umschalter unten (Terminal / Status / Notizen).
/// Klick wählt aus, Doppelklick fokussiert (= groß).
final class SessionTileView: NSView, NSTextViewDelegate, NSGestureRecognizerDelegate {
    let session: Session
    private let dot = NSTextField(labelWithString: "●")
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    private var selected = false

    private let contentContainer = NSView()
    private let pageControl = NSSegmentedControl(labels: [L("Terminal"), L("Status"), L("Notizen"), L("Diff"), L("Dateien")],
                                                 trackingMode: .selectOne, target: nil, action: nil)
    private let pagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private static let pageTitles = [L("Terminal"), L("Status"), L("Notizen"), L("Diff"), L("Dateien")]
    private let statusView = SessionStatusView(frame: .zero)
    private let notesScroll = NSScrollView()
    private let notesTextView = NSTextView()
    private lazy var diffView = SessionDiffView(session: session)
    private lazy var filesView = SessionFilesView(session: session)
    private var page = 0
    private var statusTimer: Timer?

    init(session: Session) {
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        dot.textColor = session.status.color
        dot.font = .systemFont(ofSize: 10)

        let name = NSTextField(labelWithString: session.title)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.target = self
        closeButton.action = #selector(onClose)
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 13)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        closeButton.toolTip = L("Session schließen")

        let headerStack = NSStackView(views: [dot, name, closeButton])
        headerStack.orientation = .horizontal
        headerStack.distribution = .fill
        headerStack.spacing = 6
        headerStack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        // Seiten-Umschalter unten
        pageControl.selectedSegment = 0
        pageControl.controlSize = .small
        pageControl.segmentDistribution = .fillEqually
        pageControl.target = self
        pageControl.action = #selector(pageChanged)
        pageControl.translatesAutoresizingMaskIntoConstraints = false

        // Kompaktes Dropdown für schmale Kacheln (wird adaptiv ein-/ausgeblendet)
        pagePopup.addItems(withTitles: Self.pageTitles)
        pagePopup.controlSize = .small
        pagePopup.target = self
        pagePopup.action = #selector(popupChanged)
        pagePopup.isHidden = true
        pagePopup.translatesAutoresizingMaskIntoConstraints = false

        // Notizen-Editor
        notesTextView.isRichText = false
        notesTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        notesTextView.isAutomaticQuoteSubstitutionEnabled = false
        notesTextView.isAutomaticDashSubstitutionEnabled = false
        notesTextView.delegate = self
        notesTextView.textContainerInset = NSSize(width: 6, height: 6)
        notesTextView.minSize = NSSize(width: 0, height: 0)
        notesTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        notesTextView.isVerticallyResizable = true
        notesTextView.isHorizontallyResizable = false
        notesTextView.autoresizingMask = [.width]
        notesTextView.textContainer?.widthTracksTextView = true
        notesScroll.documentView = notesTextView
        notesScroll.hasVerticalScroller = true
        notesScroll.borderType = .noBorder

        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(headerStack)
        addSubview(contentContainer)
        addSubview(pageControl)
        addSubview(pagePopup)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerStack.heightAnchor.constraint(equalToConstant: 24),

            contentContainer.topAnchor.constraint(equalTo: headerStack.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),

            pageControl.topAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: 3),
            pageControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            pageControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            pageControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            pagePopup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            pagePopup.centerYAnchor.constraint(equalTo: pageControl.centerYAnchor),
        ])

        let single = NSClickGestureRecognizer(target: self, action: #selector(onClick))
        single.delegate = self
        headerStack.addGestureRecognizer(single)
        let double = NSClickGestureRecognizer(target: self, action: #selector(onDouble))
        double.numberOfClicksRequired = 2
        double.delegate = self
        headerStack.addGestureRecognizer(double)

        showPage(0)
        refresh()
    }

    deinit { statusTimer?.invalidate() }
    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ v: Bool) { selected = v; refresh() }

    func refresh() {
        dot.textColor = session.status.color
        let color: NSColor = session.status == .attention ? .systemRed
                           : (selected ? .controlAccentColor : .separatorColor)
        layer?.borderColor = color.cgColor
        layer?.borderWidth = (selected || session.status == .attention) ? 2 : 1
    }

    @objc private func onClick()  { SessionManager.shared.select(session.id) }
    @objc private func onDouble() {
        SessionManager.shared.select(session.id)
        SessionManager.shared.setViewMode(.focus)
    }

    // Klicks auf den ✕-Button nicht vom Header-Klick abfangen lassen.
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        let p = closeButton.convert(event.locationInWindow, from: nil)
        return !closeButton.bounds.contains(p)
    }

    @objc private func onClose() {
        SessionManager.shared.requestClose(session.id, window: window)
    }

    // MARK: Seiten-Umschalter

    private func showPage(_ p: Int) {
        page = p
        pageControl.selectedSegment = p
        pagePopup.selectItem(at: p)
        contentContainer.subviews.forEach { $0.removeFromSuperview() }

        let v: NSView
        switch p {
        case 1:
            statusView.refresh(for: session)
            startStatusTimer()
            v = statusView
        case 2:
            notesTextView.string = session.notes   // Terminal rausnehmen (läuft weiter), Notizen zeigen
            stopStatusTimer()
            v = notesScroll
        case 3:
            diffView.refresh()
            stopStatusTimer()
            v = diffView
        case 4:
            filesView.reload()
            stopStatusTimer()
            v = filesView
        default:
            stopStatusTimer()
            v = session.terminalView
        }
        v.translatesAutoresizingMaskIntoConstraints = false
        // Inhalt darf die Kachel nie „aufblähen": sonst drückt z.B. der Terminal-View beim
        // Schrumpfen (Fokus→Grid) die untere Leiste aus der Kachel. Er muss immer nachgeben.
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentContainer.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            v.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private func startStatusTimer() {
        stopStatusTimer()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.page == 1 else { return }
            self.statusView.refresh(for: self.session)
        }
    }
    private func stopStatusTimer() { statusTimer?.invalidate(); statusTimer = nil }

    @objc private func pageChanged() { showPage(pageControl.selectedSegment) }
    @objc private func popupChanged() { showPage(pagePopup.indexOfSelectedItem) }

    // Schmale Kachel (viele Terminals) -> Tabs ausblenden, kompaktes Dropdown zeigen.
    override func layout() {
        super.layout()
        let narrow = bounds.width < 440
        pageControl.isHidden = narrow
        pagePopup.isHidden = !narrow
    }

    // Notizen live speichern (bleiben bis zum Schließen der Session erhalten).
    func textDidChange(_ notification: Notification) { session.notes = notesTextView.string }
}

/// Hauptbereich: Topbar (Grid/Fokus, Pagination, + Session) + Kachel-Raster.
final class ContentViewController: NSViewController {
    private let container = TileContainerView()
    private var segmented: NSSegmentedControl!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var pageLabel: NSTextField!

    /// Wiederverwendbare Kacheln pro Session -> kein unnötiges Re-Parenting der Terminals.
    private var tiles: [UUID: SessionTileView] = [:]

    override func loadView() {
        let root = NSView()

        segmented = NSSegmentedControl(labels: [L("▦ Grid"), L("◻ Fokus")],
                                       trackingMode: .selectOne,
                                       target: self, action: #selector(modeChanged))
        segmented.selectedSegment = 0

        prevButton = NSButton(title: "‹", target: self, action: #selector(prevPage))
        prevButton.bezelStyle = .rounded
        nextButton = NSButton(title: "›", target: self, action: #selector(nextPage))
        nextButton.bezelStyle = .rounded

        pageLabel = NSTextField(labelWithString: String(format: L("Seite %d/%d"), 1, 1))
        pageLabel.font = .systemFont(ofSize: 11)
        pageLabel.textColor = .secondaryLabelColor

        let addButton = NSButton(title: L("＋ Neue Session"), target: self, action: #selector(addSession))
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "t"
        addButton.keyEquivalentModifierMask = .command

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let bar = NSStackView(views: [segmented, spacer, prevButton, pageLabel, nextButton, addButton])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        bar.translatesAutoresizingMaskIntoConstraints = false

        // Sichtbare Toolbar-Leiste (eigener Hintergrund + Trennlinie), damit ＋ klar erkennbar ist.
        let barBackground = NSVisualEffectView()
        barBackground.material = .titlebar
        barBackground.blendingMode = .withinWindow
        barBackground.translatesAutoresizingMaskIntoConstraints = false
        barBackground.addSubview(bar)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(barBackground)
        root.addSubview(separator)
        root.addSubview(container)
        NSLayoutConstraint.activate([
            barBackground.topAnchor.constraint(equalTo: root.topAnchor),
            barBackground.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            barBackground.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            bar.topAnchor.constraint(equalTo: barBackground.topAnchor),
            bar.leadingAnchor.constraint(equalTo: barBackground.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: barBackground.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: barBackground.bottomAnchor),

            separator.topAnchor.constraint(equalTo: barBackground.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            container.topAnchor.constraint(equalTo: separator.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        self.view = root

        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .sessionsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .selectionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(presentNewSession), name: .newSessionRequested, object: nil)
        rebuild()
    }

    private func columnsFor(_ n: Int) -> Int { n <= 1 ? 1 : (n <= 4 ? 2 : (n <= 6 ? 3 : 4)) }

    @objc private func rebuild() {
        let mgr = SessionManager.shared
        let desired: [Session] = (mgr.viewMode == .focus)
            ? (mgr.selectedSession.map { [$0] } ?? [])
            : mgr.visibleSessions()
        let desiredIDs = Set(desired.map { $0.id })

        // Nicht mehr sichtbare Worker-Kacheln entfernen (Terminals bleiben in ihrer Kachel erhalten)
        for (id, tile) in tiles where !desiredIDs.contains(id) {
            tile.removeFromSuperview()
            tiles[id] = nil
        }

        // Worker-Kacheln in gewünschter Reihenfolge (bestehende wiederverwenden)
        var ordered: [SessionTileView] = []
        for s in desired {
            let tile = tiles[s.id] ?? SessionTileView(session: s)
            tiles[s.id] = tile
            tile.setSelected(s.id == mgr.selectedID)
            tile.refresh()
            ordered.append(tile)
        }
        container.subviews = ordered
        container.columns = columnsFor(desired.count)
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()   // setzt die neuen Kachel-Frames (Fokus→Grid: kleiner)

        // Zweiter, synchroner Pass pro Kachel: container.layout() markiert die Kacheln erst
        // WÄHREND seines eigenen Layouts als änderungsbedürftig — zu spät für denselben
        // Durchlauf. Ohne diesen Pass behält eine wiederverwendete (vormals fokussierte) Kachel
        // ihre zu breite Tab-Leiste (NSSegmentedControl rechnet die Segmentbreiten nicht neu),
        // bis man das Fenster anfasst.
        for tile in ordered {
            tile.needsLayout = true
            tile.layoutSubtreeIfNeeded()
            tile.needsDisplay = true
        }

        updateTopBar()
    }

    private func updateTopBar() {
        let mgr = SessionManager.shared
        segmented.selectedSegment = (mgr.viewMode == .grid) ? 0 : 1
        pageLabel.stringValue = String(format: L("Seite %d/%d"), mgr.page + 1, mgr.pageCount)
        let showPaging = mgr.pageCount > 1 && mgr.viewMode == .grid
        prevButton.isHidden = !showPaging
        nextButton.isHidden = !showPaging
        pageLabel.isHidden = !showPaging
        prevButton.isEnabled = mgr.page > 0
        nextButton.isEnabled = mgr.page < mgr.pageCount - 1
    }

    @objc private func modeChanged() {
        SessionManager.shared.setViewMode(segmented.selectedSegment == 0 ? .grid : .focus)
    }
    @objc private func addSession() {
        NotificationCenter.default.post(name: .newSessionRequested, object: nil)
    }
    @objc private func presentNewSession() {
        // Nur blocken, wenn unser Sheet bereits offen ist (robust gegen Ghost-Einträge).
        if presentedViewControllers?.contains(where: { $0 is NewSessionSheetController }) == true { return }
        presentAsSheet(NewSessionSheetController())
    }
    @objc private func prevPage()   { SessionManager.shared.prevPage() }
    @objc private func nextPage()   { SessionManager.shared.nextPage() }
}
