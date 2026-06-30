# HTML Agent Editor — Fix Plan

**Goal:** Working, clean, beautiful, minimalist macOS developer tool.  
**Design direction:** Refined dark-first dev tool (Warp/Linear/Raycast aesthetic). Monochrome base, single green accent. No emojis in UI. Surgical, precise.

---

## Palette & Typography

| Token | Dark | Light |
|-------|------|-------|
| Background | `#0A0E17` | `#F4F5F7` |
| Surface | `#131920` | `#FFFFFF` |
| Surface raised | `#1C2333` | `#EAECF0` |
| Border | `#252D3D` | `#D0D5DD` |
| Text primary | `#E8ECF4` | `#0F1117` |
| Text secondary | `#6B7A99` | `#4A5568` |
| Accent | `#22C55E` | `#16A34A` |
| Destructive | `#EF4444` | `#DC2626` |

**Font:** SF Mono for terminal, SF Pro (system) for UI — no external fonts needed on macOS.

---

## 1. Bugs (Functional)

### BUG-01 — Dark mode icon wrong on first launch
**File:** `ViewController.swift:222` + `viewDidLoad:71`  
**Problem:** `darkModeButton` initialized with `"sun.max"` but initial `isDarkMode = false` (light mode). Icon and state mismatch.  
**Fix:** After setting `isDarkMode` in `viewDidLoad`, also update button icon:
```swift
// in viewDidLoad, after: isDarkMode = UserDefaults.standard.bool(forKey: "darkMode")
darkModeButton.image = .sf(isDarkMode ? "sun.max" : "moon", size: 14, weight: .medium)
darkModeButton.contentTintColor = isDarkMode ? NSColor.systemYellow : NSColor(white: 0.5, alpha: 1)
```

### BUG-02 — Commands echoed twice in terminal
**File:** `ViewController.swift:248–251` + PTY echo  
**Problem:** `sendCommand` manually appends "🚀 $ cmd" AND PTY echo repeats the command. User sees every command printed twice.  
**Fix:** Remove manual `textStorage.append` in `sendCommand`. The PTY echo is sufficient. Keep only `writeToPTY(cmd + "\n")`.

### BUG-03 — `strdup` args never freed (memory leak)
**File:** `TerminalView.swift:152–155`  
**Problem:** `strdup` allocates heap memory never freed.  
**Fix:** Use `withCString` pattern or defer `free()`:
```swift
let arg0 = strdup("-zsh")
let arg1 = strdup("-l")
defer { free(arg0); free(arg1) }
let args: [UnsafeMutablePointer<CChar>?] = [arg0, arg1, nil]
```

### BUG-04 — PTY column calc uses hardcoded 8px char width
**File:** `TerminalView.swift:348`  
**Problem:** `Int(scrollView.bounds.width / 8)` — char width is font-dependent. At 13pt SF Mono, actual char width ≈ 7.8px but varies.  
**Fix:** Measure actual char width from font:
```swift
let charWidth = terminalFont.advancement(forGlyph: terminalFont.glyph(withName: "m")).width
let cols = max(40, Int(scrollView.bounds.width / charWidth))
let rows = max(10, Int(scrollView.bounds.height / (terminalFont.ascender - terminalFont.descender + terminalFont.leading)))
```

### BUG-05 — Split view initial position timing hack
**File:** `ViewController.swift:140–143`  
**Problem:** `asyncAfter(deadline: .now() + 0.05)` to set divider position. Fragile race condition; may not work if load is slow.  
**Fix:** Implement `NSSplitViewDelegate` and set position in `splitViewDidResizeSubviews` on first call, or use `viewDidLayout`:
```swift
private var didSetInitialSplit = false
override func viewDidLayout() {
    super.viewDidLayout()
    guard !didSetInitialSplit else { return }
    let h = splitView.bounds.height
    guard h > 150 else { return }
    splitView.setPosition(h * 0.65, ofDividerAt: 0)
    didSetInitialSplit = true
}
```

### BUG-06 — Toolbar background found via fragile `subviews.first`
**File:** `ViewController.swift:268–271`  
**Problem:** `if let tb = view.subviews.first, tb.wantsLayer` — breaks if subview order changes.  
**Fix:** Store toolbar reference as ivar `private var toolbarView: NSView!` in makeToolbar and use directly in applyAppearance.

