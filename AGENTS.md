# AGENTS.md

Working notes and continuity log for AI agents (and humans) doing work in this repo.

## Rule: keep this file up to date

**Any agent that changes this project MUST append an entry to the Work Log at the
bottom before finishing.** This is how we keep continuity across sessions that each
start with no memory of the last.

For every unit of work, add a dated entry that records:

1. **Date** and who/what did the work (agent name/model if known).
2. **Goal** — what the user asked for, in one or two lines.
3. **Changes** — files touched and what changed in each, at a level a future agent can act on.
4. **Decisions and trade-offs** — especially anything deliberately NOT done, and why.
5. **Verification** — what was checked (build, lint, tests, manual) and what remains unverified.
6. **Follow-ups** — known risks, TODOs, or things to confirm next.

Keep newest entries at the top of the Work Log. Do not delete old entries; append.

## Project overview

`HTML Agent Editor` is a native app to open an HTML file, render it in a WebView,
click page elements, and send precise edit/chat requests to a local agent CLI
(Claude, Codex, OpenCode, Antigravity/`agy`, Hermes).

Two codebases, kept at feature parity:

- **macOS (primary):** Swift + AppKit + WebKit, no Xcode/SPM. Single big file
  `Sources/ViewController.swift` (~3k lines) holds the UI and agent logic.
  Build with `./build.sh`. Minimum macOS 14.
- **Windows:** Electron port under `windows/src/` — `main.js` (process/agent
  orchestration, IPC), `renderer.js` (UI logic), `preload.js` (IPC bridge),
  `index.html`, `styles.css`. Run with `cd windows && npm start`.

**Parity rule:** a behavior change on one platform should be mirrored on the other.
The Swift `ViewController` and the Electron `main.js` + `renderer.js` are the two
sides that must stay in sync.

> **Parity debt (2026-07-05):** the five features in the 2026-07-05 Work Log entry
> (fresh-context-on-switch, Cmd+F find, text formatting, token-lean element context,
> Markdown chat rendering) were done on **macOS only** by explicit user request. The
> Windows/Electron port does not yet have them. See that entry for a per-feature port map.

## How the agent integration works (as of the latest entry)

- Each user message runs a local agent CLI. The app builds the command in
  `agentCommand` (Swift) / `agentProcess` (Electron `main.js`).
- **Two modes:** `edit` (agent writes the file directly, preview reloads) and `chat`
  (agent answers questions; if it changes the file, the app restores it after the run).
- **Sessions:** the app reuses one native CLI session per agent so prompt caching /
  native resume reuse context instead of re-sending history each turn. Session identity
  is **per-agent, not per-mode** — switching chat↔edit continues the same session.
  `canResumeSession(agent)` (Swift) / `canResumeSession()` (Electron `renderer.js`)
  decides resume:
  - Gated by the **"Use Context"** checkbox (`includeEditContext`), which is the
    continuity master switch. A live session is dropped by the **New Session**
    button, opening a new file, **switching agent, or switching model**. Switching
    agent/model calls `resetAgentContext(...)` which clears the hidden context
    (`sessionMessages`, `claudeSessionID`, `sessionActiveAgentID`) but keeps the visible
    transcript and user attachments. This prevents a prior agent's history from being
    text-injected into the new agent's first turn (the old token-bloat bug).
  - Claude uses an explicit id: `--session-id <uuid>` on turn 1, `--resume <uuid>` after.
    Kept per-window so it is immune to other windows' "most recent" lookup.
  - Codex uses `exec resume --last`. The non-resume turn creates the session with
    `--sandbox danger-full-access` so either mode can resume it.
  - OpenCode and `agy` use `-c` (continue last session).
  - Textual history is injected into the prompt only on the first turn of a session
    (`includeHistory` = not resuming), so resumed turns don't re-send prior context.
