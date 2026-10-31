import AppKit
import WebKit

/// Rendered Markdown preview (WKWebView + marked.js + GitHub-Dark CSS, bundled offline).
final class MarkdownPreviewView: NSView, WKNavigationDelegate {
    private let webView = WKWebView()
    private let markedJS: String
    private let css: String

    override init(frame frameRect: NSRect) {
        markedJS = Self.resource("marked.min", "js")
        css = Self.resource("github-markdown-dark.min", "css")
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: "#0d1117").cgColor
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")   // transparent -> no white flash
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func render(_ markdown: String) {
        // Safely embed the Markdown as a JS string (via the JSON-array trick).
        let jsonArr = (try? String(data: JSONSerialization.data(withJSONObject: [markdown]), encoding: .utf8)) ?? "[\"\"]"
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)
        html,body{background:#0d1117;margin:0;}
        .markdown-body{box-sizing:border-box;max-width:none;padding:16px;font-size:13px;}
        </style></head>
        <body><article class="markdown-body" id="c"></article>
        <script>\(markedJS)</script>
        <script>
        try { document.getElementById('c').innerHTML = marked.parse(\(jsonArr)[0]); }
        catch(e){ document.getElementById('c').textContent = String(e); }
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // Open links externally in the browser instead of navigating within the preview.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    private static func resource(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }
}
