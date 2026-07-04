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

final class PromptTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onTextChange: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn && !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?()
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
    private var chatInput: PromptTextView!
    private var chatInputPlaceholder: NSTextField!
    private var chatInputHeightConstraint: NSLayoutConstraint!
    private var chatInputBox: NSView!
    private var chatSendButton: NSButton!
    private var chatStopButton: NSButton!
    private var modeSegment: NSSegmentedControl!
    private var editContextCheckbox: NSButton!
    private var newSessionButton: HoverButton!
    private var rewindButton: HoverButton!
    private var attachButton: HoverButton!
    private var attachURLButton: HoverButton!
    private var activeAgentLabel: NSTextField!
    private var agentStatusDot: NSView!
    private var agentPopup: NSPopUpButton!
    private var modelPopup: NSPopUpButton!
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
    private var installingAgentID: String?
    private var installingAgentProcess: Process?
    private var didCancelRunningAgent = false
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
    private var updateBtn: HoverButton!
    private var latestUpdate: UpdateInfo?
    private var isCheckingForUpdate = false
    private var didPresentUpdateIndicator = false

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
    private var sessionMessages: [SessionMessage] = []
    private var claudeSessionID: String?
    private var sessionActiveAgentID: String?
    private var attachedContexts: [AttachmentContext] = []
    private var editUndoStack: [EditSnapshot] = []
    private var lastAnimatedMessageCount = 0
    private var agentMode: AgentMode = UserDefaults.standard.string(forKey: "HTMLAgentEditor.AgentMode") == "chat" ? .chat : .edit
    private var includeEditContext = UserDefaults.standard.object(forKey: "HTMLAgentEditor.IncludeEditContext") as? Bool ?? true

    private enum ChatKind {
        case user
        case agent
        case status
        case selection
        case error
        case process
    }

    private enum AgentMode {
        case edit
        case chat
    }

    private struct ChatMessage {
        let kind: ChatKind
        let text: String
    }

    private struct SessionMessage {
        let role: String
        let text: String
        let mode: AgentMode
    }

    private struct AttachmentContext {
        let label: String
        let value: String
    }

    private struct EditSnapshot {
        let fileURL: URL
        let data: Data
    }

    private struct SelectedElement {
        let label: String
        let selector: String
        let text: String
        let html: String
    }

    private struct AgentModel {
        let label: String
        let id: String
    }

    private struct AgentDefinition {
        let id: String
        let label: String
        let icon: String
        let color: NSColor
        let loginCommand: String
        let models: [AgentModel]
    }

    private struct AgentIssue {
        let title: String
        let message: String
        let actionCommand: String?
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct UpdateInfo {
        let version: String
        let pageURL: URL
        let assetURL: URL?
        let assetName: String?
    }

    private let agentMeta: [AgentDefinition] = [
        AgentDefinition(
            id: "claude",
            label: "Claude",
            icon: "brain.head.profile",
            color: NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1),
            loginCommand: "claude",
            models: [
                AgentModel(label: "Default", id: ""),
                AgentModel(label: "Fable", id: "fable"),
                AgentModel(label: "Opus", id: "opus"),
                AgentModel(label: "Sonnet", id: "sonnet"),
                AgentModel(label: "Haiku", id: "haiku"),
            ]
        ),
        AgentDefinition(
            id: "codex",
            label: "Codex",
            icon: "terminal",
            color: NSColor(red: 1, green: 0.549, blue: 0.259, alpha: 1),
            loginCommand: "codex login",
            models: [
                AgentModel(label: "Default", id: ""),
                AgentModel(label: "GPT-5.5", id: "gpt-5.5"),
                AgentModel(label: "GPT-5.5 Pro", id: "gpt-5.5-pro"),
                AgentModel(label: "GPT-5.4", id: "gpt-5.4"),
                AgentModel(label: "GPT-5.4 Pro", id: "gpt-5.4-pro"),
                AgentModel(label: "GPT-5.4 Mini", id: "gpt-5.4-mini"),
                AgentModel(label: "GPT-5.4 Nano", id: "gpt-5.4-nano"),
                AgentModel(label: "GPT-5.3 Codex", id: "gpt-5.3-codex"),
                AgentModel(label: "GPT-5.2 Codex", id: "gpt-5.2-codex"),
                AgentModel(label: "GPT-5 Mini", id: "gpt-5-mini"),
            ]
        ),
        AgentDefinition(
            id: "opencode",
            label: "OpenCode",
            icon: "chevron.left.forwardslash.chevron.right",
            color: NSColor(red: 0.608, green: 0.494, blue: 0.871, alpha: 1),
            loginCommand: "opencode auth",
            models: [
                AgentModel(label: "Default", id: ""),
                AgentModel(label: "opencode/big-pickle", id: "opencode/big-pickle"),
                AgentModel(label: "opencode-go/kimi-k2.7-code", id: "opencode-go/kimi-k2.7-code"),
                AgentModel(label: "opencode-go/minimax-m3", id: "opencode-go/minimax-m3"),
                AgentModel(label: "deepseek/deepseek-v4-pro", id: "deepseek/deepseek-v4-pro"),
            ]
        ),
        AgentDefinition(
            id: "agy",
            label: "Antigravity",
            icon: "paperplane.circle",
            color: NSColor(red: 0.259, green: 0.522, blue: 0.957, alpha: 1),
            loginCommand: "agy",
            models: [
                AgentModel(label: "Default", id: ""),
            ]
        ),
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
        checkForUpdates(manual: false)

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
        let previewWebView = DragWebView(frame: container.bounds, configuration: config)
        previewWebView.dragHandler = self
        webView = previewWebView
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
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
    }

    private func makeRightPanel() -> NSView {
        let panel = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 756))
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.wantsLayer = true
        panel.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        panel.widthAnchor.constraint(lessThanOrEqualToConstant: 760).isActive = true

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
        let container = DragContainerView(frame: NSRect(x: 0, y: 0, width: 360, height: 756))
        container.dragHandler = self
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

        agentStatusDot = NSView(frame: .zero)
        agentStatusDot.translatesAutoresizingMaskIntoConstraints = false
        agentStatusDot.wantsLayer = true
        agentStatusDot.layer?.cornerRadius = 4
        agentStatusDot.toolTip = "No agent selected"
        header.addArrangedSubview(agentStatusDot)
        agentStatusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        agentStatusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        processToggleButton = HoverButton(image: .sf("brain", size: 12, weight: .medium), target: self, action: #selector(toggleAgentProcess))
        processToggleButton.title = "Think"
        processToggleButton.bezelStyle = .regularSquare
        processToggleButton.isBordered = false
        processToggleButton.imagePosition = .imageLeading
        processToggleButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        processToggleButton.toolTip = "Show visible agent thinking and output"
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
        agentPopup.widthAnchor.constraint(equalToConstant: 116).isActive = true
        agentPopup.heightAnchor.constraint(equalToConstant: 28).isActive = true

        modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPopup.translatesAutoresizingMaskIntoConstraints = false
        modelPopup.bezelStyle = .inline
        modelPopup.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        modelPopup.addItem(withTitle: "Choose an agent")
        modelPopup.isEnabled = false
        modelPopup.toolTip = "Model"
        modelPopup.target = self
        modelPopup.action = #selector(modelPopupChanged)
        header.addArrangedSubview(modelPopup)
        header.addArrangedSubview(processToggleButton)
        modelPopup.widthAnchor.constraint(equalToConstant: 132).isActive = true
        modelPopup.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let targetBox = NSView()
        targetBox.translatesAutoresizingMaskIntoConstraints = false
        targetBox.wantsLayer = true
        targetBox.layer?.cornerRadius = 12
        targetBox.layer?.borderWidth = 1
        selectedElementBox = targetBox
        stack.addArrangedSubview(targetBox)

        let targetStack = NSStackView()
        targetStack.orientation = .vertical
        targetStack.alignment = .width
        targetStack.spacing = 7
        targetStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        targetStack.translatesAutoresizingMaskIntoConstraints = false
        targetBox.addSubview(targetStack)
        NSLayoutConstraint.activate([
            targetStack.topAnchor.constraint(equalTo: targetBox.topAnchor, constant: 18),
            targetStack.bottomAnchor.constraint(equalTo: targetBox.bottomAnchor, constant: -18),
            targetStack.leadingAnchor.constraint(equalTo: targetBox.leadingAnchor, constant: 22),
            targetStack.trailingAnchor.constraint(equalTo: targetBox.trailingAnchor, constant: -22),
        ])

        let targetHeader = NSStackView()
        targetHeader.orientation = .horizontal
        targetHeader.alignment = .centerY
        targetHeader.spacing = 6
        targetStack.addArrangedSubview(targetHeader)

        selectedElementLabel = NSTextField(labelWithString: "No element selected")
        selectedElementLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        selectedElementLabel.lineBreakMode = .byTruncatingTail
        selectedElementLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        selectedElementDetail.lineBreakMode = .byWordWrapping
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

        let controlRow = NSStackView()
        controlRow.orientation = .horizontal
        controlRow.alignment = .centerY
        controlRow.spacing = 8
        stack.addArrangedSubview(controlRow)

        modeSegment = NSSegmentedControl(labels: ["Edit", "Chat"], trackingMode: .selectOne, target: self, action: #selector(modeSegmentChanged))
        modeSegment.segmentStyle = .rounded
        modeSegment.selectedSegment = agentMode == .chat ? 1 : 0
        modeSegment.toolTip = "Choose whether the agent edits or only answers questions"
        controlRow.addArrangedSubview(modeSegment)

        editContextCheckbox = NSButton(checkboxWithTitle: "Use Context", target: self, action: #selector(editContextCheckboxChanged))
        editContextCheckbox.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        editContextCheckbox.state = includeEditContext ? .on : .off
        editContextCheckbox.toolTip = "Include prior chat, edit summaries, and attachments in edit mode"
        controlRow.addArrangedSubview(editContextCheckbox)

        let controlFlex = NSView(frame: .zero)
        controlFlex.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controlRow.addArrangedSubview(controlFlex)

        rewindButton = HoverButton(image: .sf("arrow.uturn.backward", size: 12, weight: .medium), target: self, action: #selector(rewindLastEdit))
        rewindButton.title = ""
        rewindButton.bezelStyle = .regularSquare
        rewindButton.isBordered = false
        rewindButton.imagePosition = .imageOnly
        rewindButton.toolTip = "Rewind the last edit"
        rewindButton.cornerRadius = 6
        rewindButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        rewindButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        controlRow.addArrangedSubview(rewindButton)

        attachButton = HoverButton(image: .sf("paperclip", size: 12, weight: .medium), target: self, action: #selector(attachFiles))
        attachButton.title = ""
        attachButton.bezelStyle = .regularSquare
        attachButton.isBordered = false
        attachButton.imagePosition = .imageOnly
        attachButton.toolTip = "Attach files or images as context"
        attachButton.cornerRadius = 6
        attachButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        attachButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        controlRow.addArrangedSubview(attachButton)

        attachURLButton = HoverButton(image: .sf("link", size: 12, weight: .medium), target: self, action: #selector(attachURL))
        attachURLButton.title = ""
        attachURLButton.bezelStyle = .regularSquare
        attachURLButton.isBordered = false
        attachURLButton.imagePosition = .imageOnly
        attachURLButton.toolTip = "Attach a URL as context"
        attachURLButton.cornerRadius = 6
        attachURLButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        attachURLButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        controlRow.addArrangedSubview(attachURLButton)

        newSessionButton = HoverButton(image: .sf("plus.message", size: 12, weight: .medium), target: self, action: #selector(startNewSession))
        newSessionButton.title = ""
        newSessionButton.bezelStyle = .regularSquare
        newSessionButton.isBordered = false
        newSessionButton.imagePosition = .imageOnly
        newSessionButton.toolTip = "Start a new chat session"
        newSessionButton.cornerRadius = 6
        newSessionButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        newSessionButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        controlRow.addArrangedSubview(newSessionButton)
        updateModeControls()
        updateRewindButton()

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

        let inputScroll = NSScrollView()
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.borderType = .noBorder
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.drawsBackground = false
        inputScroll.backgroundColor = .clear
        inputRow.addArrangedSubview(inputScroll)

        chatInput = PromptTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        chatInput.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        chatInput.isRichText = false
        chatInput.isVerticallyResizable = true
        chatInput.isHorizontallyResizable = false
        chatInput.drawsBackground = false
        chatInput.textContainerInset = NSSize(width: 0, height: 6)
        chatInput.textContainer?.widthTracksTextView = true
        chatInput.textContainer?.containerSize = NSSize(width: inputScroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        chatInput.onSubmit = { [weak self] in self?.sendChatPrompt() }
        chatInput.onTextChange = { [weak self] in self?.updatePromptInputHeight() }
        inputScroll.documentView = chatInput
        chatInputHeightConstraint = inputScroll.heightAnchor.constraint(equalToConstant: 30)
        chatInputHeightConstraint.isActive = true

        chatInputPlaceholder = NSTextField(labelWithString: "Ask for an edit")
        chatInputPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        chatInputPlaceholder.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        chatInputPlaceholder.isHidden = false
        inputShell.addSubview(chatInputPlaceholder)
        NSLayoutConstraint.activate([
            chatInputPlaceholder.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor, constant: 10),
            chatInputPlaceholder.topAnchor.constraint(equalTo: inputShell.topAnchor, constant: 12),
        ])

        chatSendButton = NSButton(image: .sf("paperplane.fill", size: 13, weight: .medium), target: self, action: #selector(sendChatPrompt))
        chatSendButton.bezelStyle = .regularSquare
        chatSendButton.isBordered = false
        chatSendButton.toolTip = "Send to selected agent"
        chatSendButton.keyEquivalent = "\r"
        chatSendButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        chatSendButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        inputRow.addArrangedSubview(chatSendButton)

        chatStopButton = NSButton(image: .sf("stop.fill", size: 12, weight: .medium), target: self, action: #selector(stopRunningAgent))
        chatStopButton.bezelStyle = .regularSquare
        chatStopButton.isBordered = false
        chatStopButton.toolTip = "Stop current agent run"
        chatStopButton.isHidden = true
        chatStopButton.isEnabled = false
        chatStopButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        chatStopButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        inputRow.addArrangedSubview(chatStopButton)

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
        updateBtn = toolBtn(icon: "arrow.down.circle", tip: "Check for updates", action: #selector(updateButtonClicked))
        stack.addArrangedSubview(reloadBtn)
        stack.addArrangedSubview(chatToggleButton)
        stack.addArrangedSubview(browserBtn)
        stack.addArrangedSubview(openBtn)
        stack.addArrangedSubview(updateBtn)

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
            isPickerEnabled = false
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
        updatePickerState()
    }

    @objc private func toggleAgentProcess() {
        showAgentProcess.toggle()
        processToggleButton.contentTintColor = showAgentProcess ? Palette.accent(dark: isDarkMode) : Palette.textSecondary(dark: isDarkMode)
        processToggleButton.title = showAgentProcess ? "Hide" : "Think"
        processToggleButton.toolTip = showAgentProcess ? "Hide visible agent thinking and output" : "Show visible agent thinking and output"
        renderChatTranscript()
    }

    @objc private func modeSegmentChanged() {
        agentMode = modeSegment.selectedSegment == 1 ? .chat : .edit
        UserDefaults.standard.set(agentMode == .chat ? "chat" : "edit", forKey: "HTMLAgentEditor.AgentMode")
        updateModeControls()
        view.window?.makeFirstResponder(chatInput)
    }

    private func updateModeControls() {
        guard chatInput != nil else { return }
        modeSegment?.selectedSegment = agentMode == .chat ? 1 : 0
        chatInputPlaceholder?.stringValue = agentMode == .chat ? "Ask about the selected element" : "Ask for an edit"
        chatInputPlaceholder?.isHidden = !(chatInput?.string.isEmpty ?? true)
        editContextCheckbox?.isEnabled = agentMode == .edit && runningAgentProcess == nil
        editContextCheckbox?.state = includeEditContext ? .on : .off
    }

    private func updatePromptInputHeight() {
        guard let chatInput = chatInput, let heightConstraint = chatInputHeightConstraint else { return }
        chatInputPlaceholder?.isHidden = !chatInput.string.isEmpty
        let fittingWidth = max(chatInput.enclosingScrollView?.contentSize.width ?? chatInput.bounds.width, 120)
        chatInput.textContainer?.containerSize = NSSize(width: fittingWidth, height: CGFloat.greatestFiniteMagnitude)
        chatInput.layoutManager?.ensureLayout(for: chatInput.textContainer!)
        let usedRect = chatInput.layoutManager?.usedRect(for: chatInput.textContainer!) ?? .zero
        let desiredHeight = min(max(30, ceil(usedRect.height + chatInput.textContainerInset.height * 2 + 2)), 150)
        heightConstraint.constant = desiredHeight
        chatInput.needsLayout = true
    }

    @objc private func editContextCheckboxChanged() {
        includeEditContext = editContextCheckbox.state == .on
        UserDefaults.standard.set(includeEditContext, forKey: "HTMLAgentEditor.IncludeEditContext")
        appendChatLine(includeEditContext ? "Edit mode will include prior context." : "Edit mode will ignore prior context.", kind: .status)
    }

    @objc private func startNewSession() {
        chatMessages = []
        sessionMessages = []
        claudeSessionID = nil
        sessionActiveAgentID = nil
        attachedContexts = []
        appendChatLine("New session started.", kind: .status)
        applyAppearance()
    }

    @objc private func rewindLastEdit() {
        guard let snapshot = editUndoStack.popLast() else {
            appendChatLine("No edit to rewind yet.", kind: .status)
            return
        }
        do {
            try snapshot.data.write(to: snapshot.fileURL, options: .atomic)
            updateRewindButton()
            if snapshot.fileURL == currentFileURL {
                webView.reload()
            }
            let remaining = editUndoStack.count
            let tail = remaining == 0 ? "" : " \(remaining) earlier edit\(remaining == 1 ? "" : "s") left."
            appendChatLine("Rewound the last edit. Preview reloaded.\(tail)", kind: .status)
        } catch {
            editUndoStack.append(snapshot)
            appendChatLine("Could not rewind last edit: \(error.localizedDescription)", kind: .error)
        }
    }

    private func updateRewindButton() {
        guard let rewindButton = rewindButton else { return }
        let hasUndo = !editUndoStack.isEmpty
        rewindButton.isEnabled = hasUndo
        rewindButton.contentTintColor = hasUndo ? Palette.accent(dark: isDarkMode) : Palette.textSecondary(dark: isDarkMode)
        rewindButton.toolTip = hasUndo ? "Rewind the last edit (\(editUndoStack.count) available)" : "Rewind the last edit"
    }

    @objc private func attachFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsOtherFileTypes = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.attachContext(urls: panel.urls)
        }
    }

    @objc private func attachURL() {
        let alert = NSAlert()
        alert.messageText = "Attach URL"
        alert.informativeText = "The URL will be included as context in the next agent prompts."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Attach")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "https://example.com/page"
        alert.accessoryView = input
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            self?.attachContext(label: "URL", value: value)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
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
        for btn in [reloadBtn, chatToggleButton, browserBtn, openBtn, updateBtn, darkModeButton, pickerButton, processToggleButton, newSessionButton, rewindButton, attachButton, attachURLButton].compactMap({ $0 }) {
            btn.hoverColor = hoverBg
            btn.contentTintColor = Palette.textPrimary(dark: isDarkMode)
        }
        agentPopup?.isEnabled = currentFileURL != nil
        modelPopup?.isEnabled = currentFileURL != nil && activeAgentIndex != nil

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
        updateAgentStatusIndicator()
        chatScrollView?.backgroundColor = Palette.surface(dark: isDarkMode)
        chatInput?.textColor = Palette.textPrimary(dark: isDarkMode)
        chatInput?.backgroundColor = .clear
        chatInputPlaceholder?.textColor = Palette.textSecondary(dark: isDarkMode)
        editContextCheckbox?.contentTintColor = agentMode == .edit ? Palette.textPrimary(dark: isDarkMode) : Palette.textSecondary(dark: isDarkMode)
        chatInputBox?.layer?.backgroundColor = (isDarkMode
            ? NSColor.white.withAlphaComponent(0.04)
            : NSColor.black.withAlphaComponent(0.035)).cgColor
        chatInputBox?.layer?.borderColor = Palette.border(dark: isDarkMode).withAlphaComponent(0.65).cgColor
        chatSendButton?.contentTintColor = Palette.accent(dark: isDarkMode)
        chatStopButton?.contentTintColor = Palette.destructive
        chatToggleButton?.contentTintColor = isChatCollapsed ? Palette.textSecondary(dark: isDarkMode) : Palette.accent(dark: isDarkMode)
        updateBtn?.contentTintColor = latestUpdate == nil ? Palette.textPrimary(dark: isDarkMode) : Palette.accent(dark: isDarkMode)
        processToggleButton?.contentTintColor = showAgentProcess ? Palette.accent(dark: isDarkMode) : Palette.textSecondary(dark: isDarkMode)
        attachButton?.contentTintColor = attachedContexts.isEmpty ? Palette.textSecondary(dark: isDarkMode) : Palette.accent(dark: isDarkMode)
        attachURLButton?.contentTintColor = attachedContexts.isEmpty ? Palette.textSecondary(dark: isDarkMode) : Palette.accent(dark: isDarkMode)
        updateRewindButton()
        updateModeControls()
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
        modelPopup?.isEnabled = hasFile && activeAgentIndex != nil
    }

    // MARK: - App Updates

    @objc private func updateButtonClicked() {
        if let update = latestUpdate {
            installUpdate(update)
        } else {
            checkForUpdates(manual: true)
        }
    }

    private func checkForUpdates(manual: Bool) {
        guard !isCheckingForUpdate else { return }
        guard let url = URL(string: "https://api.github.com/repos/drfittri/HTMLEditor/releases/latest") else { return }
        isCheckingForUpdate = true
        updateBtn?.toolTip = "Checking for updates..."

        var request = URLRequest(url: url)
        request.setValue("HTML Agent Editor", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            let result: Result<UpdateInfo?, Error>
            do {
                if let error { throw error }
                guard let data else { throw NSError(domain: "HTMLAgentEditor", code: 1, userInfo: nil) }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let current = self.currentAppVersion()
                guard self.isNewerVersion(release.tagName, than: current),
                      let pageURL = URL(string: release.htmlURL) else {
                    result = .success(nil)
                    DispatchQueue.main.async {
                        self.finishUpdateCheck(result, manual: manual)
                    }
                    return
                }
                let asset = self.preferredUpdateAsset(from: release.assets)
                result = .success(UpdateInfo(
                    version: release.tagName,
                    pageURL: pageURL,
                    assetURL: asset.flatMap { URL(string: $0.browserDownloadURL) },
                    assetName: asset?.name
                ))
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                self.finishUpdateCheck(result, manual: manual)
            }
        }.resume()
    }

    private func finishUpdateCheck(_ result: Result<UpdateInfo?, Error>, manual: Bool) {
        isCheckingForUpdate = false
        switch result {
        case .success(let update?):
            latestUpdate = update
            updateBtn?.contentTintColor = Palette.accent(dark: isDarkMode)
            updateBtn?.toolTip = "Update available: \(update.version)"
            pulseButton(updateBtn)
            if manual || !didPresentUpdateIndicator {
                didPresentUpdateIndicator = true
                presentUpdateAvailable(update)
            }
        case .success(nil):
            latestUpdate = nil
            updateBtn?.contentTintColor = Palette.textPrimary(dark: isDarkMode)
            updateBtn?.toolTip = "Check for updates"
            if manual {
                presentSimpleAlert(title: "No Update Available", message: "HTML Agent Editor is up to date.")
            }
        case .failure:
            updateBtn?.toolTip = "Could not check for updates"
            if manual {
                presentSimpleAlert(title: "Could Not Check for Updates", message: "GitHub could not be reached. Try again later.")
            }
        }
    }

    private func presentUpdateAvailable(_ update: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "HTML Agent Editor \(update.version) is available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.installUpdate(update)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private func installUpdate(_ update: UpdateInfo) {
        guard let assetURL = update.assetURL else {
            NSWorkspace.shared.open(update.pageURL)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Install \(update.version)?"
        alert.informativeText = "HTML Agent Editor will download the latest macOS release, replace this app after it quits, then reopen it."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Cancel")
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.runMacUpdater(assetURL: assetURL)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private func runMacUpdater(assetURL: URL) {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("html-agent-editor-update-\(UUID().uuidString).sh")
        let script = """
        #!/bin/zsh
        set -e
        APP_PATH=\(shellQuote(Bundle.main.bundlePath))
        APP_PID=\(ProcessInfo.processInfo.processIdentifier)
        ASSET_URL=\(shellQuote(assetURL.absoluteString))
        TMP_DIR=$(mktemp -d /tmp/html-agent-editor-update.XXXXXX)
        cleanup() { rm -rf "$TMP_DIR" "$0"; }
        trap cleanup EXIT
        curl -fL "$ASSET_URL" -o "$TMP_DIR/update.zip"
        ditto -x -k "$TMP_DIR/update.zip" "$TMP_DIR/extract"
        NEW_APP=$(find "$TMP_DIR/extract" -maxdepth 3 -name "*.app" -type d | head -n 1)
        if [ -z "$NEW_APP" ]; then
          open "$ASSET_URL"
          exit 0
        fi
        kill "$APP_PID" 2>/dev/null || true
        while kill -0 "$APP_PID" 2>/dev/null; do sleep 0.2; done
        rm -rf "$APP_PATH"
        ditto "$NEW_APP" "$APP_PATH"
        open "$APP_PATH"
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [scriptURL.path]
            try process.run()
        } catch {
            presentSimpleAlert(title: "Could Not Start Update", message: error.localizedDescription)
        }
    }

    private func preferredUpdateAsset(from assets: [GitHubAsset]) -> GitHubAsset? {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x64"
        #endif
        let macAssets = assets.filter {
            let name = $0.name.lowercased()
            return name.contains("macos") && name.hasSuffix(".zip")
        }
        return macAssets.first { $0.name.lowercased().contains(arch) } ?? macAssets.first
    }

    private func currentAppVersion() -> String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let left = versionParts(candidate)
        let right = versionParts(current)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private func versionParts(_ value: String) -> [Int] {
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return cleaned
            .split { !$0.isNumber }
            .map { Int($0) ?? 0 }
    }

    private func presentSimpleAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
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
        updateAgentStatusIndicator()
        updateModelPopup(for: agent)
        checkReadinessAfterSelection(for: agent, selectedIndex: idx)

        view.window?.makeFirstResponder(chatInput)
    }

    @objc private func modelPopupChanged() {
        guard let idx = activeAgentIndex, idx >= 0, idx < agentMeta.count,
              let item = modelPopup.selectedItem,
              let modelID = item.representedObject as? String else { return }
        let agent = agentMeta[idx]
        UserDefaults.standard.set(modelID, forKey: modelDefaultsKey(for: agent))
        appendChatLine("\(agent.label) model set to \(modelLabel(for: modelID)).", kind: .status)
    }

    private func updateModelPopup(for agent: AgentDefinition?) {
        modelPopup?.removeAllItems()
        guard let agent = agent else {
            modelPopup?.addItem(withTitle: "Choose an agent")
            modelPopup?.isEnabled = false
            return
        }

        for model in agent.models {
            modelPopup.addItem(withTitle: model.label)
            modelPopup.lastItem?.representedObject = model.id
        }

        let selectedID = selectedModelID(for: agent)
        if let selectedIndex = agent.models.firstIndex(where: { $0.id == selectedID }) {
            modelPopup.selectItem(at: selectedIndex)
        } else {
            modelPopup.selectItem(at: 0)
        }
        modelPopup.isEnabled = currentFileURL != nil
        refreshModelPopup(for: agent)
    }

    private func selectedModelID(for agent: AgentDefinition) -> String {
        let key = modelDefaultsKey(for: agent)
        if let saved = UserDefaults.standard.string(forKey: key) {
            return saved
        }
        return agent.models.first?.id ?? ""
    }

    private func modelDefaultsKey(for agent: AgentDefinition) -> String {
        return "HTMLAgentEditor.SelectedModel.\(agent.id)"
    }

    private func refreshModelPopup(for agent: AgentDefinition) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let dynamicModels = self.dynamicModels(for: agent)
            guard !dynamicModels.isEmpty else { return }
            let models = self.mergedModels(defaults: agent.models, dynamic: dynamicModels)
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let idx = self.activeAgentIndex,
                      idx >= 0,
                      idx < self.agentMeta.count,
                      self.agentMeta[idx].id == agent.id else { return }
                self.applyModelOptions(models, for: agent)
            }
        }
    }

    private func applyModelOptions(_ models: [AgentModel], for agent: AgentDefinition) {
        modelPopup?.removeAllItems()
        for model in models {
            modelPopup.addItem(withTitle: model.label)
            modelPopup.lastItem?.representedObject = model.id
        }
        let selectedID = selectedModelID(for: agent)
        if let selectedIndex = models.firstIndex(where: { $0.id == selectedID }) {
            modelPopup.selectItem(at: selectedIndex)
        } else {
            modelPopup.selectItem(at: 0)
        }
        modelPopup.isEnabled = currentFileURL != nil
    }

    private func modelLabel(for id: String) -> String {
        return id.isEmpty ? "Default" : id
    }

    private func mergedModels(defaults: [AgentModel], dynamic: [AgentModel]) -> [AgentModel] {
        var seen = Set<String>()
        var result: [AgentModel] = []
        for model in defaults + dynamic {
            guard !seen.contains(model.id) else { continue }
            seen.insert(model.id)
            result.append(model)
        }
        return result
    }

    private func dynamicModels(for agent: AgentDefinition) -> [AgentModel] {
        switch agent.id {
        case "opencode":
            return opencodeModels()
        case "codex":
            return codexModels()
        case "claude":
            return cachedProviderModels(providers: ["anthropic"], prefixIDs: false)
        case "agy":
            return agyModels()
        default:
            return []
        }
    }

    private func opencodeModels() -> [AgentModel] {
        guard let status = shellStatus("opencode models", timeout: 6), status.code == 0 else { return [] }
        return status.output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("error:") }
            .map { AgentModel(label: $0, id: $0) }
    }

    private func codexModels() -> [AgentModel] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { item in
            guard let slug = item["slug"] as? String, !slug.isEmpty else { return nil }
            let label = (item["display_name"] as? String)?.isEmpty == false
                ? item["display_name"] as! String
                : slug
            return AgentModel(label: label, id: slug)
        }
    }

    private func agyModels() -> [AgentModel] {
        guard let status = shellStatus("agy models", timeout: 6), status.code == 0 else { return [] }
        return status.output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("error:") }
            .map { AgentModel(label: $0, id: $0) }
    }

    private func cachedProviderModels(providers: [String]?, prefixIDs: Bool) -> [AgentModel] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/provider_models_cache.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let providerNames = providers ?? root.keys.sorted()
        var models: [AgentModel] = []
        for provider in providerNames {
            guard let entry = root[provider] as? [String: Any],
                  let values = entry["models"] as? [String] else { continue }
            models += values.map { model in
                let id = prefixIDs ? "\(provider)/\(model)" : model
                return AgentModel(label: id, id: id)
            }
        }
        return models
    }

    @objc private func sendChatPrompt() {
        let prompt = chatInput.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentFileURL != nil else {
            appendChatLine("Open an HTML file first.", kind: .error)
            return
        }
        guard !prompt.isEmpty else {
            appendChatLine(agentMode == .chat ? "Type a question first." : "Type a change request first.", kind: .error)
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
        guard let idx = activeAgentIndex, idx >= 0, idx < agentMeta.count else { return }
        let agent = agentMeta[idx]
        guard commandExists(agent.id) else {
            updateAgentStatusIndicator()
            presentInstallPrompt(for: agent)
            appendChatLine("\(agent.label) CLI needs to be installed before it can run.", kind: .error)
            return
        }
        if let issue = authorizationIssue(for: agent) {
            presentAgentIssue(issue, for: agent)
            appendChatLine("\(agent.label) needs authorization before it can run.", kind: .error)
            return
        }
        let mode = agentMode
        // Both modes reuse the agent's own session (server-side context) so the file
        // and prior turns aren't re-sent. Inject trimmed history only on the first turn
        // of a session, when no live session exists yet to carry it.
        let resume = canResumeSession(agent: agent)
        let includeHistory = !resume && (mode == .chat || includeEditContext)
        let payload = mode == .chat
            ? chatPrompt(userText: prompt, includeHistory: includeHistory)
            : agentPrompt(userText: prompt, includeHistory: includeHistory)
        appendChatLine(prompt, kind: .user)
        appendSessionMessage(role: "user", text: prompt, mode: mode)
        pulseComposer()
        chatInput.string = ""
        updatePromptInputHeight()
        runAgent(prompt: payload, mode: mode, resume: resume)
        view.window?.makeFirstResponder(chatInput)
    }

    @objc private func stopRunningAgent() {
        guard let process = runningAgentProcess else { return }
        didCancelRunningAgent = true
        appendChatLine("Stopping agent run...", kind: .status)
        if process.isRunning {
            process.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak process] in
            guard let self = self, let process = process, self.runningAgentProcess === process, process.isRunning else { return }
            process.interrupt()
        }
        updateAgentRunningState(false)
    }

    private func updateAgentRunningState(_ isRunning: Bool) {
        chatSendButton?.isEnabled = !isRunning
        chatSendButton?.isHidden = isRunning
        chatStopButton?.isEnabled = isRunning
        chatStopButton?.isHidden = !isRunning
        modeSegment?.isEnabled = !isRunning
        editContextCheckbox?.isEnabled = !isRunning && agentMode == .edit
        newSessionButton?.isEnabled = !isRunning
        attachButton?.isEnabled = !isRunning
        attachURLButton?.isEnabled = !isRunning
        rewindButton?.isEnabled = !isRunning && !editUndoStack.isEmpty
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

    private func checkReadinessAfterSelection(for agent: AgentDefinition, selectedIndex: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let exists = self.commandExists(agent.id)
            let issue = exists ? self.authorizationIssue(for: agent) : nil
            DispatchQueue.main.async {
                guard self.activeAgentIndex == selectedIndex else { return }
                self.updateAgentStatusIndicator()
                if exists {
                    if let issue = issue {
                        self.presentAgentIssue(issue, for: agent)
                    }
                } else {
                    self.presentInstallPrompt(for: agent)
                }
            }
        }
    }

    private func authorizationIssue(for agent: AgentDefinition) -> AgentIssue? {
        guard commandExists(agent.id) else {
            return AgentIssue(
                title: "\(agent.label) CLI not found",
                message: "\(agent.label) is not installed yet.",
                actionCommand: nil
            )
        }

        switch agent.id {
        case "claude":
            let env = ProcessInfo.processInfo.environment
            let home = env["HOME"] ?? NSHomeDirectory()
            let credentialPaths = [
                "\(home)/.claude/.credentials.json",
                "\(home)/.claude.json",
            ]
            let hasCredentialFile = credentialPaths.contains { FileManager.default.fileExists(atPath: $0) }
            if env["ANTHROPIC_API_KEY"]?.isEmpty == false || hasCredentialFile {
                return nil
            }
            return AgentIssue(
                title: "Authorize Claude",
                message: "Claude needs an authorized subscription/account before HTML Agent Editor can use it. Run Claude once and complete the sign-in flow.",
                actionCommand: agent.loginCommand
            )
        case "codex":
            if let status = shellStatus("codex login status", timeout: 3),
               status.code == 0,
               !authOutputMeansMissing(status.output) {
                return nil
            }
            return AgentIssue(
                title: "Authorize Codex",
                message: "Codex needs an authorized ChatGPT subscription/account before HTML Agent Editor can use it.",
                actionCommand: agent.loginCommand
            )
        default:
            return nil
        }
    }

    private func updateAgentStatusIndicator() {
        guard let dot = agentStatusDot else { return }
        guard let idx = activeAgentIndex, idx >= 0, idx < agentMeta.count else {
            dot.layer?.backgroundColor = Palette.textSecondary(dark: isDarkMode).withAlphaComponent(0.4).cgColor
            dot.toolTip = "No agent selected"
            return
        }
        let agent = agentMeta[idx]
        let installed = commandExists(agent.id)
        dot.layer?.backgroundColor = (installed
            ? Palette.accent(dark: isDarkMode)
            : Palette.textSecondary(dark: isDarkMode).withAlphaComponent(0.45)).cgColor
        dot.toolTip = installed ? "\(agent.label) CLI ready" : "\(agent.label) CLI not installed"
    }

    private func presentInstallPrompt(for agent: AgentDefinition) {
        guard installingAgentID == nil else { return }
        guard let command = installCommand(for: agent) else {
            appendChatLine("No automatic installer is configured for \(agent.label).", kind: .error)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Install \(agent.label) CLI?"
        alert.informativeText = "\(agent.label) is not installed yet. HTML Agent Editor can install it now and update you here when it is ready."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.installAgent(agent, command: command)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private func installCommand(for agent: AgentDefinition) -> String? {
        switch agent.id {
        case "claude":
            return "curl -fsSL https://claude.ai/install.sh | bash"
        case "codex":
            return "curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh"
        case "opencode":
            return "curl -fsSL https://opencode.ai/install | bash"
        case "agy":
            return "curl -fsSL https://antigravity.google/cli/install.sh | bash"
        default:
            return nil
        }
    }

    private func installAgent(_ agent: AgentDefinition, command: String) {
        guard installingAgentID == nil else { return }
        installingAgentID = agent.id
        appendChatLine("Installing \(agent.label) CLI...", kind: .status)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.environment = agentEnvironment()
        installingAgentProcess = process

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                let clean = self?.stripANSI(text).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !clean.isEmpty {
                    self?.appendChatLine(clean, kind: .process)
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.installingAgentID = nil
                self?.installingAgentProcess = nil
                self?.updateAgentStatusIndicator()
                if proc.terminationStatus == 0, self?.commandExists(agent.id) == true {
                    self?.appendChatLine("\(agent.label) CLI installed and ready.", kind: .status)
                    if let idx = self?.activeAgentIndex, idx >= 0, idx < (self?.agentMeta.count ?? 0), self?.agentMeta[idx].id == agent.id,
                       let issue = self?.authorizationIssue(for: agent) {
                        self?.presentAgentIssue(issue, for: agent)
                    }
                } else {
                    self?.appendChatLine("Could not install \(agent.label). Open Thinking to inspect the installer output.", kind: .error)
                }
            }
        }

        do {
            try process.run()
        } catch {
            installingAgentID = nil
            installingAgentProcess = nil
            appendChatLine("Could not start \(agent.label) installer: \(error.localizedDescription)", kind: .error)
        }
    }

    private func presentAgentIssue(_ issue: AgentIssue, for agent: AgentDefinition) {
        let alert = NSAlert()
        alert.messageText = issue.title
        alert.informativeText = issue.message + (issue.actionCommand.map { "\n\nCommand: \($0)" } ?? "")
        alert.alertStyle = .informational
        if issue.actionCommand != nil {
            alert.addButton(withTitle: "Authorize")
        }
        alert.addButton(withTitle: "OK")
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let command = issue.actionCommand else { return }
            self?.openAuthorizationTerminal(command: command)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private func openAuthorizationTerminal(command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script \(appleScriptString(command))
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func commandExists(_ command: String) -> Bool {
        guard let status = shellStatus("command -v \(shellQuote(command))", timeout: 2) else { return false }
        return status.code == 0
    }

    private func shellStatus(_ command: String, timeout: TimeInterval) -> (code: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.environment = agentEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, stripANSI(output))
    }

    private func authOutputMeansMissing(_ output: String) -> Bool {
        let text = output.lowercased()
        let markers = [
            "not logged in",
            "not authenticated",
            "no credentials",
            "login required",
            "authentication required",
            "unauthorized",
            "api key",
            "subscription",
        ]
        return markers.contains { text.contains($0) }
    }

    // Session reuse spans both chat and edit so switching modes stays in one session.
    // "Use Context" is the continuity master switch; a live session is dropped only by
    // the New Session button, a new file, or an agent switch. Claude uses an explicit
    // session id (immune to other windows); other agents resume the most-recent session.
    private func canResumeSession(agent: AgentDefinition) -> Bool {
        guard includeEditContext else { return false }
        if agent.id == "claude" { return claudeSessionID != nil }
        return sessionActiveAgentID == agent.id
    }

    private func runAgent(prompt: String, mode: AgentMode, resume: Bool) {
        guard let idx = activeAgentIndex, idx >= 0, idx < agentMeta.count, let fileURL = currentFileURL else { return }
        let agent = agentMeta[idx]
        let dir = fileURL.deletingLastPathComponent().path
        if agent.id == "claude" && !resume { claudeSessionID = nil }
        let command = agentCommand(agentID: agent.id, prompt: prompt, fileURL: fileURL, workingDirectory: dir, mode: mode, resume: resume)

        appendChatLine("\(agent.label): using model \(modelLabel(for: selectedModelID(for: agent))) in \(mode == .chat ? "chat" : "edit") mode.", kind: .status)
        appendChatLine("\(agent.label): running...", kind: .status)
        didCancelRunningAgent = false
        updateAgentRunningState(true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        process.environment = agentEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        runningAgentProcess = process
        let beforeData = try? Data(contentsOf: fileURL)
        var capturedOutput = ""

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                let clean = self?.stripANSI(text).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                capturedOutput += clean + "\n"
                self?.appendChatLine(clean, kind: .process)
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.runningAgentProcess = nil
                self?.updateAgentRunningState(false)
                if self?.didCancelRunningAgent == true {
                    self?.didCancelRunningAgent = false
                    self?.appendChatLine("Agent run stopped.", kind: .status)
                    return
                }
                if proc.terminationStatus == 0 {
                    // Both chat and edit runs leave a resumable session so switching
                    // modes continues the same session until New Session is pressed.
                    self?.sessionActiveAgentID = agent.id
                    let afterData = try? Data(contentsOf: fileURL)
                    let changed = beforeData != nil && afterData != beforeData
                    if mode == .chat {
                        let answer = self?.cleanAgentAnswer(capturedOutput) ?? ""
                        self?.appendChatLine(answer.isEmpty ? "I could not find a usable answer in the agent output. Open Thinking to inspect it." : answer, kind: answer.isEmpty ? .error : .agent)
                        if !answer.isEmpty {
                            self?.appendSessionMessage(role: "assistant", text: answer, mode: .chat)
                        }
                        if changed, let beforeData = beforeData {
                            do {
                                try beforeData.write(to: fileURL, options: .atomic)
                                self?.webView.reload()
                                self?.appendChatLine("Chat mode restored the file after the agent attempted a change.", kind: .status)
                            } catch {
                                self?.appendChatLine("Chat mode detected a file change but could not restore it: \(error.localizedDescription)", kind: .error)
                            }
                        }
                    } else {
                        self?.webView.reload()
                        if changed, let beforeData = beforeData {
                            self?.editUndoStack.append(EditSnapshot(fileURL: fileURL, data: beforeData))
                            self?.updateRewindButton()
                        }
                        let summary = changed ? "Done. Preview reloaded." : "Done, but the file appears unchanged. Open Thinking to inspect the agent output."
                        self?.appendChatLine(summary, kind: changed ? .status : .error)
                        self?.appendSessionMessage(role: "assistant", text: summary, mode: .edit)
                    }
                } else if self?.authOutputMeansMissing(capturedOutput) == true {
                    self?.presentAgentIssue(
                        AgentIssue(
                            title: "Authorize \(agent.label)",
                            message: "\(agent.label) reported an authorization problem. Authorize with your subscription/account, then run the request again.",
                            actionCommand: agent.loginCommand
                        ),
                        for: agent
                    )
                    self?.appendChatLine("\(agent.label) needs authorization before it can run.", kind: .error)
                } else {
                    self?.appendChatLine("Agent exited with status \(proc.terminationStatus). Open Thinking to inspect the output.", kind: .error)
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
            updateAgentRunningState(false)
            appendChatLine("Could not start \(agent.label): \(error.localizedDescription)", kind: .error)
        }
    }

    private func agentCommand(agentID: String, prompt: String, fileURL: URL, workingDirectory: String, mode: AgentMode, resume: Bool) -> String {
        let qPrompt = shellQuote(prompt)
        let qFile = shellQuote(fileURL.path)
        let qDir = shellQuote(workingDirectory)
        if let override = ProcessInfo.processInfo.environment["HTML_AGENT_EDITOR_AGENT_COMMAND"], !override.isEmpty {
            return "\(override) \(qPrompt)"
        }
        let agent = agentMeta.first { $0.id == agentID }
        let modelID = agent.map { selectedModelID(for: $0) } ?? ""
        let modelArg = modelID.isEmpty ? "" : " --model \(shellQuote(modelID))"
        switch agentID {
        case "opencode":
            let cont = resume ? " -c" : ""
            return "opencode run\(cont)\(modelArg) \(qPrompt) --auto --dir \(qDir) --file \(qFile)"
        case "claude":
            // Reuse a server-side session so follow-up turns don't re-send the file
            // or prior conversation as prompt text. Deterministic per-window UUID
            // avoids cross-window collisions from --continue's "most recent" lookup.
            // Both chat and edit share the session so switching modes stays continuous.
            var sessionArg = ""
            if resume, let sid = claudeSessionID {
                sessionArg = " --resume \(sid)"
            } else {
                let sid = UUID().uuidString.lowercased()
                claudeSessionID = sid
                sessionArg = " --session-id \(sid)"
            }
            return "printf %s \(qPrompt) | claude --print\(sessionArg)\(modelArg) --dangerously-skip-permissions --add-dir \(qDir)"
        case "codex":
            let head = "out=$(mktemp /tmp/html-agent-editor-codex.XXXXXX); err=$(mktemp /tmp/html-agent-editor-codex-err.XXXXXX); "
            let tail = " >/dev/null 2>\"$err\"; exitCode=$?; if [ $exitCode -eq 0 ]; then cat \"$out\"; else cat \"$err\"; fi; rm -f \"$out\" \"$err\"; exit $exitCode"
            let core: String
            if resume {
                // resume inherits the original session's cwd/sandbox; only a subset of flags is accepted.
                core = "printf %s \(qPrompt) | codex -a never\(modelArg) exec resume --last --skip-git-repo-check -o \"$out\" -"
            } else {
                // Persistent full-access session shared by chat and edit so either mode can
                // resume it. Chat safety comes from the post-run file restore, not the sandbox.
                core = "printf %s \(qPrompt) | codex -a never\(modelArg) exec --cd \(qDir) --sandbox danger-full-access --skip-git-repo-check --color never -o \"$out\" -"
            }
            return head + core + tail
        case "agy":
            let cont = resume ? " -c" : ""
            return "agy --dangerously-skip-permissions\(cont)\(modelArg) -p \(qPrompt)"
        default:
            return "\(shellQuote(agentID)) \(qPrompt)"
        }
    }

    private func agentEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = [
            "\(home)/.claude/local",
            "\(home)/.codex/bin",
            "\(home)/.opencode/bin",
            "\(home)/.hermes/bin",
            "\(home)/.antigravity/bin",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            currentPath,
            "/usr/bin:/bin:/usr/sbin:/sbin",
        ].joined(separator: ":")
        return env
    }

    private func agentPrompt(userText: String, includeHistory: Bool) -> String {
        var lines = [
            "Edit the currently open HTML file with the smallest correct change.",
            "Token/output budget: be terse. Do not narrate steps, commands, diffs, file contents, or logs.",
            "File: \(currentFileURL?.path ?? "unknown")",
        ]
        if includeHistory, let history = sessionContext(), !history.isEmpty {
            lines.append("Prior conversation in this session for context only:")
            lines.append(history)
        } else if !includeEditContext {
            lines.append("Ignore prior chat, prior edit summaries, and attached context for this edit.")
        }
        if includeEditContext, let attachmentText = attachmentContext(), !attachmentText.isEmpty {
            lines.append("Attached context references:")
            lines.append(attachmentText)
        }
        if let selectedElementContext {
            lines.append("Selected element context:\n\(selectedElementContext)")
            let targetText = selectedElements.count == 1 ? "the selected element" : "all selected elements"
            lines.append("Unless the user clearly asks for a broader change, apply the requested change to \(targetText).")
        } else {
            lines.append("No specific element selected.")
        }
        lines.append("User request: \(userText)")
        lines.append("Apply the edit directly. Preserve unrelated content. Final answer only: one sentence under 25 words naming what changed.")
        return lines.joined(separator: "\n")
    }

    private func chatPrompt(userText: String, includeHistory: Bool) -> String {
        var lines = [
            "Answer the user's question about the currently open HTML document or selected element.",
            "This is chat mode: do not edit files, do not run write commands, and do not modify the document.",
            "Be more explanatory than edit mode: give enough context for the user to understand the element, revision, or tradeoff.",
            "Do not reveal hidden chain-of-thought. If useful, provide a brief visible rationale or checklist.",
            "Open file name: \(currentFileURL?.lastPathComponent ?? "unknown")",
        ]
        if includeHistory, let history = sessionContext(mode: .chat), !history.isEmpty {
            lines.append("Prior conversation in this session:")
            lines.append(history)
        }
        if let attachmentText = attachmentContext(), !attachmentText.isEmpty {
            lines.append("Attached context references:")
            lines.append(attachmentText)
        }
        if let selectedElementContext {
            lines.append("Selected element context:\n\(selectedElementContext)")
        } else {
            lines.append("No specific element selected.")
        }
        lines.append("Question: \(userText)")
        lines.append("Final answer only. Use concise paragraphs or bullets when helpful.")
        return lines.joined(separator: "\n")
    }

    private func sessionContext(mode: AgentMode? = nil) -> String? {
        guard !sessionMessages.isEmpty else { return nil }
        let messages = sessionMessages.filter { message in
            guard let requiredMode = mode else { return true }
            return message.mode == requiredMode
        }
        guard !messages.isEmpty else { return nil }
        return messages
            .suffix(4)
            .map { "\($0.role == "user" ? "User" : "Assistant"): \($0.text)" }
            .joined(separator: "\n")
    }

    private func attachmentContext() -> String? {
        guard !attachedContexts.isEmpty else { return nil }
        return attachedContexts
            .map { "- \($0.label): \($0.value)" }
            .joined(separator: "\n")
    }

    private func appendSessionMessage(role: String, text: String, mode: AgentMode) {
        guard !text.isEmpty else { return }
        sessionMessages.append(SessionMessage(role: role, text: text, mode: mode))
        if sessionMessages.count > 20 {
            sessionMessages = Array(sessionMessages.suffix(20))
        }
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
            let message = ChatMessage(kind: .process, text: "\(hiddenProcessCount) thinking update\(hiddenProcessCount == 1 ? "" : "s") hidden. Use Think to view.")
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

    private func cleanAgentAnswer(_ text: String) -> String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func attachContext(urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                attachContext(label: attachmentLabel(for: url), value: "\(url.path)\nfileURL: \(url.absoluteString)")
            } else {
                attachContext(label: "URL", value: url.absoluteString)
            }
        }
    }

    private func attachContext(label: String, value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if attachedContexts.contains(where: { $0.value == clean }) {
            appendChatLine("Context already attached: \(label)", kind: .status)
            return
        }
        attachedContexts.append(AttachmentContext(label: label, value: clean))
        appendChatLine("Attached context: \(label)", kind: .status)
        applyAppearance()
    }

    private func attachmentLabel(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "svg"].contains(ext) {
            return "Image \(url.lastPathComponent)"
        }
        return "File \(url.lastPathComponent)"
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
        sessionMessages = []
        claudeSessionID = nil
        sessionActiveAgentID = nil
        attachedContexts = []
        editUndoStack = []
        updateRewindButton()
        selectedElementContext = nil
        selectedElements = []
        selectedElementLabel.stringValue = "No element selected"
        selectedElementDetail.stringValue = "Click any visible element in the preview. The selected DOM context will be sent with your next message."
        if activeAgentIndex == nil, let defaultIndex = agentMeta.firstIndex(where: { $0.id == "opencode" }) {
            activeAgentIndex = defaultIndex
            agentPopup?.selectItem(at: defaultIndex + 1)
            activeAgentLabel.stringValue = agentMeta[defaultIndex].label
        }
        if let idx = activeAgentIndex, idx >= 0, idx < agentMeta.count {
            updateModelPopup(for: agentMeta[idx])
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
            updateModelPopup(for: agentMeta[idx])
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
                self?.chatInput.string = prompt
                self?.updatePromptInputHeight()
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
        if currentFileURL == nil && url.isFileURL && (ext == "html" || ext == "htm") {
            loadFile(url: url)
        } else if url.isFileURL {
            attachContext(urls: [url])
        } else {
            attachContext(label: "URL", value: url.absoluteString)
        }
        return true
    }

    func isAcceptableDropURL(_ url: URL) -> Bool {
        return url.isFileURL || ["http", "https"].contains(url.scheme?.lowercased() ?? "")
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

protocol HTMLFileDropHandling: AnyObject {
    func handleDragAcceptance(_ accepted: Bool)
    func handleDroppedFile(_ url: URL) -> Bool
    func isAcceptableDropURL(_ url: URL) -> Bool
}

extension ViewController: HTMLFileDropHandling {}

private func firstDroppedFileURL(from info: NSDraggingInfo) -> URL? {
    let pasteboard = info.draggingPasteboard
    if let url = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL {
        return url
    }
    if let url = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? NSURL {
        return url as URL
    }
    if let value = pasteboard.string(forType: .fileURL), let url = URL(string: value) {
        return url
    }
    return nil
}

final class DragContainerView: NSView {
    weak var dragHandler: ViewController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .URL])
    }

    private func firstURL(from info: NSDraggingInfo) -> URL? {
        return firstDroppedFileURL(from: info)
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

final class DragWebView: WKWebView {
    weak var dragHandler: HTMLFileDropHandling?

    override init(frame frameRect: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frameRect, configuration: configuration)
        registerForDraggedTypes([.fileURL, .URL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .URL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = firstDroppedFileURL(from: sender), dragHandler?.isAcceptableDropURL(url) == true else {
            return []
        }
        dragHandler?.handleDragAcceptance(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = firstDroppedFileURL(from: sender), dragHandler?.isAcceptableDropURL(url) == true else {
            return []
        }
        return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = firstDroppedFileURL(from: sender) else { return false }
        return dragHandler?.isAcceptableDropURL(url) == true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = firstDroppedFileURL(from: sender) else { return false }
        return dragHandler?.handleDroppedFile(url) == true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dragHandler?.handleDragAcceptance(false)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragHandler?.handleDragAcceptance(false)
    }
}
