import AppKit

/// Tools in the left activity rail (extendable).
enum Tool: CaseIterable {
    case sessions, manager, history

    var title: String {
        switch self {
        case .sessions: return L("Sessions")
        case .manager:  return L("Verwalter")
        case .history:  return L("Verlauf")
        }
    }
    var symbol: String {
        switch self {
        case .sessions: return "rectangle.grid.2x2"
        case .manager:  return "cpu"
        case .history:  return "clock.arrow.circlepath"
        }
    }
}

/// A rail button: icon above label, blue rounded highlight when active.
final class RailButton: NSView {
    let tool: Tool
    var onClick: ((Tool) -> Void)?
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    var isSelected = false { didSet { update() } }

    init(tool: Tool) {
        self.tool = tool
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false

        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        iconView.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.title)?
            .withSymbolConfiguration(cfg)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.stringValue = tool.title
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .centerX
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 6, bottom: 9, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 68),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        update()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?(tool) }

    private func update() {
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        let tint: NSColor = isSelected ? .white : .secondaryLabelColor
        iconView.contentTintColor = tint
        label.textColor = tint
    }
}

/// Narrow strip on the far left holding the tool buttons.
final class ActivityRailViewController: NSViewController {
    var onChange: (([Tool]) -> Void)?
    private var active: Set<Tool> = [.sessions]
    private var buttons: [RailButton] = []
    private let stack = NSStackView()

    /// Tools currently shown — the manager is hidden when disabled in settings.
    private func visibleTools() -> [Tool] {
        Tool.allCases.filter { $0 != .manager || AppSettings.shared.showManager }
    }

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true

        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .centerX
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 0, bottom: 14, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: v.topAnchor),
            stack.centerXAnchor.constraint(equalTo: v.centerXAnchor),
        ])
        self.view = v
        rebuildButtons()

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// (Re)create the rail buttons for the currently visible tools.
    private func rebuildButtons() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        for tool in visibleTools() {
            let b = RailButton(tool: tool)
            b.onClick = { [weak self] in self?.tap($0) }
            buttons.append(b)
            stack.addArrangedSubview(b)
        }
        highlight()
    }

    @objc private func settingsChanged() {
        // If the manager was just hidden while active, drop it and update the panel.
        let visible = Set(visibleTools())
        let removed = active.subtracting(visible)
        if !removed.isEmpty {
            active.subtract(removed)
            onChange?(ordered())
        }
        rebuildButtons()
    }

    private func tap(_ tool: Tool) {
        if active.contains(tool) { active.remove(tool) } else { active.insert(tool) }
        highlight()
        onChange?(ordered())
    }
    private func ordered() -> [Tool] { visibleTools().filter { active.contains($0) } }
    private func highlight() { buttons.forEach { $0.isSelected = active.contains($0.tool) } }
}
