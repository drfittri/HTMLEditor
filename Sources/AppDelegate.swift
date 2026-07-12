import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windows: [NSWindow] = []
    private var selfTestViewController: ViewController?
    var pendingFileURLs: [URL] = []
    private var selfTestSendPrompt: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clipboard bitmaps and the PNG/AVIF pair from image conversion live in a scratch
        // directory. Wipe it once per launch (not per window, which would pull attachments
        // out from under an already-open one) so temps can never accumulate.
        ViewController.purgeScratchDirectory()
        let isDark = UserDefaults.standard.bool(forKey: "darkMode")
        if isDark {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        // FEAT-05: macOS menu bar
        setupMainMenu()

        let args = Array(CommandLine.arguments.dropFirst())
        if let idx = args.firstIndex(of: "--self-test-send"), idx + 1 < args.count {
            selfTestSendPrompt = args[idx + 1]
        }
        if pendingFileURLs.isEmpty {
            pendingFileURLs = args
                .filter { !$0.hasPrefix("--") && ($0.hasSuffix(".html") || $0.hasSuffix(".htm")) }
                .map { URL(fileURLWithPath: $0) }
        }

        let firstViewController: ViewController
        if pendingFileURLs.isEmpty {
            firstViewController = createWindow()
        } else {
            firstViewController = createWindow(fileURL: pendingFileURLs.removeFirst())
            for fileURL in pendingFileURLs {
                createWindow(fileURL: fileURL)
            }
            pendingFileURLs = []
        }
        selfTestViewController = firstViewController

        if let prompt = selfTestSendPrompt {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.selfTestViewController?.runSelfTestSend(prompt: prompt)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                print("HTML_AGENT_EDITOR_SELF_TEST_TRANSCRIPT_BEGIN")
                print(self?.selfTestViewController?.selfTestTranscript() ?? "")
                print("HTML_AGENT_EDITOR_SELF_TEST_TRANSCRIPT_END")
                NSApp.terminate(nil)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        if windows.isEmpty {
            pendingFileURLs.append(contentsOf: urls)
            return
        }
        for fileURL in urls {
            createWindow(fileURL: fileURL)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @discardableResult
    private func createWindow(fileURL: URL? = nil) -> ViewController {
        let viewController = ViewController()
        let windowRect = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let windowStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: windowStyle,
            backing: .buffered,
            defer: false
        )
        window.title = "HTML Agent Editor"
        window.contentViewController = viewController
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self

        if windows.isEmpty {
            window.center()
        } else if let lastFrame = windows.last?.frame {
            window.setFrameOrigin(NSPoint(x: lastFrame.minX + 28, y: max(40, lastFrame.minY - 28)))
        }

        windows.append(window)
        window.makeKeyAndOrderFront(nil)
        if let fileURL {
            viewController.loadFile(url: fileURL)
        }
        return viewController
    }

    @objc func menuNewWindow() {
        createWindow()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === closingWindow }
        if selfTestViewController?.view.window === closingWindow {
            selfTestViewController = windows.first?.contentViewController as? ViewController
        }
    }

    // MARK: - Menu bar (FEAT-05)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        let newWindowItem = NSMenuItem(title: "New Window", action: #selector(AppDelegate.menuNewWindow), keyEquivalent: "n")
        newWindowItem.target = self
        fileMenu.addItem(newWindowItem)
        fileMenu.addItem(withTitle: "Open\u{2026}", action: #selector(ViewController.menuOpenFile), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Reload", action: #selector(ViewController.menuReload), keyEquivalent: "r")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Open in Browser", action: #selector(ViewController.menuOpenBrowser), keyEquivalent: "b")
        fileMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Edit menu (standard)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        // Cmd+F opens the in-page find bar (routed through the responder chain to the VC).
        editMenu.addItem(withTitle: "Find\u{2026}", action: #selector(ViewController.menuFind), keyEquivalent: "f")

        // Format menu (text formatting applied to the preview selection)
        let formatMenuItem = NSMenuItem()
        mainMenu.addItem(formatMenuItem)
        let formatMenu = NSMenu(title: "Format")
        formatMenuItem.submenu = formatMenu
        formatMenu.addItem(withTitle: "Bold", action: #selector(ViewController.menuBold), keyEquivalent: "b")
        formatMenu.addItem(withTitle: "Italic", action: #selector(ViewController.menuItalic), keyEquivalent: "i")
        formatMenu.addItem(withTitle: "Underline", action: #selector(ViewController.menuUnderline), keyEquivalent: "u")
        let strike = NSMenuItem(title: "Strikethrough", action: #selector(ViewController.menuStrikethrough), keyEquivalent: "x")
        strike.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(strike)
        formatMenu.addItem(NSMenuItem.separator())
        let highlightItem = NSMenuItem(title: "Highlight", action: nil, keyEquivalent: "")
        let highlightMenu = NSMenu(title: "Highlight")
        let swatches: [(String, Int)] = [("Yellow", 0), ("Green", 1), ("Blue", 2), ("Pink", 3), ("Orange", 4)]
        for (name, tag) in swatches {
            let item = NSMenuItem(title: name, action: #selector(ViewController.menuHighlight(_:)), keyEquivalent: "")
            item.tag = tag
            highlightMenu.addItem(item)
        }
        highlightMenu.addItem(NSMenuItem.separator())
        let removeHL = NSMenuItem(title: "Remove Highlight", action: #selector(ViewController.menuHighlight(_:)), keyEquivalent: "")
        removeHL.tag = -1
        highlightMenu.addItem(removeHL)
        highlightItem.submenu = highlightMenu
        formatMenu.addItem(highlightItem)
        formatMenu.addItem(NSMenuItem.separator())
        let clearFmt = NSMenuItem(title: "Remove Formatting", action: #selector(ViewController.menuRemoveFormatting), keyEquivalent: "\\")
        clearFmt.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(clearFmt)

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        let toggleDark = NSMenuItem(title: "Toggle Dark Mode", action: #selector(ViewController.menuToggleDark), keyEquivalent: "d")
        toggleDark.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(toggleDark)
        viewMenu.addItem(withTitle: "Clear Chat", action: #selector(ViewController.menuClearTerminal), keyEquivalent: "k")

        // Agent menu
        let agentMenuItem = NSMenuItem()
        mainMenu.addItem(agentMenuItem)
        let agentMenu = NSMenu(title: "Agent")
        agentMenuItem.submenu = agentMenu
        let agents: [(String, String)] = [
            ("Claude", "1"),
            ("Codex", "2"),
            ("OpenCode", "3"),
            ("Hermes", "4"),
            ("Antigravity", "5"),
        ]
        for (i, (name, key)) in agents.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(ViewController.menuAgent(_:)), keyEquivalent: key)
            item.tag = i
            agentMenu.addItem(item)
        }

        // Window menu (standard)
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
