import AppKit
import WebKit

/// Rendered Markdown preview (WKWebView + marked.js + GitHub-Dark CSS, bundled offline).
final class MarkdownPreviewView: NSView, WKNavigationDelegate, WKScriptMessageHandler {
    private let webView: WKWebView
    private let markedJS: String
    private let css: String

    /// When set, task-list checkboxes become clickable and this is called with the
    /// 0-based task index (document order) and the new checked state. nil = read-only.
    var onToggleTask: ((Int, Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        markedJS = Self.resource("marked.min", "js")
        css = Self.resource("github-markdown-dark.min", "css")

        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        cfg.userContentController = ucc
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init(frame: frameRect)
        // Weak proxy so the content controller doesn't retain this view.
        ucc.add(WeakScriptMessageProxy(self), name: "task")

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
        let interactive = (onToggleTask != nil)
        // When interactive: enable the GFM task checkboxes and report clicks to native.
        let taskJS = interactive ? """
        var boxes = document.querySelectorAll('#c input[type="checkbox"]');
        boxes.forEach(function(cb, i){
          cb.disabled = false;
          cb.style.cursor = 'pointer';
          cb.addEventListener('change', function(){
            window.webkit.messageHandlers.task.postMessage({index: i, checked: cb.checked});
          });
        });
        """ : ""
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)
        html,body{background:#0d1117;margin:0;}
        .markdown-body{box-sizing:border-box;max-width:none;padding:16px;font-size:13px;}
        .markdown-body input[type="checkbox"]{margin-right:6px;}
        </style></head>
        <body><article class="markdown-body" id="c"></article>
        <script>\(markedJS)</script>
        <script>
        try {
          marked.setOptions({ gfm: true, breaks: true });
          document.getElementById('c').innerHTML = marked.parse(\(jsonArr)[0]);
          \(taskJS)
        }
        catch(e){ document.getElementById('c').textContent = String(e); }
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // Native side of a checkbox click.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "task",
              let body = message.body as? [String: Any],
              let index = body["index"] as? Int,
              let checked = body["checked"] as? Bool else { return }
        onToggleTask?(index, checked)
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

/// Breaks the WKUserContentController -> handler -> view retain cycle.
private final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