- **Undo:** a successful edit that changed the file pushes a snapshot onto a
  multi-level undo stack (`editUndoStack` in Swift, `editUndoStacks` per-window in
  Electron `main.js`). The rewind button pops the most recent snapshot; repeated
  rewinds walk back through history. Reset when opening a new file.
- **Permissions:** Codex sandbox is `danger-full-access` in edit; chat safety comes
  from the post-run file restore, not the sandbox. Claude/OpenCode/`agy` use
  `--dangerously-skip-permissions`.

## Conventions and gotchas

- **This sandbox cannot compile Swift** unless run on a Mac with the macOS SDK. Verify
  JS with `node --check windows/src/<file>.js`. For Swift, keep brace/paren/bracket
  counts balanced, review diffs carefully, then build with `./build.sh` on a Mac.
- Do not expose internal/session file paths to users.
- Agent resume flags differ per CLI and per version. When adding/altering a resume
  path, confirm the exact flag against that CLI's current docs before shipping.
- No em dashes in user-facing copy is a maintainer preference; not enforced in code.

## Work Log

### 2026-07-05 — Fresh-context-on-switch, Cmd+F find, text formatting, token-lean element context, Markdown chat (Claude, opus-4-8)

**Scope:** macOS only, by explicit user request. Windows/Electron intentionally not touched
(see Parity debt above). Rebuilt with `./build.sh` after the changes.

**Goal (5 asks):**
1. Switching agent (repro: OpenCode -> Codex) or model was injecting the previous agent's
   conversation as text into the new agent's first prompt, bloating tokens. Start fresh.
2. Add a browser-style Find (Cmd+F) over the preview.
3. Add text formatting: select text in the preview, Cmd+B/I/U + a right-click highlight-color
   dropdown; changes must persist to the HTML file.
4. Shrink the element context sent to the agent (the full outerHTML was huge) while keeping it
   precise/unique so the agent can still locate the element with few grep hits.
5. Make chat-mode agent output readable instead of raw plain text.

**Changes:**

