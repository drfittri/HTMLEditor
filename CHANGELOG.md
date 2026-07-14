# Changelog

## Unreleased

### Changed
- The Windows/Electron port has been removed. The app is macOS-only.

### Fixed
- After an agent edit, the preview reloaded to the top of the document, throwing you out of whatever you were reading. The reload now remembers the element you were actually looking at and puts it back at the same place on screen, so the change appears under your eyes instead of moving the page. This applies to every reload the app does for you (agent edit, rewind, a file changed on disk, the reload button). It works on pages whose content scrolls inside a panel rather than scrolling the document itself (the common "sidebar plus scrollable main column" layout), it survives the agent inserting content above where you were reading, and it survives a page that resets its own scroll position while it boots. Scrolling yourself during the reload cancels the restore, so it can never fight you.
- Collapsing the agent panel silently switched off select mode, and there was no way to keep selecting elements while reading full-width. Collapsing now only hides the panel: the picker and the current selection stay exactly as they were.
- The chat panel sometimes showed an HTTP error ("404 / not found") as if the agent had said it, even though the OpenCode session itself looked perfectly fine. The panel was rendering the agent's entire raw output as the answer, so when the agent used a tool that hit a bad URL, the tool's failure text became the reply. OpenCode's output is now parsed as a structured event stream: only what the model actually says reaches the answer, tool failures go to Thinking (with their full error text, so nothing is hidden), and real errors are reported as errors instead of a bare exit code.
- OpenCode sessions could be hijacked across windows. Resuming used "continue the last session", which means the last session run anywhere on the machine, so a second editor window or an `opencode` run in a terminal could steal the turn. Each window now resumes its own session by id.

### Known issues
- OpenCode can lose track of earlier turns in a conversation when a file is attached, answering only from the file's contents rather than what was established a turn ago. The session is resumed correctly (same session id every turn, same behavior under both the old and new resume flags), so this is not a session-plumbing bug — the model appears to anchor on the attached file. The app attaches the file on every turn; attaching it only on the first turn is the obvious thing to try. Reproduced but not yet fixed.

## 1.2.0 - 2026-07-14

### Fixed
- Mode dial (`⇧⇥`) couldn't be steered on pages whose visible content lives inside an iframe (e.g. a shell page that loads each section via `iframe.srcdoc`). Wedge selection was tracked from the page's own `mousemove` listener, which never fires for events inside a child frame. Pointer position is now tracked from AppKit and forwarded into the page, so selection works regardless of iframes.
- That AppKit-forwarded pointer had its Y axis flipped twice (WKWebView is already a top-left-origin/flipped view, so the extra manual flip inverted it), which made the dial track the cursor backwards -- moving toward "Select" moved the highlight the wrong way. Removed the redundant flip.
- Tab was also used to cycle the dial's wedge selection, but holding it (the natural gesture, since Shift+Tab has to stay held to keep the dial open) triggers macOS key-repeat, spinning the selection uncontrollably. Cycling now runs off `A`, gated on `!event.isARepeat` so only discrete presses advance it.
- On the same class of iframe-hosted page, mode toggling (Select/Normal) always landed back in Select mode, and Bold/Italic/etc. always reported "Select some text first" even with real text selected. Both commands only ever ran in the main frame (`webView.evaluateJavaScript` can't reach a child frame), so a page whose actual content lives in an iframe never received them. Commands now fan out through the page itself (`window.__htmlAgentBroadcast`, via `postMessage`) to every frame, so whichever frame the user is actually looking at receives them. A frame with nothing to do (no selection, not the target) is a silent no-op, so an ordinary single-frame page behaves exactly as before.
- Formatting text inside an iframe has nowhere to write in the file (the iframe's content isn't literal markup anywhere in the source), so it's now treated the same way generated content already is: routed to the agent instead of silently failing or throwing.

### Added
- Press `A` while the mode dial (`⇧⇥`) is open to step to the next wedge without needing the pointer.
