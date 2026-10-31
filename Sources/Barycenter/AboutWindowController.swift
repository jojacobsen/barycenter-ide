import AppKit

/// "About Barycenter" window (app icon, version, repo link, license).
final class AboutWindowController: NSWindowController {
    private let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
    private var clickTimes: [TimeInterval] = []   // Easter egg: quick clicks on the icon
    private var spinning = false

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("Über Barycenter")
        self.init(window: w)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.wantsLayer = true
        icon.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(iconClicked)))

        let name = NSTextField(labelWithString: "Barycenter")
        name.font = .systemFont(ofSize: 24, weight: .bold)
        name.alignment = .center

        let version = NSTextField(labelWithString: String(format: L("Version %@"), Self.version))
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        let tagline = NSTextField(labelWithString: L("Mission Control für viele parallele AI-Coding-Agenten und Terminal-Sessions."))
        tagline.font = .systemFont(ofSize: 12)
        tagline.alignment = .center
        tagline.lineBreakMode = .byWordWrapping
        tagline.maximumNumberOfLines = 3
        tagline.preferredMaxLayoutWidth = 320

        let link = NSButton(title: "github.com/jojacobsen/barycenter-ide", target: self, action: #selector(openRepo))
        link.isBordered = false
        link.contentTintColor = .linkColor
        link.font = .systemFont(ofSize: 12)

        let license = NSTextField(labelWithString: "MIT License · © 2026 Johannes Jacob")
        license.font = .systemFont(ofSize: 10)
        license.textColor = .tertiaryLabelColor
        license.alignment = .center

        let stack = NSStackView(views: [icon, name, version, tagline, link, license])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(14, after: tagline)
        stack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 96),
            icon.heightAnchor.constraint(equalToConstant: 96),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
        ])
    }

    @objc private func openRepo() {
        if let u = URL(string: "https://github.com/jojacobsen/barycenter-ide") { NSWorkspace.shared.open(u) }
    }

    // MARK: - Easter egg: quick clicks on the icon → it spins for a few seconds.

    @objc private func iconClicked() {
        let now = ProcessInfo.processInfo.systemUptime
        clickTimes.append(now)
        clickTimes = clickTimes.filter { now - $0 <= 1.2 }   // only count clicks from the last 1.2 s
        if clickTimes.count >= 3 {
            clickTimes.removeAll()
            spinIcon()
        }
    }

    private func spinIcon() {
        guard !spinning, let layer = icon.layer else { return }
        rotateAroundCenter(layer)
        spinning = true
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = 0
        anim.toValue = CGFloat.pi * 2 * 3          // three full turns
        anim.duration = 2.6                        // "a few seconds"
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.spinning = false }
        layer.add(anim, forKey: "spin")
        CATransaction.commit()
    }

    /// Moves the anchor point to the center (compensating the position) so the
    /// rotation happens around the icon's center instead of its corner.
    private func rotateAroundCenter(_ layer: CALayer) {
        let center = CGPoint(x: 0.5, y: 0.5)
        let old = layer.anchorPoint
        guard old != center else { return }
        var pos = layer.position
        pos.x += (center.x - old.x) * layer.bounds.width
        pos.y += (center.y - old.y) * layer.bounds.height
        layer.anchorPoint = center
        layer.position = pos
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
}
