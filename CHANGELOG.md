# Changelog

## Unreleased

### Fixed
- Mode dial (`⇧⇥`) couldn't be steered on pages whose visible content lives inside an iframe (e.g. a shell page that loads each section via `iframe.srcdoc`). Wedge selection was tracked from the page's own `mousemove` listener, which never fires for events inside a child frame. Pointer position is now tracked from AppKit and forwarded into the page, so selection works regardless of iframes.
- That AppKit-forwarded pointer had its Y axis flipped twice (WKWebView is already a top-left-origin/flipped view, so the extra manual flip inverted it), which made the dial track the cursor backwards -- moving toward "Select" moved the highlight the wrong way. Removed the redundant flip.
- Tab was also used to cycle the dial's wedge selection, but holding it (the natural gesture, since Shift+Tab has to stay held to keep the dial open) triggers macOS key-repeat, spinning the selection uncontrollably. Cycling now runs off `A`, gated on `!event.isARepeat` so only discrete presses advance it.

### Added
- Press `A` while the mode dial (`⇧⇥`) is open to step to the next wedge without needing the pointer.
