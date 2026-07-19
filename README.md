<h1 align="center">
  <img src="logo.png" width="48" height="48" alt="CodeIsland Logo" valign="middle">&nbsp;
  CodeIsland
</h1>
<p align="center">
  <b>Real-time AI coding agent status panel for macOS Dynamic Island (Notch)</b><br>
  <a href="#installation">Install</a> •
  <a href="#features">Features</a> •
  <a href="#supported-tools">Supported Tools</a> •
  <a href="#build-from-source">Build</a><br>
  English | <a href="README.zh-CN.md">简体中文</a>
</p>

---

## What's New in This Fork

### Token Usage Dashboard (Settings → Usage)

A full **per-AI token usage breakdown** showing input, output, cache, and message counts across all four AI sources:

- **Claude Code** — scans `~/.claude/projects/**/*.jsonl`
- **OMP (Oh My Pi)** — scans `~/.omp/agent/sessions/**/*.jsonl`
- **Codex** — scans `~/.codex/sessions/**/*.jsonl` (uses `last_token_usage` delta, not cumulative)
- **Cursor** — extracts usage from Chrome session cookie via the Cursor CSV export API

#### Features

- **14-day summary** — total input/output/cache/messages across all sources
- **Per-AI breakdown** — each source with its mascot icon, brand color, and progress bar
- **Daily usage chart** — 14-day bar chart with per-day token counts
- **Last 12 hours sparkline** — hourly output tokens with hour-of-day labels
- **Billion (B) formatting** — large token counts display as 1.1B, 344M, etc.
- **Notch footer rotation** — cycles through each AI source every 60 seconds showing 5h/today totals
- **Footer click → Settings → Usage** — click the notch footer to open the full usage page

#### Cursor Setup (Settings → Usage → Cursor Usage Setup)

Cursor doesn't store token counts locally. CodeIsland extracts them via:

- **Manual cookie extraction** — paste `WorkosCursorSessionToken` from DevTools → Application → Cookies, fetch CSV via API
- **Manual CSV extraction** — download CSV from cursor.com export API, import the file
- **Cookie saved in macOS Keychain** — secure storage, no plaintext files, `kSecAttrAccessibleAfterFirstUnlock`
- **Auto-refresh** — toggle + interval picker (1h/3h/6h/12h/24h), uses saved cookie, no Keychain prompt
- **URL decoding** — handles `%3A%3A` → `::` in cookie values from DevTools
- **Privacy** — all data stays on your Mac, nothing shared, no telemetry

### Session Management

- **Right-click rename** on session cards — context menu with Rename / Reset Name / Star
- **Rename freeze** — session list freezes during rename to prevent TextField losing focus
- **Custom names** stored in UserDefaults
- **Star/favorite** sessions — gold highlight, stable sort by startTime
- **`$ Ready` status** — shows in green when session is idle
- **Cursor multi-window fix** — `cursor -r --reuse-window <cwd>` CLI for reliable window jumping

### Extension & Proxy

- **OMP bridge proxy** and **Codex proxy** — auto-installed via LaunchAgents (RunAtLoad + KeepAlive)
- **Active-only tracking** — sessions removed after 5 min of inactivity
- **Extension timeout fix** — narrowed dangerous patterns to only `rm -rf /`, `rm -rf ~`, `rm -rf $HOME` (safe `rm -rf .build` passes through)
- **20s bridge timeout** with 5s hard outer timeout on socket sends
- **CODEISLAND_DEBUG=1** environment variable for extension logging

### Architecture

- **Protocol-based usage scanners** — `UsageScanner` protocol with one struct per source (`ClaudeCodeScanner`, `OMPScanner`, `CodexScanner`, `CursorScanner`), coordinated by `UsageScannerCoordinator`
- **Codex cumulative token fix** — uses `last_token_usage` (delta) not `total_token_usage` (cumulative), cache invalidated on each scan
- **Cursor cookie extraction** — Chrome Safe Storage Keychain + PBKDF2-HMAC-SHA1 + AES-128-CBC decrypt (same technique as `pycookiecheat`/spinnaker-mcp), reimplemented in Swift with `CommonCrypto`


