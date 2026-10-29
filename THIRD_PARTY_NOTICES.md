# Third-Party Notices

Barycenter bundles and/or depends on the following open-source components.
All are used under their respective licenses; copies of the license texts are
available at the linked repositories.

| Component | Purpose | License | Source |
|-----------|---------|---------|--------|
| **SwiftTerm** | Terminal emulator / PTY hosting | MIT | https://github.com/migueldeicaza/SwiftTerm |
| **Highlightr** | Syntax highlighting (wraps highlight.js) | MIT | https://github.com/raspu/Highlightr |
| **marked** | Markdown → HTML for the preview | MIT | https://github.com/markedjs/marked |
| **github-markdown-css** | Markdown preview styling (dark) | MIT | https://github.com/sindresorhus/github-markdown-css |

`marked.min.js` and `github-markdown-dark.min.css` are vendored into
`Sources/Barycenter/Resources/` and rendered offline in a `WKWebView`.

This project also integrates with the **Claude Code** CLI (`claude`) and reads
its public `claude agents --json` output and hook/`statusLine` mechanisms; it is
not affiliated with or endorsed by Anthropic.
