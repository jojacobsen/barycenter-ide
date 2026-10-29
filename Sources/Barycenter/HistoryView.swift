import AppKit

/// Rail-Tool „Verlauf": sessionübergreifende Git-Commit-History.
/// Sammelt die Repos aller Sessions und zeigt je Repo die letzten Commits.
final class HistoryView: NSView {
    private let textView = NSTextView()
    private let scroll = NSScrollView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let title = NSTextField(labelWithString: "VERLAUF")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .systemTeal
        title.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "↻", target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title); addSubview(refreshButton); addSubview(scroll)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            refreshButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func refresh() {
        setPlain("Lade …")
        let cwds = Array(Set(SessionManager.shared.sessions.map { $0.cwd }))
        DispatchQueue.global(qos: .userInitiated).async {
            var repos: [String: String] = [:]   // topLevel -> log
            for cwd in cwds {
                guard let top = Git.topLevel(cwd), repos[top] == nil else { continue }
                repos[top] = Git.run(["log", "--pretty=format:%h  %ad  %s", "--date=short", "-n", "12"], cwd: top)
            }
            DispatchQueue.main.async { self.render(repos) }
        }
    }

    private func setPlain(_ s: String) {
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: s, attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: Self.mono]))
    }

    private func render(_ repos: [String: String]) {
        guard !repos.isEmpty else {
            setPlain("Keine Git-Repos unter den Sessions."); return
        }
        let out = NSMutableAttributedString()
        for (top, log) in repos.sorted(by: { $0.key < $1.key }) {
            let name = (top as NSString).lastPathComponent
            out.append(NSAttributedString(string: "▸ \(name)\n", attributes: [
                .foregroundColor: NSColor.systemTeal, .font: NSFont.boldSystemFont(ofSize: 11)]))
            out.append(NSAttributedString(string: (log.isEmpty ? "(keine Commits)" : log) + "\n\n", attributes: [
                .foregroundColor: NSColor.labelColor, .font: Self.mono]))
        }
        textView.textStorage?.setAttributedString(out)
    }

    private static let mono = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
}
