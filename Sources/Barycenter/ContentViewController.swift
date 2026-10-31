import AppKit

/// Container that positions its tiles in a grid via frames.
final class TileContainerView: NSView {
    var columns: Int = 1
    override var isFlipped: Bool { true }   // (0,0) at top left

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

/// A tile = header + page switcher at the bottom (Terminal / Status / Notes).
/// Click selects, double-click focuses (= large).
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

        dot.textColor = session.displayState.color
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

        // Page switcher at the bottom
        pageControl.selectedSegment = 0
        pageControl.controlSize = .small
        pageControl.segmentDistribution = .fillEqually
        pageControl.target = self
        pageControl.action = #selector(pageChanged)
        pageControl.translatesAutoresizingMaskIntoConstraints = false

        // Compact dropdown for narrow tiles (shown/hidden adaptively)
        pagePopup.addItems(withTitles: Self.pageTitles)
        pagePopup.controlSize = .small
        pagePopup.target = self
        pagePopup.action = #selector(popupChanged)
        pagePopup.isHidden = true
        pagePopup.translatesAutoresizingMaskIntoConstraints = false

        // Notes editor
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
        let st = session.displayState
        dot.textColor = st.color
        let color: NSColor = st.needsYou ? .systemRed
                           : (selected ? .controlAccentColor : .separatorColor)
        layer?.borderColor = color.cgColor
        layer?.borderWidth = (selected || st.needsYou) ? 2 : 1
    }

    /// Put the keyboard into the terminal when this tile is selected and the terminal
    /// page is showing -> you can type straight after selecting a tile.
    func focusTerminalIfVisible() {
        guard selected, page == 0, let w = window else { return }
        w.makeFirstResponder(session.terminalView)
    }

    @objc private func onClick()  { SessionManager.shared.select(session.id) }
    @objc private func onDouble() {
        SessionManager.shared.select(session.id)
        SessionManager.shared.setViewMode(.focus)
    }

    // Don't let the header click swallow clicks on the ✕ button.
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        let p = closeButton.convert(event.locationInWindow, from: nil)
        return !closeButton.bounds.contains(p)
    }

    @objc private func onClose() {
        SessionManager.shared.requestClose(session.id, window: window)
    }

    // MARK: Page switcher

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
            notesTextView.string = session.notes   // take the terminal out (keeps running), show notes
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
            // Switching back to the terminal tab on the selected tile -> focus it.
            DispatchQueue.main.async { [weak self] in self?.focusTerminalIfVisible() }
        }
        v.translatesAutoresizingMaskIntoConstraints = false
        // Content must never "inflate" the tile: otherwise e.g. the terminal view, when
        // shrinking (focus→grid), pushes the bottom bar out of the tile. It must always yield.
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

    // Narrow tile (many terminals) -> hide tabs, show compact dropdown.
    override func layout() {
        super.layout()
        let narrow = bounds.width < 440
        pageControl.isHidden = narrow
        pagePopup.isHidden = !narrow
    }

    // Save notes live (kept until the session is closed).
    func textDidChange(_ notification: Notification) { session.notes = notesTextView.string }
}

/// Main area: top bar (grid/focus, pagination, + session) + tile grid.
final class ContentViewController: NSViewController {
    private let container = TileContainerView()
    private var segmented: NSSegmentedControl!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var pageLabel: NSTextField!

    /// Reusable tiles per session -> no unnecessary re-parenting of the terminals.
    private var tiles: [UUID: SessionTileView] = [:]
    /// Last selection we moved the keyboard focus to -> only refocus on real changes.
    private var lastFocusedID: UUID?

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

        // Visible toolbar strip (own background + separator) so ＋ is clearly recognizable.
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
        NotificationCenter.default.addObserver(self, selector: #selector(agentsUpdated), name: .agentsUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(presentNewSession), name: .newSessionRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(presentManager), name: .managerRequested, object: nil)
        rebuild()
    }

    private func columnsFor(_ n: Int) -> Int { n <= 1 ? 1 : (n <= 4 ? 2 : (n <= 6 ? 3 : 4)) }

    @objc private func rebuild() {
        let mgr = SessionManager.shared
        let desired: [Session] = (mgr.viewMode == .focus)
            ? (mgr.selectedSession.map { [$0] } ?? [])
            : mgr.visibleSessions()
        let desiredIDs = Set(desired.map { $0.id })

        // Remove worker tiles that are no longer visible (terminals stay kept in their tile)
        for (id, tile) in tiles where !desiredIDs.contains(id) {
            tile.removeFromSuperview()
            tiles[id] = nil
        }

        // Worker tiles in the desired order (reuse existing ones)
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
        container.layoutSubtreeIfNeeded()   // sets the new tile frames (focus→grid: smaller)

        // Second, synchronous pass per tile: container.layout() marks the tiles as needing
        // layout only DURING its own layout — too late for the same run. Without this pass a
        // reused (previously focused) tile keeps its too-wide tab bar (NSSegmentedControl does
        // not recompute the segment widths) until you touch the window.
        for tile in ordered {
            tile.needsLayout = true
            tile.layoutSubtreeIfNeeded()
            tile.needsDisplay = true
        }

        updateTopBar()

        // When the selection actually changed, move the keyboard into that tile's
        // terminal so you can type right away (periodic status refreshes won't refocus).
        if mgr.selectedID != lastFocusedID {
            lastFocusedID = mgr.selectedID
            if let id = mgr.selectedID, let tile = tiles[id] {
                DispatchQueue.main.async { tile.focusTerminalIfVisible() }
            }
        }
    }

    /// Live status from `claude agents --json`: refresh each tile's dot + border
    /// (no rebuild, no focus change) so the frame matches the sidebar at all times.
    @objc private func agentsUpdated() {
        for tile in tiles.values { tile.refresh() }
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
        // Only block if our sheet is already open (robust against ghost entries).
        if presentedViewControllers?.contains(where: { $0 is NewSessionSheetController }) == true { return }
        presentAsSheet(NewSessionSheetController())
    }
    @objc private func presentManager() {
        // Already running -> just focus it, no sheet.
        if let m = SessionManager.shared.managerSession {
            SessionManager.shared.select(m.id); SessionManager.shared.setViewMode(.focus); return
        }
        if presentedViewControllers?.contains(where: { $0 is ManagerSheetController }) == true { return }
        presentAsSheet(ManagerSheetController())
    }
    @objc private func prevPage()   { SessionManager.shared.prevPage() }
    @objc private func nextPage()   { SessionManager.shared.nextPage() }
}
