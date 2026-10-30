import AppKit
import Highlightr

/// Session-Seite „Dateien": Mini-Dateibrowser (+ rekursive Namenssuche) des Session-Ordners
/// + Text-Editor mit Syntax-Highlighting. Warnt bei ungespeicherten Änderungen.
final class SessionFilesView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSSearchFieldDelegate {
    private let rootPath: String
    private var currentPath: String
    private var entries: [(name: String, isDir: Bool)] = []
    private var searchHits: [String] = []     // absolute Pfade bei aktiver Suche
    private var searching = false
    private var loadedFile: String?
    private var dirty = false
    private var suppressDirty = false
    private var searchWork: DispatchWorkItem?

    private let searchField = NSSearchField()
    private let pathLabel = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let codeStorage: CodeAttributedString
    private let editor: NSTextView
    private let fileLabel = NSTextField(labelWithString: L("— keine Datei —"))
    private let saveButton = NSButton(title: L("Speichern"), target: nil, action: nil)
    private let editorScroll = NSScrollView()
    private var lineNumberRuler: LineNumberRulerView?
    private let editorArea = NSView()
    private let modeToggle = NSSegmentedControl(labels: [L("Editor"), L("Vorschau")], trackingMode: .selectOne, target: nil, action: nil)
    private lazy var preview = MarkdownPreviewView(frame: .zero)
    private var isMarkdown = false

