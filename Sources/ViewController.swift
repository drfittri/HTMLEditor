import Cocoa
import WebKit

// MARK: - Color Palette

enum Palette {
    static let darkBackground = NSColor(red: 0.039, green: 0.055, blue: 0.090, alpha: 1)
    static let darkSurface = NSColor(red: 0.075, green: 0.098, blue: 0.125, alpha: 1)
    static let darkSurfaceRaised = NSColor(red: 0.110, green: 0.137, blue: 0.200, alpha: 1)
    static let darkBorder = NSColor(red: 0.145, green: 0.176, blue: 0.239, alpha: 1)
    static let darkTextPrimary = NSColor(red: 0.910, green: 0.925, blue: 0.957, alpha: 1)
    static let darkTextSecondary = NSColor(red: 0.420, green: 0.478, blue: 0.600, alpha: 1)

    static let lightBackground = NSColor(red: 0.957, green: 0.961, blue: 0.969, alpha: 1)
    static let lightSurface = NSColor(white: 1, alpha: 1)
    static let lightSurfaceRaised = NSColor(red: 0.918, green: 0.925, blue: 0.941, alpha: 1)
    static let lightBorder = NSColor(red: 0.816, green: 0.835, blue: 0.866, alpha: 1)
    static let lightTextPrimary = NSColor(red: 0.059, green: 0.067, blue: 0.090, alpha: 1)
    static let lightTextSecondary = NSColor(red: 0.290, green: 0.333, blue: 0.408, alpha: 1)

    static let accentDark = NSColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1)
    static let accentLight = NSColor(red: 0.086, green: 0.639, blue: 0.290, alpha: 1)
    static let destructive = NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)

    static func background(dark: Bool) -> NSColor { dark ? darkBackground : lightBackground }
    static func surface(dark: Bool) -> NSColor { dark ? darkSurface : lightSurface }
    static func surfaceRaised(dark: Bool) -> NSColor { dark ? darkSurfaceRaised : lightSurfaceRaised }
    static func border(dark: Bool) -> NSColor { dark ? darkBorder : lightBorder }
    static func textPrimary(dark: Bool) -> NSColor { dark ? darkTextPrimary : lightTextPrimary }
    static func textSecondary(dark: Bool) -> NSColor { dark ? darkTextSecondary : lightTextSecondary }
    static func accent(dark: Bool) -> NSColor { dark ? accentDark : accentLight }
    static func hover(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.05)
    }
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - SF Symbol Helper

extension NSImage {
    static func sf(_ name: String, size: CGFloat = 16, weight: NSFont.Weight = .regular) -> NSImage {
        let c = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        img.isTemplate = true
        return img.withSymbolConfiguration(c)!
    }
}

// MARK: - HoverButton

class HoverButton: NSButton {
    var hoverColor: NSColor = .clear
    var cornerRadius: CGFloat = 6
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        wantsLayer = true
        layer?.backgroundColor = hoverColor.cgColor
        layer?.cornerRadius = cornerRadius
    }

    override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = .clear
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
    }
}

// MARK: - Padded Separator

final class PaddedSeparator: NSBox {
    override var intrinsicContentSize: NSSize {
        var s = super.intrinsicContentSize
        s.height = 18
        return s
    }
}

// MARK: - Split View Container (UI-08: accent divider with 12px hit area)

final class PolishedSplitView: NSSplitView {
    var isDark: Bool = true

    override var dividerColor: NSColor {
        isDark ? Palette.darkBorder : Palette.lightBorder
    }

    override func drawDivider(in rect: NSRect) {
        dividerColor.setFill()
        let line: NSRect
        if isVertical {
            line = NSRect(x: rect.midX - 0.5, y: rect.minY, width: 1, height: rect.height)
        } else {
            line = NSRect(x: rect.minX, y: rect.midY - 0.5, width: rect.width, height: 1)
        }
        line.fill()
    }
}

// MARK: - ViewController

class ViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, NSSplitViewDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var webContainer: NSView! // actually DragContainerView
    private var rightPanel: NSView!
    private var chatContainer: NSView!
    private var chatScrollView: NSScrollView!
    private var chatMessageStack: NSStackView!
    private var chatInput: NSTextField!
    private var chatInputBox: NSView!
    private var chatSendButton: NSButton!
    private var activeAgentLabel: NSTextField!
    private var agentPopup: NSPopUpButton!
    private var processToggleButton: HoverButton!
    private var selectedElementBox: NSView!
    private var selectedElementLabel: NSTextField!
    private var selectedElementDetail: NSTextField!
    private var pickerButton: HoverButton!
    private var terminalView: TerminalView!
    private var splitView: PolishedSplitView!
    private var currentFileURL: URL?
    private var selectedElementContext: String?
    private var selectedElements: [SelectedElement] = []
    private var isPickerEnabled = true
    private var activeAgentIndex: Int?
    private var runningAgentProcess: Process?
    private var progressIndicator: NSProgressIndicator!
    private var isDarkMode: Bool = true {
        didSet {
            guard isViewLoaded, view.window != nil else { return }
            applyAppearance()
        }
    }

    // Toolbar pieces (stored as ivars per BUG-06 / CODE-03)
    private var toolbarView: NSView!
    private var logoView: NSImageView!
    private var darkModeButton: HoverButton!
    private var reloadBtn: HoverButton!
    private var chatToggleButton: HoverButton!
    private var browserBtn: HoverButton!
    private var openBtn: HoverButton!

    // Empty state
    private var emptyStateView: NSView!
    private var emptyStateIcon: NSImageView!
    private var emptyStateTitle: NSTextField!
    private var emptyStateSub: NSTextField!

    // File watcher (FEAT-02)
    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var fileWatcherFD: Int32 = -1
    private var fileWatcherDebounce: DispatchWorkItem?

    // Split initial position latch (BUG-05)
    private var didSetInitialSplit = false
    private var isChatCollapsed = false
    private var showAgentProcess = false
    private var chatMessages: [ChatMessage] = []
    private var lastAnimatedMessageCount = 0

    private enum ChatKind {
        case user
        case agent
        case status
        case selection
        case error
        case process
    }

    private struct ChatMessage {
        let kind: ChatKind
        let text: String
    }

    private struct SelectedElement {
        let label: String
        let selector: String
        let text: String
        let html: String
    }

    private let agentMeta: [(id: String, label: String, icon: String, color: NSColor)] = [
        ("claude", "Claude", "brain.head.profile",
         NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1)),
        ("codex", "Codex", "terminal",
         NSColor(red: 1, green: 0.549, blue: 0.259, alpha: 1)),
        ("opencode", "OpenCode", "chevron.left.forwardslash.chevron.right",
         NSColor(red: 0.608, green: 0.494, blue: 0.871, alpha: 1)),
        ("hermes", "Hermes", "sparkles",
         NSColor(red: 0.247, green: 0.725, blue: 0.314, alpha: 1)),
    ]

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        isDarkMode = UserDefaults.standard.bool(forKey: "darkMode")
        applyAppearance()
        updateDarkModeIcon()
        updateEmptyState()
        updateFileButtonsEnabled()

        // TerminalView remains hidden as a lightweight reusable PTY component,
        // but chat uses one-shot agent commands for predictable feedback.
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // BUG-05: set initial split position on first layout
        guard !didSetInitialSplit else { return }
        let w = splitView.bounds.width
        guard w > 500 else { return }
        splitView.setPosition(max(620, w - 360), ofDividerAt: 0)
        didSetInitialSplit = true
    }

    // MARK: - Build UI

    private func buildUI() {
        toolbarView = makeToolbar()
        view.addSubview(toolbarView)
        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 34),
        ])

        splitView = PolishedSplitView(frame: .zero)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.delegate = self
        view.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Web container with dark bg (UI-05)
        // Use auto layout for the webContainer too. NSSplitView's arranged subviews
        // can be auto-layout based with the right minSize/holdingPriority setup.
        let container = DragContainerView(frame: NSRect(x: 0, y: 0, width: 840, height: 756))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = Palette.darkBackground.cgColor
        container.dragHandler = self
        splitView.addArrangedSubview(container)
        self.webContainer = container

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        let userContent = WKUserContentController()
        userContent.add(self, name: "elementPicked")
        userContent.addUserScript(WKUserScript(source: elementPickerScript(), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        config.userContentController = userContent
        webView = WKWebView(frame: container.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        // UI-05: transparent drawsBackground lets dark webContainer show through during load
        webView.setValue(false, forKey: "drawsBackground")
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Progress indicator — BUG-07: constrain to webContainer
        progressIndicator = NSProgressIndicator(frame: .zero)
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(progressIndicator)
        NSLayoutConstraint.activate([
            progressIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        // Empty state (FEAT-04)
        emptyStateView = makeEmptyState()
        container.addSubview(emptyStateView)
        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyStateView.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])

        terminalView = TerminalView(frame: NSRect(x: -400, y: -400, width: 240, height: 120))
        terminalView.isHidden = true
        view.addSubview(terminalView)

        rightPanel = makeRightPanel()
        splitView.addArrangedSubview(rightPanel)
    }

    private func makeRightPanel() -> NSView {
        let panel = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 756))
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.wantsLayer = true
        panel.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        panel.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true

        chatContainer = makeChatContainer()
        panel.addSubview(chatContainer)
        NSLayoutConstraint.activate([
            chatContainer.topAnchor.constraint(equalTo: panel.topAnchor),
            chatContainer.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            chatContainer.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            chatContainer.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
        ])

        return panel
    }

    private func makeChatContainer() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 756))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        stack.addArrangedSubview(header)

        let title = NSTextField(labelWithString: "Edit")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        header.addArrangedSubview(title)

        let flex = NSView(frame: .zero)
        flex.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(flex)

        activeAgentLabel = NSTextField(labelWithString: "")
        activeAgentLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        activeAgentLabel.lineBreakMode = .byTruncatingTail

        processToggleButton = HoverButton(image: .sf("doc.text.magnifyingglass", size: 12, weight: .medium), target: self, action: #selector(toggleAgentProcess))
        processToggleButton.title = "Work"
        processToggleButton.bezelStyle = .regularSquare
        processToggleButton.isBordered = false
        processToggleButton.imagePosition = .imageLeading
        processToggleButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        processToggleButton.toolTip = "Show agent working output"
        processToggleButton.cornerRadius = 6
        processToggleButton.widthAnchor.constraint(equalToConstant: 66).isActive = true
        processToggleButton.heightAnchor.constraint(equalToConstant: 26).isActive = true

        agentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        agentPopup.translatesAutoresizingMaskIntoConstraints = false
        agentPopup.bezelStyle = .inline
        agentPopup.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        agentPopup.addItem(withTitle: "Choose agent")
        for agent in agentMeta {
            agentPopup.addItem(withTitle: agent.label)
        }
        agentPopup.target = self
        agentPopup.action = #selector(agentPopupChanged)
        header.addArrangedSubview(agentPopup)
        header.addArrangedSubview(processToggleButton)
        agentPopup.widthAnchor.constraint(equalToConstant: 128).isActive = true
        agentPopup.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let targetBox = NSView()
        targetBox.translatesAutoresizingMaskIntoConstraints = false
        targetBox.wantsLayer = true
        targetBox.layer?.cornerRadius = 12
        targetBox.layer?.borderWidth = 1
        selectedElementBox = targetBox
        stack.addArrangedSubview(targetBox)

        let targetStack = NSStackView()
        targetStack.orientation = .vertical
        targetStack.spacing = 7
        targetStack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        targetStack.translatesAutoresizingMaskIntoConstraints = false
        targetBox.addSubview(targetStack)
        NSLayoutConstraint.activate([
            targetStack.topAnchor.constraint(equalTo: targetBox.topAnchor),
            targetStack.bottomAnchor.constraint(equalTo: targetBox.bottomAnchor),
            targetStack.leadingAnchor.constraint(equalTo: targetBox.leadingAnchor),
            targetStack.trailingAnchor.constraint(equalTo: targetBox.trailingAnchor),
        ])

        let targetHeader = NSStackView()
        targetHeader.orientation = .horizontal
        targetHeader.alignment = .centerY
        targetHeader.spacing = 6
        targetStack.addArrangedSubview(targetHeader)

        selectedElementLabel = NSTextField(labelWithString: "No element selected")
        selectedElementLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        targetHeader.addArrangedSubview(selectedElementLabel)

        let targetFlex = NSView(frame: .zero)
        targetFlex.setContentHuggingPriority(.defaultLow, for: .horizontal)
        targetHeader.addArrangedSubview(targetFlex)

        pickerButton = HoverButton(image: .sf("scope", size: 13, weight: .medium), target: self, action: #selector(togglePicker))
        pickerButton.title = ""
        pickerButton.bezelStyle = .regularSquare
        pickerButton.isBordered = false
        pickerButton.imagePosition = .imageOnly
        pickerButton.toolTip = "Toggle element picking"
        pickerButton.cornerRadius = 6
        pickerButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        pickerButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        targetHeader.addArrangedSubview(pickerButton)

        selectedElementDetail = NSTextField(wrappingLabelWithString: "Click any visible element in the preview. The selected DOM context will be sent with your next message.")
        selectedElementDetail.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        selectedElementDetail.maximumNumberOfLines = 3
        selectedElementDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        targetStack.addArrangedSubview(selectedElementDetail)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        stack.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        let messageDocument = NSView(frame: .zero)
        messageDocument.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = messageDocument
        chatScrollView = scroll

        chatMessageStack = NSStackView()
        chatMessageStack.orientation = .vertical
        chatMessageStack.alignment = .leading
        chatMessageStack.spacing = 12
        chatMessageStack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 12, right: 16)
        chatMessageStack.translatesAutoresizingMaskIntoConstraints = false
        messageDocument.addSubview(chatMessageStack)
        NSLayoutConstraint.activate([
            messageDocument.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            chatMessageStack.topAnchor.constraint(equalTo: messageDocument.topAnchor),
            chatMessageStack.bottomAnchor.constraint(equalTo: messageDocument.bottomAnchor),
            chatMessageStack.leadingAnchor.constraint(equalTo: messageDocument.leadingAnchor),
            chatMessageStack.trailingAnchor.constraint(equalTo: messageDocument.trailingAnchor),
        ])
        resetChatIntro()

        let inputShell = NSView()
        inputShell.translatesAutoresizingMaskIntoConstraints = false
        inputShell.wantsLayer = true
        inputShell.layer?.cornerRadius = 12
        inputShell.layer?.borderWidth = 1
        chatInputBox = inputShell
        stack.addArrangedSubview(inputShell)

        let inputRow = NSStackView()
        inputRow.orientation = .horizontal
        inputRow.spacing = 8
        inputRow.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 6)
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        inputShell.addSubview(inputRow)
        NSLayoutConstraint.activate([
            inputRow.topAnchor.constraint(equalTo: inputShell.topAnchor),
            inputRow.bottomAnchor.constraint(equalTo: inputShell.bottomAnchor),
            inputRow.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: inputShell.trailingAnchor),
        ])

        chatInput = NSTextField()
        chatInput.placeholderString = "Ask for an edit"
        chatInput.target = self
        chatInput.action = #selector(sendChatPrompt)
        chatInput.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        chatInput.isBordered = false
        chatInput.drawsBackground = false
        inputRow.addArrangedSubview(chatInput)

        chatSendButton = NSButton(image: .sf("paperplane.fill", size: 13, weight: .medium), target: self, action: #selector(sendChatPrompt))
        chatSendButton.bezelStyle = .regularSquare
        chatSendButton.isBordered = false
        chatSendButton.toolTip = "Send to selected agent"
        chatSendButton.keyEquivalent = "\r"
        chatSendButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        chatSendButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        inputRow.addArrangedSubview(chatSendButton)

        return container
    }

    // MARK: - Empty state

    private func makeEmptyState() -> NSView {
        let container = NSView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        emptyStateIcon = NSImageView(image: .sf("doc.text.magnifyingglass", size: 44, weight: .regular))
        emptyStateIcon.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(emptyStateIcon)

        emptyStateTitle = NSTextField(labelWithString: "Drop an HTML file here")
        emptyStateTitle.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(emptyStateTitle)

        emptyStateSub = NSTextField(labelWithString: "or press \u{2318}O to open")
        emptyStateSub.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        stack.addArrangedSubview(emptyStateSub)

        return container
    }

    private func updateEmptyState() {
        emptyStateView?.isHidden = currentFileURL != nil
    }

    // MARK: - Toolbar (UI-03)

    private func makeToolbar() -> NSView {
        let bar = NSView(frame: .zero)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 86, bottom: 3, right: 12)
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            bar.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])

        // Spacer
        let flex = NSView(frame: .zero)
        flex.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(flex)

        // Utility buttons live on the right so they never collide with macOS traffic lights.
        reloadBtn = toolBtn(icon: "arrow.clockwise", tip: "Reload (\u{2318}R)", action: #selector(reloadPage))
        chatToggleButton = toolBtn(icon: "sidebar.right", tip: "Toggle chat", action: #selector(toggleChatPanel))
        browserBtn = toolBtn(icon: "safari", tip: "Open in browser", action: #selector(openBrowser))
        openBtn = toolBtn(icon: "folder", tip: "Open file (\u{2318}O)", action: #selector(openFile))
        stack.addArrangedSubview(reloadBtn)
        stack.addArrangedSubview(chatToggleButton)
        stack.addArrangedSubview(browserBtn)
        stack.addArrangedSubview(openBtn)

        // Dark mode (UI-03: rightmost)
        darkModeButton = HoverButton(image: .sf("sun.max", size: 14, weight: .medium), target: self, action: #selector(toggleDark))
        darkModeButton.bezelStyle = .regularSquare
        darkModeButton.isBordered = false
        darkModeButton.toolTip = "Toggle dark/light (\u{2318}\u{21E7}D)"
        darkModeButton.hoverColor = Palette.hover(dark: true)
        darkModeButton.cornerRadius = 6
        darkModeButton.setContentHuggingPriority(.required, for: .horizontal)
        darkModeButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        darkModeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(darkModeButton)

        return bar
    }

    private func makePaddedSeparator() -> NSView {
        let s = PaddedSeparator(frame: .zero)
        s.boxType = .separator
        s.setContentHuggingPriority(.required, for: .horizontal)
        return s
    }

    private func toolBtn(icon: String, tip: String, action: Selector) -> HoverButton {
        let btn = HoverButton(image: .sf(icon, size: 14, weight: .medium), target: self, action: action)
        btn.title = ""
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.imagePosition = .imageOnly
        btn.imageScaling = .scaleProportionallyDown
        btn.toolTip = tip
        btn.contentTintColor = Palette.textPrimary(dark: true)
        btn.hoverColor = Palette.hover(dark: true)
        btn.cornerRadius = 6
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .vertical)
        btn.wantsLayer = true
        btn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return btn
    }

    // MARK: - Dark Mode

    @objc private func toggleDark() {
        isDarkMode.toggle()
        UserDefaults.standard.set(isDarkMode, forKey: "darkMode")
        updateDarkModeIcon()
    }

    private func updateDarkModeIcon() {
        // BUG-01: keep icon in sync with state
        darkModeButton.image = .sf(isDarkMode ? "sun.max" : "moon", size: 14, weight: .medium)
        darkModeButton.contentTintColor = isDarkMode
            ? NSColor(red: 1, green: 0.812, blue: 0.302, alpha: 1)
            : Palette.textSecondary(dark: false)
    }

    @objc private func toggleChatPanel() {
        isChatCollapsed.toggle()
        if isChatCollapsed {
            clearSelectionForReadingMode()
        }
        rightPanel.isHidden = isChatCollapsed
        chatToggleButton.image = .sf(isChatCollapsed ? "sidebar.right" : "sidebar.right", size: 14, weight: .medium)
        chatToggleButton.contentTintColor = isChatCollapsed ? Palette.textSecondary(dark: isDarkMode) : Palette.accent(dark: isDarkMode)
        splitView.adjustSubviews()
        if !isChatCollapsed {
            view.window?.makeFirstResponder(chatInput)
        }
    }

    private func clearSelectionForReadingMode() {
        selectedElements = []
        selectedElementContext = nil
        selectedElementLabel?.stringValue = "No element selected"
        selectedElementDetail?.stringValue = "Click any visible element in the preview. The selected DOM context will be sent with your next message."
        webView?.evaluateJavaScript("window.__htmlAgentClearSelection && window.__htmlAgentClearSelection();", completionHandler: nil)
    }

    @objc private func toggleAgentProcess() {
        showAgentProcess.toggle()
        processToggleButton.contentTintColor = showAgentProcess ? Palette.accent(dark: isDarkMode) : Palette.textSecondary(dark: isDarkMode)
        processToggleButton.title = showAgentProcess ? "Hide" : "Work"
        processToggleButton.toolTip = showAgentProcess ? "Hide agent working output" : "Show agent working output"
        renderChatTranscript()
    }

    private func applyAppearance() {
        let appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)!
        view.window?.appearance = appearance
        NSApp.appearance = appearance
        splitView?.isDark = isDarkMode

        // BUG-06 / CODE-03: use stored toolbarView
        toolbarView?.layer?.backgroundColor = (isDarkMode
            ? Palette.darkSurface
            : Palette.lightSurfaceRaised).cgColor
        toolbarView?.layer?.borderColor = (isDarkMode
            ? Palette.darkBorder
            : Palette.lightBorder).cgColor
        toolbarView?.layer?.borderWidth = 0
        toolbarView?.layer?.masksToBounds = true

        // UI-04: hover color for light mode
        let hoverBg = Palette.hover(dark: isDarkMode)
        for btn in [reloadBtn, chatToggleButton, browserBtn, openBtn, darkModeButton, pickerButton, processToggleButton].compactMap({ $0 }) {
            btn.hoverColor = hoverBg
            btn.contentTintColor = Palette.textPrimary(dark: isDarkMode)
        }
        agentPopup?.isEnabled = currentFileURL != nil

        logoView?.contentTintColor = Palette.accent(dark: isDarkMode)
        rightPanel?.layer?.backgroundColor = Palette.surface(dark: isDarkMode).cgColor
        chatContainer?.layer?.backgroundColor = Palette.surface(dark: isDarkMode).cgColor
        activeAgentLabel?.textColor = Palette.textSecondary(dark: isDarkMode)
        selectedElementBox?.layer?.backgroundColor = (isDarkMode
            ? NSColor.white.withAlphaComponent(0.035)
            : NSColor.black.withAlphaComponent(0.025)).cgColor
        selectedElementBox?.layer?.borderColor = Palette.border(dark: isDarkMode).withAlphaComponent(0.55).cgColor
        selectedElementLabel?.textColor = Palette.textPrimary(dark: isDarkMode)
        selectedElementDetail?.textColor = Palette.textSecondary(dark: isDarkMode)
        chatScrollView?.backgroundColor = Palette.surface(dark: isDarkMode)
        chatInput?.textColor = Palette.textPrimary(dark: isDarkMode)
        chatInput?.backgroundColor = .clear
        chatInputBox?.layer?.backgroundColor = (isDarkMode
            ? NSColor.white.withAlphaComponent(0.04)
            : NSColor.black.withAlphaComponent(0.035)).cgColor
        chatInputBox?.layer?.borderColor = Palette.border(dark: isDarkMode).withAlphaComponent(0.65).cgColor
        chatSendButton?.contentTintColor = Palette.accent(dark: isDarkMode)
        chatToggleButton?.contentTintColor = isChatCollapsed ? Palette.textSecondary(dark: isDarkMode) : Palette.accent(dark: isDarkMode)
        processToggleButton?.contentTintColor = showAgentProcess ? Palette.accent(dark: isDarkMode) : Palette.textSecondary(dark: isDarkMode)
        renderChatTranscript()

        // Empty state text/icon colors for current appearance
        emptyStateIcon?.contentTintColor = Palette.textSecondary(dark: isDarkMode)
        emptyStateTitle?.textColor = Palette.textPrimary(dark: isDarkMode)
        emptyStateSub?.textColor = Palette.textSecondary(dark: isDarkMode)

        webContainer?.layer?.backgroundColor = (isDarkMode
            ? Palette.darkBackground
            : Palette.lightBackground).cgColor

        terminalView.applyAppearance(dark: isDarkMode)

        // CODE-04: inject color-scheme meta only once, not every call
        let bg = isDarkMode ? "#0A0E17" : "#F4F5F7"
        let fg = isDarkMode ? "#E8ECF4" : "#0F1117"
        webView?.evaluateJavaScript("""
            (function(){
                if (!document.head) return;
                var existing = document.head.querySelector('meta[name="color-scheme"]');
                if (!existing) {
                    var m = document.createElement('meta');
                    m.name = 'color-scheme';
                    m.content = '\(isDarkMode ? "dark" : "light")';
                    document.head.appendChild(m);
                } else {
                    existing.content = '\(isDarkMode ? "dark" : "light")';
                }
                document.documentElement.style.backgroundColor = '\(bg)';
                document.documentElement.style.color = '\(fg)';
            })();
        """, completionHandler: nil)

        updatePickerState()
        splitView.needsDisplay = true
    }

    // MARK: - Button enable state (UX-06)

    private func updateFileButtonsEnabled() {
        let hasFile = currentFileURL != nil
        reloadBtn?.isEnabled = hasFile
        browserBtn?.isEnabled = hasFile
        agentPopup?.isEnabled = hasFile
    }

    // MARK: - Actions

    @objc private func agentPopupChanged() {
        let idx = agentPopup.indexOfSelectedItem - 1
        guard idx >= 0 else { return }
        startAgent(index: idx)
    }

    private func startAgent(index idx: Int) {
        guard currentFileURL != nil else {
            // UX-01: NSPopover-like alert sheet
            presentNoFileAlert()
            return
        }

        guard idx >= 0, idx < agentMeta.count else { return }
        let agent = agentMeta[idx]
        activeAgentIndex = idx
        activeAgentLabel.stringValue = agent.label

        view.window?.makeFirstResponder(chatInput)
    }

    @objc private func sendChatPrompt() {
        let prompt = chatInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentFileURL != nil else {
            appendChatLine("Open an HTML file first.", kind: .error)
            return
        }
        guard !prompt.isEmpty else {
            appendChatLine("Type a change request first.", kind: .error)
            return
        }
        guard activeAgentIndex != nil else {
            appendChatLine("Choose an agent first.", kind: .error)
            return
        }
        guard runningAgentProcess == nil else {
            appendChatLine("Agent is still working. Wait for this run to finish.", kind: .status)
            return
        }
        let payload = agentPrompt(userText: prompt)
        appendChatLine(prompt, kind: .user)
        pulseComposer()
        chatInput.stringValue = ""
        runAgent(prompt: payload)
        view.window?.makeFirstResponder(chatInput)
    }

    private func pulseComposer() {
        guard let layer = chatInputBox?.layer else { return }
        let animation = CABasicAnimation(keyPath: "borderColor")
        animation.fromValue = Palette.accent(dark: isDarkMode).withAlphaComponent(0.9).cgColor
        animation.toValue = Palette.border(dark: isDarkMode).withAlphaComponent(0.65).cgColor
        animation.duration = 0.32
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "composerBorderPulse")
    }

    private func runAgent(prompt: String) {
        guard let idx = activeAgentIndex, idx >= 0, idx < agentMeta.count, let fileURL = currentFileURL else { return }
        let agent = agentMeta[idx]
        let dir = fileURL.deletingLastPathComponent().path
        let command = agentCommand(agentID: agent.id, prompt: prompt, fileURL: fileURL, workingDirectory: dir)

        appendChatLine("\(agent.label): running...", kind: .status)
        chatSendButton.isEnabled = false

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = [
            "\(home)/.opencode/bin",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            currentPath,
            "/usr/bin:/bin:/usr/sbin:/sbin",
        ].joined(separator: ":")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        runningAgentProcess = process
        let previousModified = fileModifiedDate(fileURL)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendChatLine(self?.stripANSI(text).trimmingCharacters(in: .whitespacesAndNewlines) ?? "", kind: .process)
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.runningAgentProcess = nil
                self?.chatSendButton.isEnabled = true
                if proc.terminationStatus == 0 {
                    self?.webView.reload()
                    let changed = self?.fileModifiedDate(fileURL) != previousModified
                    self?.appendChatLine(changed == true ? "Done. Preview reloaded." : "Done, but the file appears unchanged. Open Work to inspect the agent output.", kind: changed == true ? .status : .error)
                } else {
                    self?.appendChatLine("Agent exited with status \(proc.terminationStatus). Open Work to inspect the output.", kind: .error)
                }
            }
        }

        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self, weak process] in
                guard let self = self, let process = process, self.runningAgentProcess === process, process.isRunning else { return }
                self.appendChatLine("\(agent.label): still running...", kind: .status)
            }
        } catch {
            runningAgentProcess = nil
            chatSendButton.isEnabled = true
            appendChatLine("Could not start \(agent.label): \(error.localizedDescription)", kind: .error)
        }
    }

    private func agentCommand(agentID: String, prompt: String, fileURL: URL, workingDirectory: String) -> String {
        let qPrompt = shellQuote(prompt)
        let qFile = shellQuote(fileURL.path)
        let qDir = shellQuote(workingDirectory)
        if let override = ProcessInfo.processInfo.environment["HTML_AGENT_EDITOR_AGENT_COMMAND"], !override.isEmpty {
            return "\(override) \(qPrompt)"
        }
        switch agentID {
        case "opencode":
            return "opencode run \(qPrompt) --dangerously-skip-permissions --dir \(qDir) --file \(qFile)"
        case "claude":
            return "claude --print --add-dir \(qDir) \(qPrompt)"
        case "codex":
            return "codex exec \(qPrompt)"
        case "hermes":
            return "hermes --oneshot \(qPrompt)"
        default:
            return "\(shellQuote(agentID)) \(qPrompt)"
        }
    }

    private func agentPrompt(userText: String) -> String {
        var lines = [
            "Edit the currently open HTML file.",
            "File: \(currentFileURL?.path ?? "unknown")",
        ]
        if let selectedElementContext {
            lines.append("Selected element context:\n\(selectedElementContext)")
            let targetText = selectedElements.count == 1 ? "the selected element" : "all selected elements"
            lines.append("Unless the user clearly asks for a broader change, apply the requested change to \(targetText).")
        } else {
            lines.append("No specific element selected.")
        }
        lines.append("User request: \(userText)")
        lines.append("Apply the edit directly to the HTML/CSS/JS file. Make a visible change that matches the request, preserve unrelated content, then print a concise summary of the file and selector changed.")
        return lines.joined(separator: "\n")
    }

    private func fileModifiedDate(_ url: URL) -> Date? {
        return try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    @objc private func togglePicker() {
        isPickerEnabled.toggle()
        updatePickerState()
    }

    private func updatePickerState() {
        pickerButton?.contentTintColor = isPickerEnabled ? Palette.accent(dark: isDarkMode) : Palette.textSecondary(dark: isDarkMode)
        let enabled = isPickerEnabled ? "true" : "false"
        webView?.evaluateJavaScript("window.__htmlAgentSetPickerEnabled && window.__htmlAgentSetPickerEnabled(\(enabled));", completionHandler: nil)
    }

    private func resetChatIntro() {
        chatMessages = []
        lastAnimatedMessageCount = 0
        renderChatTranscript()
    }

    private func appendChatLine(_ line: String, kind: ChatKind = .status) {
        guard !line.isEmpty else { return }
        chatMessages.append(ChatMessage(kind: kind, text: line))
        renderChatTranscript(animateNewRows: true)
    }

    private func renderChatTranscript(animateNewRows: Bool = false) {
        guard let stack = chatMessageStack else { return }
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        var hiddenProcessCount = 0

        for message in chatMessages {
            let shouldAnimate = animateNewRows && stack.arrangedSubviews.count >= lastAnimatedMessageCount
            if message.kind == .process && !showAgentProcess {
                hiddenProcessCount += 1
                continue
            }
            let view = makeChatMessageView(message)
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if shouldAnimate { animateMessageView(view) }
        }

        if hiddenProcessCount > 0 && !showAgentProcess {
            let message = ChatMessage(kind: .process, text: "\(hiddenProcessCount) work update\(hiddenProcessCount == 1 ? "" : "s") hidden. Use Work to view.")
            let view = makeChatMessageView(message)
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if animateNewRows { animateMessageView(view) }
        }
        lastAnimatedMessageCount = stack.arrangedSubviews.count

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let last = self.chatMessageStack.arrangedSubviews.last else { return }
            last.scrollToVisible(last.bounds)
        }
    }

    private func animateMessageView(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.opacity = 0
        view.layer?.transform = CATransform3DMakeTranslation(0, 8, 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
            view.layer?.transform = CATransform3DIdentity
        }
    }

    private func makeChatMessageView(_ message: ChatMessage) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false

        if message.kind == .status || message.kind == .process {
            let text = NSTextField(wrappingLabelWithString: message.text)
            text.translatesAutoresizingMaskIntoConstraints = false
            text.font = message.kind == .process
                ? NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                : NSFont.systemFont(ofSize: 11, weight: .regular)
            text.textColor = Palette.textSecondary(dark: isDarkMode)
            text.maximumNumberOfLines = 0
            text.lineBreakMode = .byWordWrapping
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(text)
            text.leadingAnchor.constraint(equalTo: row.leadingAnchor).isActive = true
            text.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor).isActive = true
            return row
        }

        let bubble = NSView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = message.kind == .user ? 13 : 10
        bubble.layer?.borderWidth = message.kind == .process ? 0 : 1

        let content = NSStackView()
        content.orientation = .vertical
        content.spacing = 4
        content.edgeInsets = NSEdgeInsets(top: 11, left: 14, bottom: 12, right: 14)
        content.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: bubble.topAnchor),
            content.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
        ])

        let role = NSTextField(labelWithString: chatRoleTitle(for: message.kind))
        role.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        role.textColor = chatRoleColor(for: message.kind)
        role.lineBreakMode = .byTruncatingTail
        content.addArrangedSubview(role)

        let body = NSTextField(wrappingLabelWithString: message.text)
        body.translatesAutoresizingMaskIntoConstraints = false
        body.font = NSFont.systemFont(ofSize: 12, weight: message.kind == .user ? .medium : .regular)
        body.textColor = message.kind == .process ? Palette.textSecondary(dark: isDarkMode) : Palette.textPrimary(dark: isDarkMode)
        body.maximumNumberOfLines = 0
        body.lineBreakMode = .byWordWrapping
        body.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.addArrangedSubview(body)

        let leftFlex = NSView(frame: .zero)
        let rightFlex = NSView(frame: .zero)
        leftFlex.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rightFlex.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if message.kind == .user {
            row.addArrangedSubview(leftFlex)
            row.addArrangedSubview(bubble)
        } else {
            row.addArrangedSubview(bubble)
            row.addArrangedSubview(rightFlex)
        }

        let maxWidth = bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.88)
        maxWidth.priority = .defaultHigh
        maxWidth.isActive = true
        body.widthAnchor.constraint(lessThanOrEqualTo: bubble.widthAnchor, constant: -28).isActive = true

        switch message.kind {
        case .user:
            bubble.layer?.backgroundColor = Palette.accent(dark: isDarkMode).withAlphaComponent(isDarkMode ? 0.20 : 0.12).cgColor
            bubble.layer?.borderColor = Palette.accent(dark: isDarkMode).withAlphaComponent(0.28).cgColor
        case .process:
            bubble.layer?.backgroundColor = NSColor.clear.cgColor
        case .error:
            bubble.layer?.backgroundColor = Palette.destructive.withAlphaComponent(0.08).cgColor
            bubble.layer?.borderColor = Palette.destructive.withAlphaComponent(0.35).cgColor
        default:
            bubble.layer?.backgroundColor = (isDarkMode
                ? NSColor.white.withAlphaComponent(0.04)
                : NSColor.black.withAlphaComponent(0.025)).cgColor
            bubble.layer?.borderColor = Palette.border(dark: isDarkMode).withAlphaComponent(0.55).cgColor
        }

        return row
    }

    private func chatRoleTitle(for kind: ChatKind) -> String {
        switch kind {
        case .user: return "You"
        case .agent: return "Agent"
        case .selection: return "Selection"
        case .error: return "Needs attention"
        case .process: return "Process"
        case .status: return "Status"
        }
    }

    private func chatRoleColor(for kind: ChatKind) -> NSColor {
        switch kind {
        case .user, .selection:
            return Palette.accent(dark: isDarkMode)
        case .error:
            return Palette.destructive
        case .agent:
            return Palette.textPrimary(dark: isDarkMode)
        case .process, .status:
            return Palette.textSecondary(dark: isDarkMode)
        }
    }

    private func stripANSI(_ string: String) -> String {
        var result = string
        let pattern = "\u{001B}\\[[0-9;:?]*[ -/]*[@-~]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        let oscPattern = "\u{001B}\\].*?(\u{0007}|\u{001B}\\\\)"
        if let regex = try? NSRegularExpression(pattern: oscPattern, options: [.dotMatchesLineSeparators]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        return result.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    @objc private func reloadPage() {
        guard currentFileURL != nil else {
            // UX-05: pulse animation
            pulseButton(reloadBtn)
            return
        }
        webView.reload()
    }

    @objc private func openBrowser() {
        if let url = currentFileURL { NSWorkspace.shared.open(url) }
    }

    @objc private func clearChat() {
        chatMessages = []
        appendChatLine("Chat cleared.", kind: .status)
    }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.allowsOtherFileTypes = true
        panel.begin { [weak self] resp in
            if resp == .OK, let url = panel.url { self?.loadFile(url: url) }
        }
    }

    private func pulseButton(_ btn: HoverButton?) {
        guard let btn = btn else { return }
        let original = btn.hoverColor
        btn.hoverColor = Palette.accent(dark: isDarkMode).withAlphaComponent(0.4)
        btn.layer?.backgroundColor = btn.hoverColor.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            btn.layer?.backgroundColor = .clear
            btn.hoverColor = original
        }
    }

    private func presentNoFileAlert() {
        // UX-01: brief alert sheet instead of burying error in terminal
        let alert = NSAlert()
        alert.messageText = "No file open"
        alert.informativeText = "Use \u{2318}O to open an HTML file."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open File")
        alert.addButton(withTitle: "Cancel")
        if let window = view.window {
            alert.beginSheetModal(for: window) { [weak self] resp in
                if resp == .alertFirstButtonReturn { self?.openFile() }
            }
        } else {
            alert.runModal()
        }
    }

    // MARK: - File Loading

    func loadFile(url: URL) {
        guard webView != nil else { return }
        currentFileURL = url
        updateEmptyState()
        updateFileButtonsEnabled()
        startWatching(url: url)

        _ = url.startAccessingSecurityScopedResource()
        webView.loadFileURL(url, allowingReadAccessTo: readAccessRoot(for: url))

        // UI-10: window title + subtitle (macOS 11+)
        if let window = view.window {
            window.title = "HTML Agent Editor"
            window.subtitle = url.lastPathComponent
        }
        resetChatIntro()
        selectedElementContext = nil
        selectedElements = []
        selectedElementLabel.stringValue = "No element selected"
        selectedElementDetail.stringValue = "Click any visible element in the preview. The selected DOM context will be sent with your next message."
        if activeAgentIndex == nil, let defaultIndex = agentMeta.firstIndex(where: { $0.id == "opencode" }) {
            activeAgentIndex = defaultIndex
            agentPopup?.selectItem(at: defaultIndex + 1)
            activeAgentLabel.stringValue = agentMeta[defaultIndex].label
        }
        view.window?.makeFirstResponder(chatInput)
    }

    private func readAccessRoot(for url: URL) -> URL {
        let fm = FileManager.default
        let fileDir = url.deletingLastPathComponent()
        var candidate = fileDir
        for _ in 0..<5 {
            if fm.fileExists(atPath: candidate.appendingPathComponent("support.js").path) ||
                fm.fileExists(atPath: candidate.appendingPathComponent("package.json").path) ||
                fm.fileExists(atPath: candidate.appendingPathComponent(".git").path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }
            candidate = parent
        }
        let parent = fileDir.deletingLastPathComponent()
        return parent.path == fileDir.path ? fileDir : parent
    }

    private func shellQuote(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - FEAT-02: File watcher

    private func startWatching(url: URL) {
        stopWatching()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileWatcherFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.fileWatcherDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.currentFileURL != nil else { return }
                self.webView.reload()
            }
            self.fileWatcherDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileWatcherFD >= 0 {
                close(self.fileWatcherFD)
                self.fileWatcherFD = -1
            }
        }
        source.resume()
        fileWatcherSource = source
    }

    private func stopWatching() {
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
    }

    // MARK: - WKNavigationDelegate

    private func elementPickerScript() -> String {
        return """
        (function(){
          if (window.__htmlAgentPickerInstalled) return;
          window.__htmlAgentPickerInstalled = true;
          window.__htmlAgentPickerEnabled = true;
          var selected = [];
          var hover = null;
          var style = document.createElement('style');
          style.textContent = [
            '.__html_agent_hover{outline:1.5px solid rgba(34,197,94,.75)!important;outline-offset:2px!important;cursor:crosshair!important}',
            '.__html_agent_selected{outline:2px solid rgba(34,197,94,1)!important;outline-offset:3px!important;box-shadow:0 0 0 5px rgba(34,197,94,.14)!important}'
          ].join('\\n');
          document.documentElement.appendChild(style);
          window.__htmlAgentSetPickerEnabled = function(value){
            window.__htmlAgentPickerEnabled = !!value;
            if (!value && hover) { hover.classList.remove('__html_agent_hover'); hover = null; }
          };
          function isSelected(el){
            return selected.indexOf(el) !== -1;
          }
          function clearSelected(){
            selected.forEach(function(el){ el.classList.remove('__html_agent_selected'); });
            selected = [];
          }
          function postSelection(){
            window.webkit.messageHandlers.elementPicked.postMessage(selected.map(summarize));
          }
          window.__htmlAgentClearSelection = function(){
            if (hover) { hover.classList.remove('__html_agent_hover'); hover = null; }
            clearSelected();
          };
          function cssPath(el){
            if (!el || el.nodeType !== 1) return '';
            var parts = [];
            while (el && el.nodeType === 1 && el !== document.documentElement) {
              var part = el.tagName.toLowerCase();
              if (el.id) {
                part += '#' + CSS.escape(el.id);
                parts.unshift(part);
                break;
              }
              var cls = Array.prototype.slice.call(el.classList || []).filter(function(c){ return c.indexOf('__html_agent_') !== 0; }).slice(0, 3);
              if (cls.length) part += '.' + cls.map(function(c){ return CSS.escape(c); }).join('.');
              var sib = el, nth = 1;
              while ((sib = sib.previousElementSibling)) {
                if (sib.tagName === el.tagName) nth++;
              }
              part += ':nth-of-type(' + nth + ')';
              parts.unshift(part);
              el = el.parentElement;
            }
            return parts.join(' > ');
          }
          function summarize(el){
            var rect = el.getBoundingClientRect();
            return {
              tag: el.tagName.toLowerCase(),
              id: el.id || '',
              className: Array.prototype.slice.call(el.classList || []).filter(function(c){ return c.indexOf('__html_agent_') !== 0; }).join(' '),
              text: (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 500),
              selector: cssPath(el),
              outerHTML: el.outerHTML.slice(0, 1200),
              rect: { x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height) }
            };
          }
          document.addEventListener('mouseover', function(e){
            if (!window.__htmlAgentPickerEnabled) return;
            if (hover && hover !== e.target) hover.classList.remove('__html_agent_hover');
            hover = e.target;
            if (hover && !isSelected(hover)) hover.classList.add('__html_agent_hover');
          }, true);
          document.addEventListener('mouseout', function(e){
            if (hover && !isSelected(hover)) hover.classList.remove('__html_agent_hover');
          }, true);
          document.addEventListener('click', function(e){
            if (!window.__htmlAgentPickerEnabled) return;
            var el = e.target;
            if (!el || el === document.documentElement || el === document.body) return;
            e.preventDefault();
            e.stopPropagation();
            if (e.shiftKey) {
              var idx = selected.indexOf(el);
              if (idx >= 0) {
                selected.splice(idx, 1);
                el.classList.remove('__html_agent_selected');
              } else {
                selected.push(el);
                el.classList.add('__html_agent_selected');
              }
            } else {
              clearSelected();
              selected = [el];
              el.classList.add('__html_agent_selected');
            }
            el.classList.remove('__html_agent_hover');
            postSelection();
          }, true);
        })();
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "elementPicked" else { return }
        let dicts: [[String: Any]]
        if let items = message.body as? [[String: Any]] {
            dicts = items
        } else if let dict = message.body as? [String: Any] {
            dicts = [dict]
        } else {
            return
        }

        selectedElements = dicts.map { dict in
            let tag = dict["tag"] as? String ?? "element"
            let id = dict["id"] as? String ?? ""
            let className = dict["className"] as? String ?? ""
            let selector = dict["selector"] as? String ?? ""
            let text = dict["text"] as? String ?? ""
            let html = dict["outerHTML"] as? String ?? ""

            var label = "<\(tag)>"
            if !id.isEmpty { label += "#\(id)" }
            if !className.isEmpty { label += "." + className.split(separator: " ").prefix(2).joined(separator: ".") }
            return SelectedElement(label: label, selector: selector, text: text, html: html)
        }

        updateSelectedElementSummary()
    }

    private func updateSelectedElementSummary() {
        guard !selectedElements.isEmpty else {
            selectedElementContext = nil
            selectedElementLabel.stringValue = "No element selected"
            selectedElementDetail.stringValue = "Click any visible element in the preview. The selected DOM context will be sent with your next message."
            return
        }

        if selectedElements.count == 1, let selected = selectedElements.first {
            selectedElementLabel.stringValue = selected.label
            selectedElementDetail.stringValue = selected.selector.isEmpty ? selected.text : selected.selector
        } else {
            selectedElementLabel.stringValue = "\(selectedElements.count) elements selected"
            selectedElementDetail.stringValue = selectedElements
                .prefix(3)
                .map { $0.selector.isEmpty ? $0.label : $0.selector }
                .joined(separator: "\n")
        }

        selectedElementContext = selectedElements.enumerated().map { index, selected in
            """
            Selected element \(index + 1):
            selector: \(selected.selector)
            label: \(selected.label)
            visible text: \(selected.text)
            outerHTML:
            \(selected.html)
            """
        }.joined(separator: "\n\n")
    }

    func webView(_ wv: WKWebView, didStartProvisionalNavigation nav: WKNavigation!) {
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
    }

    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        progressIndicator.isHidden = true
        progressIndicator.stopAnimation(nil)
        // BUG-08: only echo on main document, not subframes
        if wv.url == currentFileURL || wv.url == currentFileURL?.deletingLastPathComponent() {
            currentFileURL?.stopAccessingSecurityScopedResource()
        }
        applyAppearance()
        updatePickerState()
    }

    func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError err: Error) {
        progressIndicator.isHidden = true
        // CODE-05: filter cancelled navigations
        let nsErr = err as NSError
        if nsErr.code == NSURLErrorCancelled { return }
        currentFileURL?.stopAccessingSecurityScopedResource()
        appendChatLine("Preview error: \(nsErr.localizedDescription)", kind: .error)
    }

    func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError err: Error) {
        progressIndicator.isHidden = true
        let nsErr = err as NSError
        if nsErr.code == NSURLErrorCancelled { return }
        appendChatLine("Preview error: \(nsErr.localizedDescription)", kind: .error)
    }

    func webView(_ wv: WKWebView, createWebViewWith config: WKWebViewConfiguration, for nav: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = nav.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    // MARK: - Menu bar actions (FEAT-05)

    @objc func menuOpenFile() { openFile() }
    @objc func menuReload() { reloadPage() }
    @objc func menuOpenBrowser() { openBrowser() }
    @objc func menuToggleDark() { toggleDark() }
    @objc func menuClearTerminal() { clearChat() }
    @objc func menuIncreaseFont() { terminalView.increaseFont() }
    @objc func menuDecreaseFont() { terminalView.decreaseFont() }

    @objc func menuAgent(_ sender: NSMenuItem) {
        let idx = sender.tag
        if idx >= 0, idx < agentMeta.count {
            agentPopup?.selectItem(at: idx + 1)
            startAgent(index: idx)
        }
    }

    func runSelfTestSend(prompt: String) {
        if activeAgentIndex == nil, let idx = agentMeta.firstIndex(where: { $0.id == "opencode" }) {
            activeAgentIndex = idx
            agentPopup?.selectItem(at: idx + 1)
            activeAgentLabel.stringValue = agentMeta[idx].label
        }
        webView.evaluateJavaScript("""
            (function(){
                var el = document.querySelector('h1') || document.body.firstElementChild;
                if (!el) return false;
                el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
                return true;
            })();
        """) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.chatInput.stringValue = prompt
                self?.sendChatPrompt()
            }
        }
    }

    func selfTestTranscript() -> String {
        return chatMessages.map { "\($0.kind): \($0.text)" }.joined(separator: "\n")
    }

    // MARK: - FEAT-01: Drag & Drop helpers (called by DragContainerView)

    func handleDragAcceptance(_ accepted: Bool) {
        webContainer?.layer?.backgroundColor = accepted
            ? Palette.accent(dark: isDarkMode).withAlphaComponent(0.10).cgColor
            : (isDarkMode ? Palette.darkBackground.cgColor : Palette.lightBackground.cgColor)
    }

    func handleDroppedFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "html" || ext == "htm" else { return false }
        loadFile(url: url)
        return true
    }

    func isAcceptableDropURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "html" || ext == "htm"
    }

    // MARK: - NSSplitViewDelegate (UX-04: 12px hit area for divider)

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return subview == rightPanel
    }

    func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        let expand: CGFloat = 5
        if splitView.isVertical {
            return NSRect(
                x: drawnRect.minX - expand,
                y: drawnRect.minY,
                width: drawnRect.width + expand * 2,
                height: drawnRect.height
            )
        } else {
            return NSRect(
                x: drawnRect.minX,
                y: drawnRect.minY - expand,
                width: drawnRect.width,
                height: drawnRect.height + expand * 2
            )
        }
    }
}

// MARK: - DragContainerView (FEAT-01)

final class DragContainerView: NSView {
    weak var dragHandler: ViewController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    private func firstURL(from info: NSDraggingInfo) -> URL? {
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = firstURL(from: sender), let h = dragHandler, h.isAcceptableDropURL(url) else {
            return []
        }
        h.handleDragAcceptance(true)
        return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = firstURL(from: sender), let h = dragHandler, h.isAcceptableDropURL(url) else {
            return false
        }
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = firstURL(from: sender), let h = dragHandler else { return false }
        return h.handleDroppedFile(url)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dragHandler?.handleDragAcceptance(false)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragHandler?.handleDragAcceptance(false)
    }
}
