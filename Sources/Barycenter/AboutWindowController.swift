import AppKit

/// „Über Barycenter"-Fenster (App-Icon, Version, Repo-Link, Lizenz).
final class AboutWindowController: NSWindowController {
    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Über Barycenter"
        self.init(window: w)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: "Barycenter")
        name.font = .systemFont(ofSize: 24, weight: .bold)
        name.alignment = .center

        let version = NSTextField(labelWithString: "Version \(Self.version)")
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        let tagline = NSTextField(labelWithString: "Mission Control für viele parallele AI-Coding-Agenten und Terminal-Sessions.")
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

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
}