    init(session: Session) {
        rootPath = session.cwd
        currentPath = session.cwd

        let storage = CodeAttributedString()
        storage.highlightr.setTheme(to: "atom-one-dark")
        storage.highlightr.theme.codeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        lm.addTextContainer(tc)
        codeStorage = storage
        editor = NSTextView(frame: .zero, textContainer: tc)

        super.init(frame: .zero)

        searchField.placeholderString = L("Dateien suchen (rekursiv)…")
        searchField.controlSize = .small
        searchField.sendsSearchStringImmediately = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 20
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.addTableColumn(NSTableColumn(identifier: .init("f")))
        let listScroll = NSScrollView()
        listScroll.documentView = table
        listScroll.hasVerticalScroller = true
        listScroll.drawsBackground = false
        listScroll.translatesAutoresizingMaskIntoConstraints = false

        let sep = NSBox(); sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        fileLabel.font = .systemFont(ofSize: 10, weight: .medium)
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.translatesAutoresizingMaskIntoConstraints = false

        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .small
        saveButton.isEnabled = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isEditable = false
        editor.delegate = self
        editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.drawsBackground = true
        editor.backgroundColor = storage.highlightr.theme.themeBackgroundColor
        editor.insertionPointColor = .white
        editorScroll.documentView = editor
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .noBorder
        editorScroll.translatesAutoresizingMaskIntoConstraints = false

        // Zeilennummern-Leiste (optional, per Einstellung).
        let ruler = LineNumberRulerView(textView: editor)
        ruler.applyTheme(dark: true)
        editorScroll.verticalRulerView = ruler
        editorScroll.hasVerticalRuler = true
        editorScroll.rulersVisible = AppSettings.shared.showEditorLineNumbers
        lineNumberRuler = ruler

        modeToggle.selectedSegment = 0
        modeToggle.controlSize = .small
        modeToggle.target = self
        modeToggle.action = #selector(modeChanged)
        modeToggle.isHidden = true
        modeToggle.setContentHuggingPriority(.required, for: .horizontal)

        editorArea.translatesAutoresizingMaskIntoConstraints = false

        let fileBar = NSStackView(views: [fileLabel, modeToggle, saveButton])
        fileBar.orientation = .horizontal
        fileLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        fileBar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField)
        addSubview(pathLabel)
        addSubview(listScroll)
        addSubview(sep)
        addSubview(fileBar)
        addSubview(editorArea)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            pathLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            pathLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            listScroll.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 4),
            listScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            listScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            listScroll.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.34),

            sep.topAnchor.constraint(equalTo: listScroll.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),

            fileBar.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 4),
            fileBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            fileBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            editorArea.topAnchor.constraint(equalTo: fileBar.bottomAnchor, constant: 4),
            editorArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            editorArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            editorArea.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        showEditorMode()
        reloadDir()

        NotificationCenter.default.addObserver(self, selector: #selector(onSettingsChanged),
                                               name: .settingsChanged, object: nil)
    }

    @objc private func onSettingsChanged() {
        editorScroll.rulersVisible = AppSettings.shared.showEditorLineNumbers
        lineNumberRuler?.redraw()
    }

    // MARK: Editor/Vorschau-Umschalter

    @objc private func modeChanged() {
        modeToggle.selectedSegment == 1 ? showPreview() : showEditorMode()
    }
    private func showEditorMode() {
        preview.removeFromSuperview()
        if editorScroll.superview !== editorArea {
            editorArea.addSubview(editorScroll)
            pinInArea(editorScroll)
        }
    }
    private func showPreview() {
        editorScroll.removeFromSuperview()
        preview.translatesAutoresizingMaskIntoConstraints = false
        if preview.superview !== editorArea {
            editorArea.addSubview(preview)
            pinInArea(preview)
        }
        preview.render(editor.string)
    }
    private func pinInArea(_ v: NSView) {
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: editorArea.topAnchor),
            v.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: editorArea.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func reload() { if !searching { reloadDir() } }

    // MARK: Verzeichnis / Suche

    private func reloadDir() {
        let fm = FileManager.default
        var items: [(String, Bool)] = []
        if currentPath != rootPath { items.append(("..", true)) }
        if let names = try? fm.contentsOfDirectory(atPath: currentPath) {
            let dirs = names.filter { isDir(currentPath + "/" + $0) }.sorted()
            let files = names.filter { !isDir(currentPath + "/" + $0) }.sorted()
            items += dirs.map { ($0, true) } + files.map { ($0, false) }
        }
        entries = items.map { (name: $0.0, isDir: $0.1) }
        pathLabel.stringValue = displayPath()
        table.reloadData()
    }

    // Live-Suche mit kleinem Debounce; leeres Feld schaltet sofort zurück zur Ordneransicht.
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        searchWork?.cancel()
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { searching = false; reloadDir(); return }
        let work = DispatchWorkItem { [weak self] in self?.searchChanged() }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    @objc private func searchChanged() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { searching = false; reloadDir(); return }
        let base = currentPath
        DispatchQueue.global(qos: .userInitiated).async {
            let skip: Set<String> = [".git", "node_modules", ".build", "DerivedData", ".next", "dist", "Pods",
                                     ".venv", "venv", "virtenv", "site-packages", "__pycache__", ".cache",
                                     "Library", ".Trash", ".npm", ".gradle", "target", ".tox"]
            let fm = FileManager.default
            var hits: [String] = []
            func walk(_ dir: String, _ depth: Int) {
                guard hits.count < 500, depth < 12 else { return }
                guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
                for n in names {
                    let full = dir + "/" + n
                    var d: ObjCBool = false
                    fm.fileExists(atPath: full, isDirectory: &d)
                    if d.boolValue {
                        if !skip.contains(n) { walk(full, depth + 1) }
                    } else if n.range(of: q, options: .caseInsensitive) != nil {
                        hits.append(full)
                        if hits.count >= 500 { return }
                    }
                }
            }
            walk(base, 0)
            DispatchQueue.main.async {
                self.searchHits = hits.sorted()
                self.searching = true
                self.pathLabel.stringValue = String(format: L("🔎 %d Treffer für „%@\""), hits.count, q)
                self.table.reloadData()
            }
        }
    }

    private func isDir(_ path: String) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
    }

    private func displayPath() -> String {
        let rel = currentPath.hasPrefix(rootPath) ? String(currentPath.dropFirst(rootPath.count)) : currentPath
        return "📁 " + (rel.isEmpty ? (rootPath as NSString).lastPathComponent : "…" + rel)
    }

    @objc private func rowClicked() {
        let row = table.clickedRow
        if searching {
            guard row >= 0, row < searchHits.count else { return }
            let path = searchHits[row]
            confirmDiscardIfNeeded { [weak self] in self?.load(path) }
        } else {
            guard row >= 0, row < entries.count else { return }
            let e = entries[row]
            if e.name == ".." {
                currentPath = (currentPath as NSString).deletingLastPathComponent
                reloadDir()
            } else if e.isDir {
                currentPath = currentPath + "/" + e.name
                reloadDir()
            } else {
                confirmDiscardIfNeeded { [weak self] in self?.load(self!.currentPath + "/" + e.name) }
            }
        }
    }

    // MARK: Laden / Speichern / Dirty

    private func load(_ path: String) {
        guard let data = FileManager.default.contents(atPath: path) else { return }
        suppressDirty = true
        if data.count > 2_000_000 {
            loadedFile = nil; codeStorage.language = nil; show(L("(Datei zu groß zum Anzeigen)"), editable: false)
        } else if let text = String(data: data, encoding: .utf8) {
            loadedFile = path
            codeStorage.language = Self.language(for: path)
            show(text, editable: true)
        } else {
            loadedFile = nil; codeStorage.language = nil; show(L("(Binärdatei – nicht darstellbar)"), editable: false)
        }
        let ext = (path as NSString).pathExtension.lowercased()
        isMarkdown = (loadedFile != nil) && (ext == "md" || ext == "markdown")
        modeToggle.isHidden = !isMarkdown
        modeToggle.selectedSegment = 0
        showEditorMode()
        dirty = false
        suppressDirty = false
        updateFileBar()
    }

    private func show(_ text: String, editable: Bool) {
        editor.string = text
        editor.isEditable = editable
        lineNumberRuler?.redraw()   // programmatische Textänderung sendet kein didChange
    }

    func textDidChange(_ notification: Notification) {
        guard !suppressDirty, editor.isEditable, loadedFile != nil else { return }
        if !dirty { dirty = true; updateFileBar() }
    }

    private func updateFileBar() {
        if let f = loadedFile {
            let name = (f as NSString).lastPathComponent
            fileLabel.stringValue = dirty ? String(format: L("● %@  — ungesicherte Änderungen"), name) : name
            fileLabel.textColor = dirty ? .systemOrange : .labelColor
            saveButton.isEnabled = dirty
        } else {
            fileLabel.stringValue = L("— keine Datei —")
            fileLabel.textColor = .secondaryLabelColor
            saveButton.isEnabled = false
        }
    }

    @objc private func saveClicked() { doSave() }

    private func doSave() {
        guard let path = loadedFile else { return }
        do {
            try editor.string.write(toFile: path, atomically: true, encoding: .utf8)
            dirty = false
            updateFileBar()
        } catch {
            fileLabel.stringValue = L("⚠︎ Fehler beim Speichern")
            fileLabel.textColor = .systemRed
        }
    }

    /// Fragt bei ungespeicherten Änderungen nach, bevor etwas anderes geladen wird.
    private func confirmDiscardIfNeeded(_ proceed: @escaping () -> Void) {
        guard dirty, loadedFile != nil, let win = window else { proceed(); return }
        let alert = NSAlert()
        alert.messageText = L("Ungespeicherte Änderungen")
        alert.informativeText = String(format: L("Die Änderungen an %@ sind nicht gespeichert."), (loadedFile! as NSString).lastPathComponent)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Speichern"))
        alert.addButton(withTitle: L("Verwerfen"))
        alert.addButton(withTitle: L("Abbrechen"))
        alert.beginSheetModal(for: win) { resp in
            switch resp {
            case .alertFirstButtonReturn:  self.doSave(); proceed()
            case .alertSecondButtonReturn: self.dirty = false; proceed()
            default: break
            }
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { searching ? searchHits.count : entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let title: String
        if searching {
            let rel = searchHits[row].hasPrefix(rootPath + "/")
                ? String(searchHits[row].dropFirst(rootPath.count + 1)) : searchHits[row]
            title = "📄 " + rel
        } else {
            let e = entries[row]
            title = (e.isDir ? "📁 " : "📄 ") + e.name
        }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    /// Dateiendung -> highlight.js-Sprache (nil = kein Highlighting).
    private static func language(for path: String) -> String? {
        let name = (path as NSString).lastPathComponent.lowercased()
        if name == ".env" || name.hasSuffix(".env") { return "ini" }
        switch (path as NSString).pathExtension.lowercased() {
        case "py":                      return "python"
        case "ts", "tsx":               return "typescript"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "json":                    return "json"
        case "yml", "yaml":             return "yaml"
        case "swift":                   return "swift"
        case "sh", "bash", "zsh":       return "bash"
        case "md", "markdown":          return "markdown"
        case "html", "htm", "xml":      return "xml"
        case "css":                     return "css"
        case "scss", "sass":            return "scss"
        case "go":                      return "go"
        case "rs":                      return "rust"
        case "rb":                      return "ruby"
        case "java":                    return "java"
        case "kt", "kts":               return "kotlin"
        case "c", "h":                  return "c"
        case "cpp", "cc", "hpp":        return "cpp"
        case "cs":                      return "csharp"
        case "php":                     return "php"
        case "sql":                     return "sql"
        case "toml":                    return "ini"
        default:                        return nil
        }
    }
}
