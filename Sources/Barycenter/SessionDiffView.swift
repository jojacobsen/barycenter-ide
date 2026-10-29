import AppKit

/// Session-Seite „Diff": zeigt git status + diff des Session-Ordners (farbig, read-only).
final class SessionDiffView: NSView {
    private let session: Session
    private let textView = NSTextView()
    private let scroll = NSScrollView()

    init(session: Session) {
        self.session = session
        super.init(frame: .zero)

        textView.isEditable = false
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "↻ Aktualisieren", target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroll)
        addSubview(refreshButton)
        NSLayoutConstraint.activate([
            refreshButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func refresh() {
        let cwd = session.cwd
        setPlain("Lade …")
        DispatchQueue.global(qos: .userInitiated).async {
            guard Git.isRepo(cwd) else {
                DispatchQueue.main.async { self.setPlain("Kein Git-Repo in diesem Ordner.") }
                return
            }
            let status = Git.run(["status", "--short", "--branch"], cwd: cwd)
            let diff = Git.run(["diff"], cwd: cwd)
            DispatchQueue.main.async { self.render(status: status, diff: diff) }
        }
    }

    private func setPlain(_ s: String) {
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: s, attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: Self.mono]))
    }

    private func render(status: String, diff: String) {
        let out = NSMutableAttributedString()
        out.append(colored("● Status\n", .systemPurple, bold: true))
        out.append(colorizeStatus(status.isEmpty ? "(sauber)\n" : status))
        out.append(colored("\n● Änderungen (git diff)\n", .systemPurple, bold: true))
        if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(colored("(keine uncommitteten Änderungen)\n", .secondaryLabelColor))
        } else {
            out.append(colorizeDiff(diff))
        }
        textView.textStorage?.setAttributedString(out)
    }

    private func colorizeStatus(_ s: String) -> NSAttributedString {
        let r = NSMutableAttributedString()
        for line in s.components(separatedBy: "\n") {
            let c: NSColor = line.hasPrefix("??") ? .systemGray
                : (line.hasPrefix(" M") || line.hasPrefix("M") || line.hasPrefix("A")) ? .systemGreen
                : line.hasPrefix("##") ? .systemTeal : .labelColor
            r.append(colored(line + "\n", c))
        }
        return r
    }

    private func colorizeDiff(_ s: String) -> NSAttributedString {
        let r = NSMutableAttributedString()
        for line in s.components(separatedBy: "\n") {
            let c: NSColor
            if line.hasPrefix("+") && !line.hasPrefix("+++") { c = .systemGreen }
            else if line.hasPrefix("-") && !line.hasPrefix("---") { c = .systemRed }
            else if line.hasPrefix("@@") { c = .systemTeal }
            else if line.hasPrefix("diff ") || line.hasPrefix("+++") || line.hasPrefix("---") { c = .secondaryLabelColor }
            else { c = .labelColor }
            r.append(colored(line + "\n", c))
        }
        return r
    }

    private func colored(_ s: String, _ color: NSColor, bold: Bool = false) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .foregroundColor: color,
            .font: bold ? NSFont.boldSystemFont(ofSize: 11) : Self.mono,
        ])
    }

    private static let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
}