<p align="center">
  <img src="docs/images/notch-panel.png" width="700" alt="CodeIsland Panel Preview">
</p>

## What is CodeIsland?

CodeIsland lives in your MacBook's notch area and shows you what your AI coding agents are doing — in real time. No more switching windows to check if Claude is waiting for approval or if Codex finished its task.

It connects to **13 AI coding tools** via Unix socket IPC, displaying session status, tool calls, permission requests, and more — all in a compact, pixel-art styled panel.

## Features

- **Notch-native UI** — Expands from the MacBook notch, collapses when idle
- **13 AI tools supported** — Claude Code, Codex, Gemini CLI, Cursor, Copilot, Trae/Traecli, Qoder, Factory, CodeBuddy, OpenCode, Kimi Code CLI, Cline, Pi / Oh My Pi
- **Live status tracking** — See active sessions, tool calls, and AI responses in real time
- **Permission management** — Approve/deny tool permissions directly from the panel
- **Question answering** — Respond to agent questions without leaving your current app
- **Pixel-art mascots** — Each AI tool has its own animated character
- **One-click jump** — Click a session to jump to its terminal tab or IDE window
- **Smart suppress** — Tab-level terminal detection: only suppresses notifications when you're looking at the specific session tab, not just the terminal app
- **Sound effects** — Optional 8-bit sound notifications for session events
- **Auto hook install** — Automatically configures hooks for all detected CLI tools, with auto-repair and version tracking
- **iPhone & Apple Watch Buddy** — Mirror session status to Dynamic Island, Lock Screen, StandBy, and Apple Watch
- **Bilingual UI** — English and Chinese, auto-detects system language
- **Multi-display** — Works with external monitors, auto-detects notch displays

## Supported Tools

| | Tool | Events | Jump | Status |
|:---:|------|--------|------|--------|
| <img src="docs/images/mascots/claude.gif" width="28"> | <img src="Sources/CodeIsland/Resources/cli-icons/claude.png" width="16"> Claude Code | 13 | Terminal tab | Full |
| <img src="docs/images/mascots/codex.gif" width="28"> | <img src="Sources/CodeIsland/Resources/cli-icons/codex.png" width="16"> Codex | 3 | Terminal | Basic |
| <img src="docs/images/mascots/gemini.gif" width="28"> | <img src="Sources/CodeIsland/Resources/cli-icons/gemini.png" width="16"> Gemini CLI | 6 | Terminal | Full |
| <img src="docs/images/mascots/cursor.gif" width="28"> | <img src="Sources/CodeIsland/Resources/cli-icons/cursor.png" width="16"> Cursor | 10 | IDE | Full |
| <img src="docs/images/mascots/trae.gif" width="28"> | <img src="Sources/CodeIsland/Resources/cli-icons/traecli.png" width="16"> TraeCli | 10 | Terminal | Full |
| <img src="docs/images/mascots/qoder.gif" width="28"> | <img src="Sources/CodeIsland/Resources/cli-icons/qoder.png" width="16"> Qoder | 10 | IDE | Full |
| | <img src="Sources/CodeIsland/Resources/cli-icons/copilot.png" width="16"> Copilot | 6 | Terminal | Full |
| <img src="docs/images/mascots/factory.gif" width="28"> | <img src="Sources/CodeIsland/Resources/cli-icons/factory.png" width="16"> Factory | 10 | IDE | Full |
| <img src="docs/images/mascots/codebuddy.gif" width="28"> | <img src="Sources/CodeIsland/Resources/cli-icons/codebuddy.png" width="16"> CodeBuddy | 10 | APP/Terminal | Full |
| | <img src="Sources/CodeIsland/Resources/cli-icons/kimi.png" width="16"> Kimi Code CLI | 10 | Terminal | Full |
| <img src="docs/images/mascots/opencode.gif" width="28"> | <img src="Sources/CodeIsland/Resources/cli-icons/opencode.png" width="16"> OpenCode | All | APP/Terminal | Full |
| <img src="docs/images/mascots/cline.gif" width="28"> | <img src="Sources/CodeIsland/Resources/cli-icons/cline.png" width="16"> Cline | 5 | VSCode | Full |
| | <img src="Sources/CodeIsland/Resources/cli-icons/pi.png" width="16"> Pi / Oh My Pi | 8 | Terminal | Full |

