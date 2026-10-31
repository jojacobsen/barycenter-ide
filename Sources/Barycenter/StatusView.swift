import AppKit

/// Status page of a session: profile, folder, start time, state and — for Claude —
/// model, cost, context (from the statusLine file). Missing values are omitted.
final class SessionStatusView: NSView {
    private let stack = NSStackView()

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .medium; return f
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh(for session: Session) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        row(L("Profil"), session.profileName)
        row(L("Ordner"), session.cwd)
        row(L("Gestartet"), Self.df.string(from: session.startedAt))
        switch session.status {
        case .running:   row(L("Zustand"), L("läuft"))
        case .attention: row(L("Zustand"), L("braucht dich"))
        case .done:      row(L("Zustand"), L("beendet"))
        case .idle:      row(L("Zustand"), L("wartet"))
        }

        if session.remoteControl { row(L("Remote Control"), L("aktiv")) }

        if session.launchCommand == "claude", let a = AgentsMonitor.shared.info(forPID: session.pid) {
            row(L("Live-Status"), a.status + (a.waitingFor.map { " — \($0)" } ?? ""))
        }

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

        note(L("Zusammenfassung & Roadmap: folgt"))
    }

    private func row(_ label: String, _ value: String) {
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 92).isActive = true
        l.setContentHuggingPriority(.required, for: .horizontal)

        let v = NSTextField(labelWithString: value)
        v.font = .systemFont(ofSize: 12)
        v.isSelectable = true
        v.lineBreakMode = .byTruncatingMiddle

        let r = NSStackView(views: [l, v])
        r.orientation = .horizontal
        r.spacing = 10
        r.alignment = .firstBaseline
        stack.addArrangedSubview(r)
    }

    private func note(_ text: String) {
        let n = NSTextField(labelWithString: text)
        n.font = .systemFont(ofSize: 11)
        n.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(n)
    }
}
