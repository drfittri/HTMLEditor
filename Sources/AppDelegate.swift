import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var viewController: ViewController?
    var pendingFileURL: URL?
    private var selfTestSendPrompt: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDark = UserDefaults.standard.bool(forKey: "darkMode")
        if isDark {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        viewController = ViewController()

        let windowRect = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let windowStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window = NSWindow(
            contentRect: windowRect,
            styleMask: windowStyle,
            backing: .buffered,
            defer: false
        )
        window?.title = "HTML Agent Editor"
        window?.contentViewController = viewController
        window?.titlebarAppearsTransparent = true
        window?.isMovableByWindowBackground = true
        window?.center()
        window?.makeKeyAndOrderFront(nil)

        // FEAT-05: macOS menu bar
        setupMainMenu()

        let args = Array(CommandLine.arguments.dropFirst())
        if let idx = args.firstIndex(of: "--self-test-send"), idx + 1 < args.count {
            selfTestSendPrompt = args[idx + 1]
        }
        if pendingFileURL == nil, let path = args.first(where: { !$0.hasPrefix("--") && ($0.hasSuffix(".html") || $0.hasSuffix(".htm")) }) {
            pendingFileURL = URL(fileURLWithPath: path)
        }

        if let fileURL = pendingFileURL {
            viewController?.loadFile(url: fileURL)
            pendingFileURL = nil
        }

        if let prompt = selfTestSendPrompt {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.viewController?.runSelfTestSend(prompt: prompt)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                print("HTML_AGENT_EDITOR_SELF_TEST_TRANSCRIPT_BEGIN")
                print(self?.viewController?.selfTestTranscript() ?? "")
                print("HTML_AGENT_EDITOR_SELF_TEST_TRANSCRIPT_END")
                NSApp.terminate(nil)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let fileURL = urls.first else { return }
        if viewController?.view.window != nil {
            viewController?.loadFile(url: fileURL)
        } else {
            pendingFileURL = fileURL
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
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