## Installation

### Homebrew (Recommended)

```bash
brew tap wxtsky/tap
brew install --cask codeisland
```

### Manual Download

1. Go to [Releases](https://github.com/wxtsky/CodeIsland/releases)
2. Download `CodeIsland.dmg`
3. Open the DMG and drag `CodeIsland.app` to your Applications folder
4. Launch CodeIsland — it will automatically install hooks for all detected AI tools

> **Note:** On first launch, macOS may show a security warning. Go to **System Settings → Privacy & Security** and click **Open Anyway**.

### iPhone & Apple Watch Buddy

Code Island Buddy is available on the App Store:

[Download Code Island Buddy](https://apps.apple.com/us/app/code-island-buddy/id6773881129)

The iPhone app mirrors your Mac sessions to Dynamic Island, Lock Screen, StandBy, and Apple Watch. The Mac app publishes lightweight session snapshots over your local network while the iPhone app is open, and sends compact Bluetooth summaries for background refreshes such as Live Activities and Watch updates.

Code Island Buddy is completely free and open source. It does not require an account or an external server; the companion source code lives in this repository under `ios/CodeIslandCompanion` and `apple-companion`.

### Build from Source

Requires **macOS 14+** and **Swift 5.9+**.

```bash
git clone https://github.com/wxtsky/CodeIsland.git
cd CodeIsland

# Development (debug build + launch; Buddy Bluetooth needs the .app below)
swift build && ./.build/debug/CodeIsland

# Release (universal binary: Apple Silicon + Intel)
./build.sh
open .build/release/CodeIsland.app
```

## How It Works

```
AI Tool (Claude/Codex/Gemini/Cursor/...)
  → Hook event triggered
    → codeisland-bridge (native Swift binary, ~86KB)
      → Unix socket → /tmp/codeisland-<uid>.sock
        → CodeIsland app receives event
          → Updates UI in real time
          → Optional local Buddy sync to iPhone / Apple Watch
```

CodeIsland installs lightweight hooks into each AI tool's config. When the tool triggers an event (session start, tool call, permission request, etc.), the hook sends a JSON message through a Unix socket. CodeIsland listens on this socket and updates the notch panel instantly.

For **OpenCode**, a JS plugin connects directly to the socket — no bridge binary needed.

## Settings

CodeIsland provides a 7-tab settings panel:

- **General** — Language, launch at login, display selection
- **Behavior** — Auto-hide, smart suppress, session cleanup
- **Appearance** — Panel height, font size, AI reply lines
- **Mascots** — Preview all pixel-art characters and their animations
- **Sound** — 8-bit sound effects for session events
- **Hooks** — View CLI installation status, reinstall or uninstall hooks
- **About** — Version info and links

## Keyboard Shortcuts

| Shortcut | Action | Default |
|----------|--------|---------|
| ⌘⇧I | Toggle the island panel open/closed | On |
| ⌘⇧A | Approve the current permission request | Off |
| ⌘⇧D | Deny the current permission request | Off |

All shortcuts are configurable — and more actions (always-allow, skip question, jump to terminal) can be bound — under **Settings → Shortcuts**. When an approve/deny shortcut is enabled, its binding shows as a badge right on the approval card.

## Requirements

- macOS 14.0 (Sonoma) or later
- Works best on MacBooks with a notch, but also works on external displays

## Acknowledgments

This project was inspired by [claude-island](https://github.com/farouqaldori/claude-island) by [@farouqaldori](https://github.com/farouqaldori). Thanks for the original idea of bringing AI agent status into the macOS notch.

## Star History

<a href="https://www.star-history.com/?repos=wxtsky%2FCodeIsland&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=wxtsky/CodeIsland&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=wxtsky/CodeIsland&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=wxtsky/CodeIsland&type=date&legend=top-left" />
 </picture>
</a>

## License

MIT License — see [LICENSE](LICENSE) for details.