- `Sources/ViewController.swift`
  - **(1) Fresh context on switch.** New `resetAgentContext(statusMessage:)` clears
    `sessionMessages` + `claudeSessionID` + `sessionActiveAgentID` but keeps the visible
    transcript (`chatMessages`) and `attachedContexts`. `startAgent(index:)` now captures the
    previous agent id and calls it when the agent actually changes. `modelPopupChanged()` calls
    it when the model id actually changes. Root cause of the bug: on a switch,
    `canResumeSession` returns false for the new agent, so `includeHistory` became true and
    `sessionContext()` (the OLD agent's turns) was appended to the new prompt. Clearing
    `sessionMessages` removes that injected history.
  - **(2) Find (Cmd+F).** New `findEngineScript()` injected as a main-frame user script. Uses
    the **CSS Custom Highlight API** (`Highlight` + `CSS.highlights`) so matches are painted
    without mutating the DOM (no cleanup artifacts, no interference with the picker or with
    serialize-on-save). Exposes `__htmlAgentFind(query, caseSensitive)`, `__htmlAgentFindStep(fwd)`,
    `__htmlAgentFindClear()` returning `{total,current}`. Swift side: `makeFindBar()` overlay
    (top-right of the preview), `menuFind`/`showFindBar`/`closeFindBar`/`performFind`/`stepFind`/
    `updateFindCount`, live search via `controlTextDidChange`, Return=next / Shift+Return=prev /
    Esc=close via `control(_:textView:doCommandBy:)`. `styleFindBar()` themed in `applyAppearance`.
    Requires macOS 14 (Safari 17.2+) which is already the app minimum; falls back to scroll-only.
  - **(3) Text formatting.** New `formatEngineScript()` (main-frame). Applies formatting with
    `execCommand` under a **momentarily** `contenteditable` body (`withEditable`) so toggling +
    multi-node selections work for free, then returns `__htmlAgentSerialize()` — a cleaned clone
    of `document.documentElement` (strips `[data-html-agent-style]`, `meta[data-html-agent]`,
    `__html_agent_*` classes, leftover `contenteditable`, and the dark-mode inline styles the app
    paints on `<html>`), prefixed with a reconstructed doctype. Swift `applyFormat(kind:value:)`
    writes the returned HTML back to the file, pushes an undo snapshot onto `editUndoStack` (so
    the existing rewind button undoes formatting), and briefly sets `suppressReloadUntil` +
    re-arms the file watcher so the atomic write doesn't cause a preview flash. `menuBold/Italic/
    Underline/Strikethrough/RemoveFormatting` and `menuHighlight(_:)` (tag -> color, tag -1 =
    remove). Right-click menu built in `DragWebView.willOpenMenu` (only when text is selected;
    tracked via a `selectionchange` listener -> `textSelectionChanged` message handler ->
    `hasWebTextSelection`). Highlight palette: yellow/green/blue/pink/orange.
  - **(4) Token-lean element context.** JS `summarize()` no longer sends up-to-1200-char
    `outerHTML`. It now sends: `openTag` (reconstructed opening tag, agent classes stripped, long
    attr values clipped — a compact, usually-unique grep anchor), `htmlSnippet` (head 240 + tail
    100 with a "[N chars truncated]" marker when > 400), a 200-char `text`, and the `selector`.
    `SelectedElement` fields changed `html` -> `openTag` + `htmlSnippet`. `updateSelectedElementSummary`
    emits a compact block (`signature`, `visible text`, truncated `html`). `agentPrompt` gained a
    line telling the agent to grep the signature/visible-text to locate the element and that the
    HTML is truncated.
  - **(5) Markdown chat.** Agent bubbles in `makeChatMessageView` now render via
    `MarkdownRenderer` and are selectable. Other message kinds unchanged.
  - Registered the `textSelectionChanged` script message handler; tagged the picker `<style>` and
    the injected color-scheme `<meta>` with `data-html-agent[-style]` so serialize strips them.
  - Added `NSTextFieldDelegate` + `NSMenuItemValidation` conformances (format items enabled only
    when a file is open AND text is selected; Find enabled when a file is open).
- `Sources/MarkdownRenderer.swift` (new). Dependency-free Markdown -> `NSAttributedString`:
  headings, bold/italic/inline-code, fenced code blocks, ordered/unordered lists, blockquotes,
  horizontal rules, links, strikethrough; theme-aware via a `Theme` struct. Recursive inline
  parser for nested emphasis.
- `Sources/AppDelegate.swift` — Edit menu gained **Find… (Cmd+F)**; new **Format menu**: Bold
  (Cmd+B), Italic (Cmd+I), Underline (Cmd+U), Strikethrough (Shift+Cmd+X), Highlight submenu
  (5 colors + Remove Highlight), Remove Formatting (Shift+Cmd+\\). All route through the
  responder chain to `ViewController`.
- `build.sh` — added `MarkdownRenderer.swift` to `SOURCE_FILES`.

**Decisions / trade-offs:**
- Formatting **re-serializes the whole document** via the browser (DOM is authoritative). This is
  the pragmatic way to persist edits, but it normalizes indentation/quoting/self-closing tags, so
  hand-written HTML may show large diffs. Chosen over byte-level surgical editing (DOM->file offset
  mapping is too fragile). User approved this behavior.
- On agent/model switch we keep the visible transcript and only reset the hidden context (user
  choice), so the user can still read old messages even though the new agent won't receive them.
- Attachments (`attachedContexts`) are preserved across switch (explicit user intent, not "prior
  conversation"). Only **New Session** clears them.
- Formatting uses the deprecated-but-fully-supported `execCommand`; acceptable for a local WebKit
  tool and gives correct toggle/multi-node behavior without hand-rolling range surgery.
- `hiliteColor 'transparent'` is best-effort highlight removal; "Remove Formatting" (`removeFormat`)
  is the reliable clear-all.

**Verification:**
- `./build.sh` on the Mac: **exit 0, 0 warnings**, arm64 Mach-O produced (~1.4 MB).
- Swift brace/paren/bracket balance verified with a Swift-aware tokenizer (handles multiline
  strings, interpolation, comments) — all balanced.
- The three injected JS engines (picker/find/format) extracted and passed `node --check`.
- NOT yet GUI-tested this session: actual Cmd+F highlighting, formatting round-trip to disk, and
  the context-reset behavior across a real OpenCode->Codex turn. Recommend a manual pass.

**Follow-ups / risks:**
- Manually confirm: (a) Cmd+F highlights + count on a real file; (b) Cmd+B on a text selection
  saves and survives reload, and rewind undoes it; (c) right-click shows format items only with a
  selection; (d) OpenCode->Codex no longer carries OpenCode history (inspect via Think).
- The picker intercepts left-clicks; text formatting relies on **drag-select** (which doesn't fire
  a click) so the two coexist. If users report the picker stealing text selections, consider a
  modifier or a mode toggle.
- Whole-document re-serialization on format is invasive for large/hand-authored files; consider a
  more surgical approach later if diffs become a problem.
- **Port to Windows** for parity: (1) reset context in `renderer.js` on agent/model change;
  (2) find bar + a JS find engine in `preview-preload.js`; (3) formatting + serialize + write-back
  in `main.js`/`preview-preload.js`; (4) token-lean summarize in `preview-preload.js`;
  (5) Markdown rendering in `renderer.js` (a JS md library or a small renderer).

### 2026-07-04 — Mode-independent sessions, multi-level undo, AGENTS.md (Claude, opus-4-8)

**Goal:** (1) Switching chat↔edit was starting a brand-new agent session each time;
make both modes share one session, resetting only via the New Session button.
(2) Port two things from an abandoned remote branch the user reverted: a multi-level
undo stack and this AGENTS.md continuity log.

**Changes:**

- `Sources/ViewController.swift`
  - `canResumeSession` no longer takes/checks `mode`; resume is per-agent and gated
    only by `includeEditContext`. Termination handler marks the session resumable after
    both chat and edit. Claude `--session-id`/`--resume` and Codex sandbox now apply to
    both modes (Codex non-resume turn uses `danger-full-access` so either mode can
    resume it). `includeHistory` = `!resume && (mode == .chat || includeEditContext)`.
  - Replaced single-level `lastEditSnapshot` with `editUndoStack`; `rewindLastEdit`
    pops the stack, `updateRewindButton` reflects depth, reset on new-file load.
- `windows/src/renderer.js`, `windows/src/main.js` — mirrored the session and undo
  changes. `canResumeSession()` drops the mode gate; claude session keyed per-agent for
  both modes; codex sandbox `danger-full-access`; `editUndoStacks` per-window stack,
  `rewindLastEdit` pops and returns `remaining`.
- Added `AGENTS.md`. Removed stale scratch file `fix.md`.

**Decisions / trade-offs:**

- Deliberately did NOT adopt the reverted remote branch's diff-review card, session-tier
  UI, or token counter — the user reported that branch broke something and wanted the
  current local behavior kept, plus only these two features cherry-picked.
- Codex chat now runs `danger-full-access` (was `read-only`) so one session can span
  both modes; chat safety relies on the existing post-run file restore.

**Verification:** `./build.sh` compiles clean (arm64). `node --check` passes for
`main.js`/`renderer.js`. User confirmed chat↔edit continuity works in OpenCode.
Not GUI-tested for Claude/Codex this session.

**Follow-ups:** Confirm Codex `exec resume --last` holds context over 2–3 turns on the
installed CLI. Consider clearing the Electron undo stack on file open in `main.js`
(currently only guarded by the snapshot's filePath check).
