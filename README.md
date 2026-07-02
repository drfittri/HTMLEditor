# HTML Agent Editor

macOS native app untuk buka HTML files, render dalam WKWebView, select page elements, and send precise feedback to local agent CLIs.

## Features

- **WKWebView** render HTML — native WebKit, DevTools enabled
- **Element picking** — click any visible element in the preview and send its DOM context to the agent
- **Right-side feedback panel** — chat-style composer for edit requests
- **Agent selector** — Claude · Codex · OpenCode · Antigravity via a compact dropdown
- **Model selector** — choose the model/alias passed to the selected agent CLI
- **Parallel windows** — open separate HTML files in separate editor windows
- **Token-efficient sessions** — each agent reuses its own session on follow-up edits (Claude `--session-id`/`--resume`; Codex `exec resume`; OpenCode/Antigravity `-c`) so the file and prior turns aren't re-sent as prompt text. History is injected only to bootstrap the first turn or an agent switch. Chat runs read-only where supported (Codex `--sandbox read-only`)
  - *Caveat:* Codex/OpenCode/Antigravity resume the **most-recent** session. Claude is isolated per-window; the others can cross sessions if you run two windows on the **same folder** with the **same agent** at once. One window per folder per agent keeps them fully separate.
- **Dark/Light mode** toggle — sun/moon button in toolbar
- **File association** — right-click .html → Open With → HTML Agent Editor
- **Drag & drop** — drop .html onto app window
- **Minimal UI** — large HTML preview with small icon controls on the chrome

## Build

### macOS

```bash
cd ~/Desktop/HTMLEditor
./build.sh
```

Output: `~/Desktop/HTML Agent Editor.app`

### Windows

The Windows-compatible version lives in `windows/` and uses Electron because the Swift/AppKit app depends on macOS-only frameworks.

```powershell
cd .\windows
npm install
npm start
```

To build a standalone portable app on Windows:

```powershell
.\build-windows.ps1
```

Outputs:
- `windows\dist\HTML-Agent-Editor-Windows-x64-Portable-1.0.2.exe`
- `windows\dist\HTML-Agent-Editor-Windows-x64-Portable-1.0.2.zip`

If Windows says it cannot access the downloaded `.exe`, download the `.zip` release instead, extract it, and run `HTML Agent Editor.exe` from the extracted folder.

## Usage

### Open file
1. Right-click `.html` → **Open With → HTML Agent Editor**
2. Drag `.html` onto app window
3. Click the folder button in the toolbar for file open dialog
4. Use **File → New Window** (`⌘N`) for another independent editor window

### Agent workflow
1. Open an HTML file.
2. Pick Claude, Codex, OpenCode, or Antigravity from the feedback panel.
3. Choose the model for that agent, or leave it on Default.
4. Click an element in the preview.
5. Type the change you want and send it.

### Other toolbar controls
| Icon | Action |
|------|--------|
| ⟳ | Reload HTML |
| 🌐 Safari | Open in browser |
| 📁 Folder | Open file dialog |
| ☀/🌙 | Toggle dark/light mode |

### Layout
- Left: WKWebView HTML preview
- Right: feedback panel with agent selector, selected element context, chat transcript, and composer
- Drag divider to resize the preview and feedback panel

### Make default
Right-click .html → Get Info → Open with → HTML Agent Editor → Change All

## Prerequisites

Agent selector needs respective CLIs in PATH:
- `claude` — Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)
- `codex` — Codex CLI
- `opencode` — OpenCode CLI
- `agy` — Google Antigravity CLI (`curl -fsSL https://antigravity.google/cli/install.sh | bash`)

If Claude or Codex is installed but not authorized yet, the app shows an authorization sheet and can open Terminal with the right setup command.

## Customise

Source at `~/Desktop/HTMLEditor/Sources/`:
- Add agents in `ViewController.agentMeta`
- Rebuild with `./build.sh`

## Build Notes

- Minimum macOS 14 (Sonoma)
- Built with `swiftc` + Cocoa + WebKit (no SPM/Xcode needed)
- arm64 native binary
