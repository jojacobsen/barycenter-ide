import AppKit

/// Status page of a session: profile, folder, start time, state and — for Claude —
/// model, cost, context (from the statusLine file). Below that, an AI-generated
/// project status (summary / roadmap / open points), produced on demand.
final class SessionStatusView: NSView {
    private let stack = NSStackView()

    // Project-status section
    private let genButton = NSButton(title: "", target: nil, action: nil)
    private let genInfo = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let preview = MarkdownPreviewView(frame: .zero)
    private let placeholder = NSTextField(wrappingLabelWithString: "")

    private weak var session: Session?
    private var isGenerating = false
    private var renderedText: String?   // avoid re-rendering the web view on every refresh

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Section header: title + spinner + timestamp + generate button.
        let title = NSTextField(labelWithString: L("PROJEKT-STATUS"))
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        genInfo.font = .systemFont(ofSize: 10)
        genInfo.textColor = .tertiaryLabelColor
        genInfo.lineBreakMode = .byTruncatingTail

        genButton.bezelStyle = .rounded
        genButton.controlSize = .small
        genButton.target = self
        genButton.action = #selector(generate)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let header = NSStackView(views: [title, spacer, spinner, genInfo, genButton])
        header.orientation = .horizontal
        header.spacing = 8
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        placeholder.font = .systemFont(ofSize: 12)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.stringValue = L("Noch kein Projekt-Status. „Generieren“ lässt einen Claude-Lauf im Projektordner eine Zusammenfassung, Roadmap und offene Punkte erstellen.")

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.isHidden = true
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.layer?.masksToBounds = true
        addSubview(preview)
        addSubview(placeholder)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),

            header.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            preview.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            preview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            placeholder.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            placeholder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh(for session: Session) {
        self.session = session
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        row(L("Profil"), session.profileName)
        row(L("Ordner"), session.cwd)
        row(L("Gestartet"), Self.df.string(from: session.startedAt))

        // One state, color-coded — matches the tile border and the sidebar pill.
        let st = session.displayState
        row(L("Zustand"), st.text, color: st.color)

        if session.remoteControl { row(L("Remote Control"), L("aktiv")) }

        if session.launchCommand == "claude" {
            if let j = session.readStatusJSON() {
                if let m = (j["model"] as? [String: Any])?["display_name"] as? String { row(L("Modell"), m) }
                if let cost = (j["cost"] as? [String: Any])?["total_cost_usd"] as? Double {
                    row(L("Kosten"), String(format: "$%.4f", cost))
                }
                if let over = j["exceeds_200k_tokens"] as? Bool {
                    row(L("Context"), over ? L("⚠︎ über 200k Tokens") : L("ok"))
                }
            } else {
                row(L("Modell/Kosten"), L("— (sammelt Daten …)"))
            }
        } else if let cmd = session.launchCommand {
            row(L("Befehl"), cmd)
        }

        refreshProjectStatus()
    }

    /// Load the cached overview (only re-rendering the web view when it changed) and
    /// reflect the current generation state in the header.
    private func refreshProjectStatus() {
        if isGenerating {
            spinner.startAnimation(nil)
            genButton.isEnabled = false
            genButton.title = L("Generieren")
            genInfo.stringValue = L("generiert …")
            return
        }
        spinner.stopAnimation(nil)
        genButton.isEnabled = true

        guard let cwd = session?.cwd, let cached = ProjectStatus.cached(for: cwd) else {
            genButton.title = L("Generieren")
            genInfo.stringValue = ""
            preview.isHidden = true
            placeholder.isHidden = false
            renderedText = nil
            return
        }
        genButton.title = L("Neu generieren")
        genInfo.stringValue = String(format: L("Aktualisiert: %@"), Self.df.string(from: cached.date))
        placeholder.isHidden = true
        preview.isHidden = false
        if cached.text != renderedText {
            renderedText = cached.text
            preview.render(cached.text)
        }
    }

    @objc private func generate() {
        guard let cwd = session?.cwd, !isGenerating else { return }
        isGenerating = true
        refreshProjectStatus()
        ProjectStatus.generate(for: cwd) { [weak self] result in
            guard let self else { return }
            self.isGenerating = false
            switch result {
            case .success:
                self.refreshProjectStatus()
            case .failure(let error):
                self.refreshProjectStatus()
                self.genInfo.stringValue = error.localizedDescription
            }
        }
    }

    private func row(_ label: String, _ value: String, color: NSColor? = nil) {
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 92).isActive = true
        l.setContentHuggingPriority(.required, for: .horizontal)

        let v = NSTextField(labelWithString: value)
        v.font = .systemFont(ofSize: 12, weight: color == nil ? .regular : .semibold)
        if let color { v.textColor = color }
        v.isSelectable = true
        v.lineBreakMode = .byTruncatingMiddle

        let r = NSStackView(views: [l, v])
        r.orientation = .horizontal
        r.spacing = 10
        r.alignment = .firstBaseline
        stack.addArrangedSubview(r)
    }
}
