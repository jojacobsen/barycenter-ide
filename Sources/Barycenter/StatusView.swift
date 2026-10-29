import AppKit

/// Status-Seite einer Session: Profil, Ordner, Startzeit, Zustand und — bei Claude —
/// Modell, Kosten, Context (aus der statusLine-Datei). Fehlende Werte werden ausgelassen.
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

        row("Profil", session.profileName)
        row("Ordner", session.cwd)
        row("Gestartet", Self.df.string(from: session.startedAt))
        switch session.status {
        case .running:   row("Zustand", "läuft")
        case .attention: row("Zustand", "braucht dich")
        case .done:      row("Zustand", "beendet")
        case .idle:      row("Zustand", "wartet")
        }

        if session.remoteControl { row("Remote Control", "aktiv") }

        if session.launchCommand == "claude", let a = AgentsMonitor.shared.info(forPID: session.pid) {
            row("Live-Status", a.status + (a.waitingFor.map { " — \($0)" } ?? ""))
        }

        if session.launchCommand == "claude" {
            if let j = session.readStatusJSON() {
                if let m = (j["model"] as? [String: Any])?["display_name"] as? String { row("Modell", m) }
                if let cost = (j["cost"] as? [String: Any])?["total_cost_usd"] as? Double {
                    row("Kosten", String(format: "$%.4f", cost))
                }
                if let over = j["exceeds_200k_tokens"] as? Bool {
                    row("Context", over ? "⚠︎ über 200k Tokens" : "ok")
                }
            } else {
                row("Modell/Kosten", "— (sammelt Daten …)")
            }
        } else if let cmd = session.launchCommand {
            row("Befehl", cmd)
        }

        note("Zusammenfassung & Roadmap: folgt")
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
