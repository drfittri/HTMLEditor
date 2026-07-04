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
    continuity master switch. A live session is dropped only by the **New Session**
    button, opening a new file, or switching agent.
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
