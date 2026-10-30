import AppKit

/// Zeilennummern-Leiste links im Editor. Als Vertical-Ruler eines NSScrollView.
/// Zeichnet die Nummer je Textzeile, folgt Scrollen und Inhaltsänderungen.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private var numberColor: NSColor = .tertiaryLabelColor
    var backgroundColor: NSColor = NSColor(white: 0, alpha: 0.18)

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40

        // Bei Scrollen und Inhaltsänderungen neu zeichnen.
        if let clip = textView.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(redraw),
                                                   name: NSView.boundsDidChangeNotification, object: clip)
        }
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(redraw),
                                               name: NSView.frameDidChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(redraw),
                                               name: NSText.didChangeNotification, object: textView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    /// Farbe an das Editor-Theme anpassen (helles/dunkles Theme).
    func applyTheme(dark: Bool) {
        numberColor = dark ? .tertiaryLabelColor : .secondaryLabelColor
        backgroundColor = NSColor(white: dark ? 0 : 1, alpha: 0.18)
        redraw()
    }

    @objc func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              let scrollView = textView.enclosingScrollView else { return }

        backgroundColor.setFill()
        rect.fill()

        let text = textView.string as NSString
        let visible = scrollView.contentView.bounds
        let inset = textView.textContainerInset.height
        let attrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: numberColor]

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Zeilennummer am Anfang des sichtbaren Bereichs (= Zeilenumbrüche davor + 1).
        var lineNo = text.substring(to: charRange.location).components(separatedBy: "\n").count

        text.enumerateSubstrings(in: charRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let gRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var eff = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: gRange.location,
                                                          effectiveRange: &eff, withoutAdditionalLayout: true)
            let y = lineRect.minY + inset - visible.minY
            let s = "\(lineNo)" as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: self.ruleThickness - size.width - 5,
                               y: y + (lineRect.height - size.height) / 2), withAttributes: attrs)
            lineNo += 1
        }
    }
}