### BUG-07 — Progress indicator constraint crosses view hierarchy
**File:** `ViewController.swift:135–136`  
**Problem:** `progressIndicator.centerXAnchor.constraint(equalTo: webView.centerXAnchor)` — webView is inside webContainer, not a direct sibling. Auto Layout may warn.  
**Fix:** Constrain to `webContainer` instead (store webContainer as ivar), or position within webContainer itself.

### BUG-08 — `didFinish` fires on every subframe/redirect
**File:** `ViewController.swift:346–354`  
**Problem:** `terminalView.sendCommand("echo '✅ Rendered'")` fires on every navigation event including iframes. Spammy.  
**Fix:** Track main document URL. Only echo when `wv.url == currentFileURL`.

### BUG-09 — `sendCommand` called before PTY starts
**File:** `ViewController.swift:336`  
**Problem:** `loadFile` can be called (from `application(_:open:urls:)`) before 0.5s PTY start delay elapses. The echo `"📂 Opened: ..."` may be lost.  
**Fix:** Queue commands if PTY not yet started, drain on `startShell` completion.

### BUG-10 — Redundant `-l` flag with `-zsh` arg0
**File:** `TerminalView.swift:152–155`  
**Problem:** `argv[0] = "-zsh"` already signals login shell. Adding `"-l"` is redundant and may cause double `.zprofile` sourcing.  
**Fix:** Remove `"-l"` arg. Use only `[strdup("-zsh"), nil]`.

---

## 2. Missing Features (Documented but Not Implemented)

### FEAT-01 — Drag & drop (README claims it, code has none)
**Files:** `ViewController.swift`, `AppDelegate.swift`  
**Fix:** Register NSView for drag types in `viewDidLoad`:
```swift
view.registerForDraggedTypes([.fileURL])
// implement draggingEntered, performDragOperation
// filter for .html/.htm extensions
```

### FEAT-02 — File watcher / auto-reload
**Fix:** After `loadFile`, start `DispatchSourceFileSystemObject` watching the file for `.write` events. On write event, call `webView.reload()` after 100ms debounce. Show small "Auto-reloaded" indicator briefly.

### FEAT-03 — Keyboard shortcuts
**Fix:** Add `NSMenuItem` entries for:
- `⌘O` → Open file
- `⌘R` → Reload page
- `⌘K` → Clear terminal
- `⌘⇧D` → Toggle dark/light
- `⌘B` → Open in browser

### FEAT-04 — Empty state when no file open
**Fix:** Show a centered NSView in webContainer with:
- Icon: `doc.text.magnifyingglass` at 48pt
- Text: "Drop an HTML file here" (secondary label)
- Subtext: "or press ⌘O to open" (tertiary)
- Remove when `currentFileURL` is set

### FEAT-05 — macOS menu bar
**Fix:** Add proper `NSMenu` in AppDelegate:
```
File > Open (⌘O), Open Recent ▸, Reload (⌘R), Open in Browser (⌘⇧B)
View > Toggle Dark Mode (⌘⇧D), Clear Terminal (⌘K), Increase/Decrease Font (⌘+/-)
Agent > Claude (⌘1), Codex (⌘2), OpenCode (⌘3), Hermes (⌘4)
```

---

## 3. UI Design Overhaul

### UI-01 — Remove emojis from all UI strings
**Files:** `TerminalView.swift:176`, `ViewController.swift:248,297,335,352,358`  
**Fix:**
- `"🔌 Terminal sedia — taip command atau klik agent buttons\n"` → `"Terminal ready\n"` (English, no emoji)
- `"📂 Opened: \(path)"` → `"Opened: \(path)"`
- `"✅ Rendered"` → `"Rendered"` (or remove entirely, see BUG-08)
- `"❌ \(err)"` → `"Error: \(err)"`
- `"🚀 $ \(cmd)"` → `"$ \(cmd)"` (if kept at all — see BUG-02)
- `"📄 \(filename)"` → keep only filename in agent command echo
- `"⚠ No file open"` → `"Error: no file open"`

