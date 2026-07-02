# HTML Agent Editor for Windows

Windows-compatible Electron version of the macOS HTML Agent Editor.

## Features

- Chromium preview for local `.html` and `.htm` files
- Click-to-select DOM elements in the preview
- Agent and model selector for Claude, Codex, OpenCode, and Hermes
- Chat-style edit requests sent to local agent CLIs
- File watching with automatic preview reload
- Drag and drop HTML files
- Dark and light mode
- File association support when packaged with the installer

## Requirements

- Windows 10 or newer
- Node.js LTS
- The agent CLIs you want to use available in `PATH`

Agent CLI commands:

- `claude`
- `codex`
- `opencode`
- `hermes`

## Run In Development

```powershell
cd .\windows
npm install
npm start
```

## Build Installer

Run this from PowerShell on Windows:

```powershell
cd .\windows
.\build-windows.ps1
```

Output:

```text
windows\dist\HTML-Agent-Editor-Windows-x64-Portable-1.0.0.exe
windows\dist\HTML-Agent-Editor-Windows-x64-Portable-1.0.0.zip
```

If Windows blocks the downloaded `.exe` with “Windows cannot access the specified device, path, or file,” use the `.zip` release instead. Extract it, then run `HTML Agent Editor.exe` from the extracted folder.

## Notes

The original Swift app remains the native macOS build. This Windows app is a separate Electron implementation because Cocoa, WebKit, SF Symbols, AppleScript, and `/bin/zsh` do not run on Windows.
