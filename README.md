# HTML Agent Editor

macOS native app untuk buka HTML files, render dalam WKWebView, select page elements, and send precise feedback to local agent CLIs.

## Features

- **WKWebView** render HTML — native WebKit, DevTools enabled
- **Element picking** — click any visible element in the preview and send its DOM context to the agent
- **Direct editing without the agent** — delete, move, resize, retype, and paste images straight into the DOM. Every one of these writes the file through the same path (atomic save + rewind/undo) and costs **zero agent tokens**
- **Right-side feedback panel** — chat-style composer for edit requests
- **Agent selector** — Claude · Codex · OpenCode · Antigravity via a compact dropdown
- **Model selector** — choose the model/alias passed to the selected agent CLI
- **Parallel windows** — open separate HTML files in separate editor windows
- **Token-efficient sessions** — each agent reuses its own session on follow-up edits (Claude `--session-id`/`--resume`; Codex `exec resume`; OpenCode/Antigravity `-c`) so the file and prior turns aren't re-sent as prompt text. History is injected only to bootstrap the first turn or an agent switch. Chat runs read-only where supported (Codex `--sandbox read-only`)
  - *Caveat:* Codex/OpenCode/Antigravity resume the **most-recent** session. Claude is isolated per-window; the others can cross sessions if you run two windows on the **same folder** with the **same agent** at once. One window per folder per agent keeps them fully separate.
- **Send-once preamble** — the standing instructions (be terse, smallest correct change, file path, output budget) go out on the **first turn of a session only**. Every turn after that sends just `Edit mode.`, the element anchors, and your request; the agent already holds the rest in its resumed session. A new session — the New Session button, a new file, an agent switch — re-sends the preamble once.
- **Minimal element context** — a selected element is sent as one line: its opening tag plus a six-word text anchor, both chosen to be grep-able (`1. <button class="btn primary"> | "Get started with the free plan"`). No CSS selector, no HTML snippet. That is roughly 40 tokens per element instead of several hundred; the agent greps the file when it needs more.
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

### Direct editing (no agent, no tokens)

These act on the DOM in the preview and save the file immediately. The rewind button undoes any of them, exactly like an agent edit.

**Selecting**

Click an element to select it. Shift-click to add or remove more. A click lands on the deepest element under the cursor — a table cell, not the table — so there are three ways to widen from there:

- **Crumb bar.** A breadcrumb of the ancestor chain (`div.page › section.content › table#t1 › tbody › tr › td`) floats above the selected element, in the preview itself. Click any crumb to select that ancestor; hovering one ghosts it first.
- **Arrow keys.** `↑` parent, `↓` first child, `←`/`→` siblings.
- **Text selection.** A word is not an element, so the picker can never target one. Drag-highlight it instead and the exact string is sent to the agent as a grep anchor, along with the tag it sits in.

**Moving.** Select an element, then press and drag it. A green line shows where it will land (before or after the element you're hovering). Widen the selection first and the drag carries the *container* — select a cell, click the `table` crumb, drag, and the whole table moves. `Esc` cancels a drag in flight. The element stays selected after the drop, so it is still the agent's context.

Dragging an element that is **not** selected does nothing, which is what keeps ordinary text drag-selection working. To select text inside an element that *is* selected, double-click into it first.

**Deleting.** Select, then press `⌫`/`Delete` or hit the trash button.

**Resizing images.** Select an `<img>` and eight handles appear. Corners keep the aspect ratio; side edges resize one axis (a horizontal drag leaves `height:auto`). `Esc` restores the pre-drag size.

**Editing text.** Double-click any passage to edit it in place — type, delete, select. `Enter` inserts a line break inside the block rather than splitting it. Double-clicking a bolded word edits the whole paragraph, not just the `<strong>`. Click away or press `Esc` to finish and save.

**Inserting images.** Copy an image, then either press `⌘V` with an element selected or hit the photo button. The bitmap is downscaled to 1600px, encoded to **AVIF** via `avifenc`, base64'd, and inserted as an `<img>` **immediately after the selected element** — so the picker doubles as the placement marker. With nothing selected it appends to `<body>`. Requires `avifenc` (`brew install libavif`).

`⌘V` routing, in short: chat box focused → the image attaches as agent context (as before); preview focused with an element selected → the image is inserted into the page; preview focused with nothing selected → nothing happens.

### Mode dial (Shift+Tab)

**Hold `⇧⇥`** to raise a radial selector at the cursor, point at a wedge, and **release** to commit it.

| Wedge | Effect |
|-------|--------|
| **Select** (top) | Element picking armed — the normal editing mode |
| **Normal** (bottom) | Reading mode: picking off, selection cleared, chat sidebar collapsed |

Releasing over the centre hub commits nothing; `Esc` cancels.

### Other toolbar controls
| Icon | Action |
|------|--------|
| ⟳ | Reload HTML |
| 🎯 Scope | Toggle element picking |
| 🗑 Trash | Delete selected element(s) |
| 🖼 Photo | Insert clipboard image (AVIF) after the selection |
| 🌐 Safari | Open in browser |
| 📁 Folder | Open file dialog |
| ☀/🌙 | Toggle dark/light mode |

### Text formatting and search
- `⌘F` find, with `⏎`/`⇧⏎` to step through matches
- `⌘B` / `⌘I` / `⌘U`, strikethrough, and highlight colours apply to the current text selection

### Layout
- Left: WKWebView HTML preview
- Right: feedback panel with agent selector, selected element context, chat transcript, and composer
- Drag divider to resize the preview and feedback panel

### Make default
Right-click .html → Get Info → Open with → HTML Agent Editor → Change All

## Prerequisites

Image insertion needs `avifenc` in PATH:

```bash
brew install libavif
```

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
- Temp files (clipboard bitmaps, the PNG/AVIF pair from image conversion) live in a single scratch directory that is wiped on every launch, so they cannot accumulate
- The Windows/Electron build in `windows/` does **not** yet have the direct-editing features above — it is behind the macOS app