### UI-02 — Agent buttons: replace rounded bezel with borderless pill style
**File:** `ViewController.swift:177–192`  
**Problem:** `.bezelStyle = .rounded` gives system button appearance that clashes with custom dark toolbar.  
**Fix:** Make agent buttons borderless with custom background layer, matching utility button style. Use `isBordered = false`, custom hover background, and draw colored dot indicator instead of relying on bezel color:
```swift
btn.bezelStyle = .regularSquare
btn.isBordered = false
btn.wantsLayer = true
btn.layer?.backgroundColor = a.color.withAlphaComponent(0.12).cgColor
btn.layer?.cornerRadius = 6
btn.hoverColor = a.color.withAlphaComponent(0.22)
```

### UI-03 — Toolbar visual hierarchy
**File:** `ViewController.swift:makeToolbar()`  
**Current:** All elements same weight — logo, agents, utilities, path label, dark toggle compete equally.  
**Fix:**
- Logo: 18pt, accent color, left-most
- Agent buttons: grouped together, slightly dimmer text until hovered
- Vertical separator `NSBox` between agent group and utility group
- Utility buttons: icon-only, secondary color
- Path label: monospace 10pt, right-aligned, max-width 280pt, truncates from left
- Dark toggle: rightmost, always visible

### UI-04 — Hover color broken in light mode
**File:** `ViewController.swift:227,244`  
**Problem:** `hoverColor = NSColor.white.withAlphaComponent(0.08)` on a light gray toolbar = invisible hover.  
**Fix:** In `applyAppearance`, update all utility `HoverButton.hoverColor`:
```swift
let hoverBg = isDarkMode ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.06)
// iterate toolbar buttons and set hoverColor
```

### UI-05 — WebView empty white flash in dark mode
**File:** `ViewController.swift:103–119`  
**Problem:** WKWebView defaults white bg before page load. In dark mode = jarring white flash.  
**Fix:**
```swift
webView.setValue(false, forKey: "drawsBackground")
// set a matching dark NSView behind it:
webContainer.wantsLayer = true
webContainer.layer?.backgroundColor = NSColor(red: 0.04, green: 0.055, blue: 0.09, alpha: 1).cgColor
```

### UI-06 — Terminal startup message is Malay
**File:** `TerminalView.swift:176`  
**Fix:** `"Terminal ready — type commands or click agent buttons\n"` → then just `"Terminal ready\n"` is cleaner.

