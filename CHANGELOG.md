# Changelog

## Unreleased

### Fixed
- Mode dial (`⇧⇥`) couldn't be steered on pages whose visible content lives inside an iframe (e.g. a shell page that loads each section via `iframe.srcdoc`). Wedge selection was tracked from the page's own `mousemove` listener, which never fires for events inside a child frame. Pointer position is now tracked from AppKit and forwarded into the page, so selection works regardless of iframes.

### Added
- Tab-cycle for the mode dial: while `⇧⇥` is held and the dial is up, tapping `⇥` again steps to the next wedge without needing the pointer.
