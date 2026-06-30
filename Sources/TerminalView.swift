import Cocoa
import Darwin

// MARK: - PTY Terminal View

class TerminalView: NSView, NSTextViewDelegate {
    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    private var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var pid: pid_t = 0
    private var readSource: DispatchSourceRead?
    private let terminalQueue = DispatchQueue(label: "com.fittri.terminal.pty", qos: .userInteractive)
    private var buffer = Data()
    private(set) var isRunning = false
    private(set) var isShellReady = false
    private var inputHistory: [String] = []
    private var historyIndex: Int = 0
    private var currentLine: String = ""
    private let historyLock = NSLock()
    private var borderLayer: CALayer?
    private var isDark: Bool = true

    // Appearance
    var terminalBackgroundColor: NSColor = Palette.darkBackground {
        didSet { applyColors() }
    }
    var terminalTextColor: NSColor = Palette.darkTextPrimary {
        didSet { applyColors() }
    }
    var terminalBorderColor: NSColor = Palette.darkBorder {
        didSet { borderLayer?.borderColor = terminalBorderColor.cgColor }
    }
    var terminalFont: NSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) {
        didSet { applyColors(); updatePTYSize() }
    }

    var onCommand: ((String) -> Void)?
    private var didStartCallback: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        borderLayer = CALayer()
        borderLayer?.frame = bounds
        borderLayer?.borderWidth = 1
        borderLayer?.borderColor = terminalBorderColor.cgColor
        borderLayer?.cornerRadius = 10
        borderLayer?.masksToBounds = true
        borderLayer?.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if let bl = borderLayer { layer?.addSublayer(bl) }

        scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = terminalBackgroundColor
        addSubview(scrollView)

        textView = scrollView.documentView as? NSTextView
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = terminalBackgroundColor
        textView.textColor = terminalTextColor
        textView.font = terminalFont
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.allowsUndo = false
        textView.insertionPointColor = Palette.accentDark

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        applyColors()
    }

    func applyAppearance(dark: Bool) {
        isDark = dark
        terminalBackgroundColor = dark ? Palette.darkBackground : Palette.lightBackground
        terminalTextColor = dark ? Palette.darkTextPrimary : Palette.lightTextPrimary
        terminalBorderColor = dark ? Palette.darkBorder : Palette.lightBorder
        // UI-07: insertion point color follows appearance
        textView.insertionPointColor = dark ? Palette.accentDark : Palette.accentLight
    }

    private func applyColors() {
        textView.textColor = terminalTextColor
        textView.backgroundColor = terminalBackgroundColor
        scrollView.backgroundColor = terminalBackgroundColor
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = isDark ? .light : .dark
        borderLayer?.borderColor = terminalBorderColor.cgColor
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        borderLayer?.frame = bounds
        updatePTYSize()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        updatePTYSize()
    }

    // MARK: - PTY Lifecycle

    func startShell(onReady: (() -> Void)? = nil) {
        guard !isRunning else {
            onReady?()
            return
        }
        isRunning = true
        didStartCallback = onReady
        terminalQueue.async { [weak self] in
            self?.spawnPTY()
        }
    }

    private func spawnPTY() {
        var win = winsize()
        win.ws_row = 40
        win.ws_col = 120
        win.ws_xpixel = 0
        win.ws_ypixel = 0

        let result = forkpty(&masterFD, nil, nil, &win)
        guard result >= 0 else {
            appendOutput("Error: failed to create PTY (errno: \(errno))\n")
            isRunning = false
            return
        }

        if result == 0 {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
            let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
            let pathParts = [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "\(home)/.local/bin",
                inheritedPath,
                "/usr/bin:/bin:/usr/sbin:/sbin",
            ]
            setenv("TERM", "xterm-256color", 1)
            setenv("PATH", pathParts.joined(separator: ":"), 1)
            setenv("HOME", home, 1)
            setenv("SHELL", "/bin/zsh", 1)
            setsid()

            // BUG-10: remove redundant -l flag. arg0 = "-zsh" already signals login.
            // BUG-03: free strdup'd args via defer
            let shell = "/bin/zsh"
            let arg0 = strdup("-zsh")
            defer { free(arg0) }
            let args: [UnsafeMutablePointer<CChar>?] = [arg0, nil]
            _ = Darwin.execvp(shell.cString(using: .utf8), args)
            perror("execvp failed")
            _exit(1)
        }

        pid = result

        let readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: terminalQueue)
        readSource.setEventHandler { [weak self] in
            self?.handlePTYOutput()
        }
        readSource.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.masterFD >= 0 {
                close(self.masterFD)
                self.masterFD = -1
            }
        }
        readSource.resume()
        self.readSource = readSource

        // BUG-09: signal shell ready on main thread so caller can drain queue
        DispatchQueue.main.async { [weak self] in
            self?.isShellReady = true
            self?.didStartCallback?()
            self?.didStartCallback = nil
        }

        // UI-06: simple English message, no emoji
        appendOutput("Terminal ready\n")
    }

    private func handlePTYOutput() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(masterFD, &buf, buf.count)
        guard n > 0 else {
            if n == 0 {
                appendOutput("Session ended\n")
                cleanup()
            }
            return
        }
        let data = Data(bytes: buf, count: n)
        if let str = String(data: data, encoding: .utf8) {
            appendOutput(str)
        }
    }

    private func stripANSI(_ string: String) -> String {
        var result = string
        let pattern = "\\e\\[[0-9;:?]*[ABCDEFGHJKSTfhilmnsu]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        let oscPattern = "\\e\\].*?(\\a|\\e\\\\)"
        if let regex = try? NSRegularExpression(pattern: oscPattern, options: [.dotMatchesLineSeparators]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        let bsPattern = ".\u{7F}"
        if let regex = try? NSRegularExpression(pattern: bsPattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        return result
    }

    private func appendOutput(_ text: String) {
        let cleaned = stripANSI(text)
        guard !cleaned.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tv = self.textView else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: self.terminalFont,
                .foregroundColor: self.terminalTextColor,
            ]
            let attrStr = NSAttributedString(string: cleaned, attributes: attrs)
            tv.textStorage?.append(attrStr)
            tv.scrollToEndOfDocument(nil)
        }
    }

    func writeToPTY(_ text: String) {
        guard masterFD >= 0 else {
            // BUG-09: if not ready, swallow silently — caller should use sendOrQueue
            return
        }
        terminalQueue.async { [weak self] in
            guard let self = self else { return }
            if let data = text.data(using: .utf8) {
                data.withUnsafeBytes { ptr in
                    _ = Darwin.write(self.masterFD, ptr.baseAddress, data.count)
                }
            }
        }
    }

    // BUG-02: removed manual echo. PTY echo handles it.

    private func cleanup() {
        isRunning = false
        isShellReady = false
        readSource?.cancel()
        readSource = nil
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        if pid > 0 {
            kill(pid, SIGTERM)
            pid = 0
        }
    }

    deinit {
        cleanup()
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            let text = textView.string
            let lines = text.components(separatedBy: "\n")
            let lastLine = lines.last ?? ""
            let trimmed = lastLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmed.isEmpty {
                let cmd = trimmed + "\n"
                writeToPTY(cmd)
                onCommand?(trimmed)

                historyLock.lock()
                inputHistory.append(trimmed)
                historyIndex = inputHistory.count
                historyLock.unlock()
            }

            return false
        }

        if commandSelector == #selector(moveUp(_:)) {
            historyLock.lock()
            if !inputHistory.isEmpty && historyIndex > 0 {
                historyIndex -= 1
                let cmd = inputHistory[historyIndex]
                historyLock.unlock()
                replaceCurrentLine(with: cmd)
            } else {
                historyLock.unlock()
            }
            return true
        }

        if commandSelector == #selector(moveDown(_:)) {
            historyLock.lock()
            if historyIndex < inputHistory.count - 1 {
                historyIndex += 1
                let cmd = inputHistory[historyIndex]
                historyLock.unlock()
                replaceCurrentLine(with: cmd)
            } else {
                historyIndex = inputHistory.count
                historyLock.unlock()
                replaceCurrentLine(with: "")
            }
            return true
        }

        return false
    }

    private func replaceCurrentLine(with text: String) {
        guard let tv = textView else { return }
        let fullText = tv.string as NSString
        let range = fullText.lineRange(for: NSRange(location: fullText.length, length: 0))
        let lineStart = range.location
        tv.replaceCharacters(in: NSRange(location: lineStart, length: fullText.length - lineStart), with: text)
    }

    func clear() {
        // UX-03: re-append "Terminal ready" so user knows terminal is still live
        textView.string = ""
        let attrs: [NSAttributedString.Key: Any] = [
            .font: terminalFont,
            .foregroundColor: terminalTextColor.withAlphaComponent(0.5),
        ]
        let ready = NSAttributedString(string: "Terminal ready\n", attributes: attrs)
        textView.textStorage?.append(ready)
    }

    // UX-08: dynamic terminal font size
    func setFontSize(_ size: CGFloat) {
        let clamped = max(10, min(18, size))
        terminalFont = NSFont.monospacedSystemFont(ofSize: clamped, weight: .regular)
        UserDefaults.standard.set(Double(clamped), forKey: "terminalFontSize")
    }

    func increaseFont() { setFontSize(terminalFont.pointSize + 1) }
    func decreaseFont() { setFontSize(terminalFont.pointSize - 1) }

    // MARK: - Sizing (BUG-04)

    private func updatePTYSize() {
        guard masterFD >= 0 else { return }
        let glyph = terminalFont.glyph(withName: "m")
        let charWidth: CGFloat
        if terminalFont.advancement(forGlyph: glyph).width > 0 {
            charWidth = terminalFont.advancement(forGlyph: glyph).width
        } else {
            charWidth = terminalFont.maximumAdvancement.width
        }
        let lineHeight = terminalFont.ascender - terminalFont.descender + terminalFont.leading
        let cols = max(40, Int(scrollView.bounds.width / max(charWidth, 1)))
        let rows = max(10, Int(scrollView.bounds.height / max(lineHeight, 1)))
        var win = winsize()
        win.ws_row = UInt16(rows)
        win.ws_col = UInt16(cols)
        _ = ioctl(masterFD, TIOCSWINSZ, &win)
    }
}