### UI-07 — Insertion point color tied to Hermes green always
**File:** `TerminalView.swift:86`  
**Problem:** `insertionPointColor = NSColor(red:0.247, green:0.725, blue:0.314, alpha:1)` hardcoded regardless of appearance.  
**Fix:** Use accent color `#22C55E` (same value, that's fine) but update in `applyColors()` for light mode:
```swift
textView.insertionPointColor = isDark ? NSColor(hex: "#22C55E") : NSColor(hex: "#16A34A")
```

### UI-08 — NSSplitView divider needs visual polish
**File:** `ViewController.swift:89–91`  
**Fix:** Subclass `NSSplitView` or use delegate `splitView(_:effectiveRect:forDrawnRect:ofDividerAt:)` to render a 1px accent-colored divider. Or use `dividerStyle = .paneSplitter` and override `dividerColor`.

### UI-09 — Add app icon
**File:** `Resources/Info.plist`  
**Fix:** Create an `.icns` file and add to `Resources/`. Add to Info.plist:
```xml
<key>CFBundleIconFile</key>
<string>AppIcon</string>
```
Design: `doc.text.magnifyingglass` SF Symbol rendered at icon sizes with accent green on dark background.

### UI-10 — Window title is generic
**File:** `ViewController.swift:333` + `AppDelegate.swift:24`  
**Fix:** Use subtitle API (macOS 11+):
```swift
window?.title = "HTML Agent Editor"
window?.subtitle = url.lastPathComponent  // shows smaller under title
// Remove " - filename" concatenation from title string
```

---

## 4. UX Improvements

### UX-01 — No feedback when agent button clicked with no file
**File:** `ViewController.swift:288–289`  
**Current:** `terminalView.sendCommand("echo '⚠ No file open'")` — buries the error in terminal.  
**Fix:** Show brief `NSPopover` or `NSAlert` sheet: "No file open. Use ⌘O to open an HTML file."

### UX-02 — No visual "active file" indicator
**Fix:** Show a colored dot or filename badge in toolbar when a file is loaded. Use a mini SF Symbol `doc.fill` + filename in the path label area. Clear on new file or close.

### UX-03 — Terminal clear loses context
**File:** `ViewController.swift:310`  
**Current:** `textView.string = ""` — clears everything.  
**Fix:** Clear then re-append `"Terminal ready\n"` so user knows terminal is still live.

### UX-04 — Split divider hard to grab
**Fix:** Increase hit area for divider by implementing `NSSplitViewDelegate.splitView(_:effectiveRect:forDrawnRect:ofDividerAt:)` returning a 12px-tall rect centered on the 1px line.

### UX-05 — Reload when no file does nothing silently
**File:** `ViewController.swift:301–303`  
**Fix:** Guard with no-op is correct but add a tooltip-style pulse on the reload button if called with no file. Or just disable the button when `currentFileURL == nil`.

### UX-06 — All toolbar buttons enabled with no file
**Fix:** Disable `reloadBtn`, `browserBtn`, and all agent buttons when `currentFileURL == nil`. Re-enable in `loadFile`. Use `isEnabled` property.

### UX-07 — Agent command doesn't show what it'll do
**Current:** Clicking "Claude" just runs `cd dir && claude` — no feedback on what's happening.  
**Fix:** Before sending command, scroll terminal into view and append a separator line:
```
─── Claude ────────────────────────────
```
Then send the command. Makes session context clearer.

### UX-08 — No way to resize terminal font
**Fix:** Add `⌘+` / `⌘-` support to change `terminalFont` point size (range 10–18pt). Persist in UserDefaults.

---

## 5. Code Quality

### CODE-01 — `strdump` is dead weight
**File:** `TerminalView.swift:357–360`  
`strdump` is just `strdup`. Remove it and use `strdup` directly everywhere.

### CODE-02 — `isDarkMode` didSet fires before view loaded
**File:** `ViewController.swift:51`  
Guard `guard isViewLoaded, darkModeButton != nil else { return }` to be safe.

### CODE-03 — `view.subviews.first` is fragile (already BUG-06)
Store toolbar as `private var toolbarView: NSView!`.

### CODE-04 — `applyAppearance` injects duplicate meta tags
**File:** `ViewController.swift:275–279`  
Every call appends a new `<meta>` tag. **Fix:** Check/remove existing before appending, or use `document.querySelector('meta[name="color-scheme"]')`.

### CODE-05 — No `NSError` domain check on webView failures
**File:** `ViewController.swift:356–366`  
Cancelled navigations (`NSURLErrorCancelled`, code -999) are not errors. Filter them:
```swift
if (err as NSError).code == NSURLErrorCancelled { return }
```

---

## Implementation Order

**Phase 1 — Bugs (do first, nothing else matters until these work):**
BUG-01, BUG-02, BUG-05, BUG-06, BUG-08, BUG-10

**Phase 2 — Core UX (usability blockers):**
UX-06 (disable buttons), FEAT-01 (drag & drop), FEAT-04 (empty state), FEAT-03 (keyboard shortcuts), UX-07 (agent feedback)

**Phase 3 — Visual polish:**
UI-01 (no emojis), UI-02 (agent button style), UI-03 (toolbar hierarchy), UI-04 (hover light mode), UI-05 (dark webview bg), UI-08 (divider), UI-10 (window subtitle)

**Phase 4 — Nice-to-have:**
BUG-03, BUG-04, BUG-07, BUG-09, FEAT-02 (file watcher), FEAT-05 (menu bar), UX-02, UX-03, UX-08, CODE-01–05, UI-09 (app icon)

---

## File Change Summary

| File | Changes |
|------|---------|
| `Sources/ViewController.swift` | BUG-01,05,06,07,08,09 · UI-01,02,03,04,05,10 · UX-01,02,05,06,07 · FEAT-01,03,04 · CODE-02,03,04,05 |
| `Sources/TerminalView.swift` | BUG-02,03,04,10 · UI-01,06,07 · UX-03,04,08 · CODE-01 |
| `Sources/AppDelegate.swift` | FEAT-05 (menu bar) · BUG-09 |
| `Resources/Info.plist` | UI-09 (app icon) |
| `build.sh` | No changes needed |
