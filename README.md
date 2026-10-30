# Barycenter

**Native macOS mission control for many parallel AI coding agents and terminal sessions.**

Barycenter is the control layer *above* your coding agents: run a fleet of
**Claude Code**, Codex, Gemini CLI, Aider (or any CLI) sessions side by side,
see at a glance what each is doing, and get pulled in the moment one needs you —
with an optional AI **Handler** that spawns and steers sessions for you.

> Not a classic editor-first IDE — it's orchestration-first. Agents do the work;
> the built-in editor/diff/files are there for you to peek in and intervene.

<!-- ![screenshot](docs/screenshot.png) -->

## Features

- **Grid & Focus** — all sessions at once, or one big; click a tile and type.
- **Attention routing** — a session that needs you turns 🔴 with a sound, Dock
  bounce and a macOS banner. For Claude Code this is driven by real **hooks**;
  others use a terminal-bell heuristic.
- **Live status** — busy / waiting (+ reason) / idle, read from
  `claude agents --json` and matched to sessions by PID.
- **Spawn with profiles** — Claude Code · Codex · Gemini CLI · Aider · Shell ·
  custom command, in any folder, optionally in its own **git worktree**.
- **Per-session pages** (tab switcher per tile): **Terminal · Status**
  (model / cost / context) **· Notes · Diff** (`git diff`) **· Files** —
  a mini file browser + editor with **syntax highlighting** and a rendered
  **Markdown preview**, plus recursive filename search.
- **Handler** — an AI manager (itself a Claude session) that controls Barycenter
  via a tiny local command (`baryctl`): list / spawn / send / focus / close.
- **Activity rail** — toggle **Sessions**, **Handler** and **Verlauf** (cross-repo
  git history); two tools split the panel 50/50.
- **Remote Control** toggle & badge for Claude sessions, themes, notes, and a
  dark, modern UI throughout.

## Requirements

- macOS 13+
- Swift 6 / Xcode 16+ (`swift` toolchain)
- The [`claude`](https://docs.claude.com/en/docs/claude-code) CLI for Claude Code
  sessions (optional for plain shells / other agents)

## Build & Run

```bash
# Run directly
swift run

# …or build a signed .app bundle and open it
./build_app.sh
open Barycenter.app
```

`build_app.sh` assembles `Barycenter.app`, copies the SwiftPM resource bundles
(Highlightr, SwiftTerm, marked/CSS) into it, and ad-hoc signs it.

## How it works (short)

- Each session is a real process in its own PTY, embedded via **SwiftTerm**.
- Claude sessions are launched with per-session **hooks + statusLine** injected
  through `--settings` (no changes to your global config), writing to a local
  file that Barycenter watches → that's the attention/status channel.
- The **Handler** drives the app through a local Unix-domain socket; `baryctl`
  (auto-generated at runtime) is the thin client it calls from its shell tool.

## Releases (signed DMG)

To produce a distributable, **Developer ID–signed and Apple-notarized** `Barycenter.dmg`:

```bash
./release.sh
```

One-time prerequisites: a *Developer ID Application* certificate in your login
keychain and a `notarytool` credential profile:

```bash
xcrun notarytool store-credentials "barycenter-notary" \
  --apple-id "<apple-id>" --team-id "<TEAM_ID>"
```

`release.sh` re-signs the app with Hardened Runtime (+ a JIT entitlement for
JavaScriptCore/WebKit), builds the DMG via `hdiutil`, notarizes and staples it.

> ⚠️ Early-stage / work in progress — expect rough edges.

## License

[MIT](LICENSE). Third-party components and their licenses are listed in
[THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md). Not affiliated with Anthropic.
