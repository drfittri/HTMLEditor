const { app, BrowserWindow, Menu, clipboard, dialog, ipcMain, shell } = require("electron");
const { pathToFileURL } = require("url");
const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const https = require("https");
const os = require("os");
const path = require("path");

const appName = "HTML Agent Editor";
const watchers = new Map();
const runningProcesses = new Map();
const installingAgents = new Map();
const editUndoStacks = new Map();
const claudeSessions = new Map();
const opencodeSessions = new Map();
const repoOwner = "drfittri";
const repoName = "HTMLEditor";

const agents = [
  {
    id: "claude",
    label: "Claude",
    loginCommand: "claude",
    models: [
      { label: "Default", id: "" },
      { label: "Fable", id: "fable" },
      { label: "Opus", id: "opus" },
      { label: "Sonnet", id: "sonnet" },
      { label: "Haiku", id: "haiku" }
    ]
  },
  {
    id: "codex",
    label: "Codex",
    loginCommand: "codex login",
    models: [
      { label: "Default", id: "" },
      { label: "GPT-5.5", id: "gpt-5.5" },
      { label: "GPT-5.5 Pro", id: "gpt-5.5-pro" },
      { label: "GPT-5.4", id: "gpt-5.4" },
      { label: "GPT-5.4 Pro", id: "gpt-5.4-pro" },
      { label: "GPT-5.4 Mini", id: "gpt-5.4-mini" },
      { label: "GPT-5.4 Nano", id: "gpt-5.4-nano" },
      { label: "GPT-5.3 Codex", id: "gpt-5.3-codex" },
      { label: "GPT-5.2 Codex", id: "gpt-5.2-codex" },
      { label: "GPT-5 Mini", id: "gpt-5-mini" }
    ]
  },
  {
    id: "opencode",
    label: "OpenCode",
    loginCommand: "opencode auth",
    models: [
      { label: "Default", id: "" },
      { label: "opencode/big-pickle", id: "opencode/big-pickle" },
      { label: "opencode-go/kimi-k2.7-code", id: "opencode-go/kimi-k2.7-code" },
      { label: "opencode-go/minimax-m3", id: "opencode-go/minimax-m3" },
      { label: "deepseek/deepseek-v4-pro", id: "deepseek/deepseek-v4-pro" }
    ]
  },
  {
    id: "agy",
    label: "Antigravity",
    loginCommand: "agy",
    models: [
      { label: "Default", id: "" }
    ]
  }
];

function createWindow(filePath = null) {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 900,
    minHeight: 560,
    title: appName,
    backgroundColor: "#0a0e17",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      webviewTag: true
    }
  });

  win.initialFilePath = filePath;
  win.loadFile(path.join(__dirname, "index.html"));
  const webContentsId = win.webContents.id;

  win.webContents.on("did-finish-load", () => {
    if (!win.webContents.isDestroyed() && win.initialFilePath) {
      win.webContents.send("open-file-path", win.initialFilePath);
    }
  });

  win.on("closed", () => {
    stopWatching(webContentsId);
    stopAgentProcess(webContentsId);
    editUndoStacks.delete(webContentsId);
    claudeSessions.delete(webContentsId);
    opencodeSessions.delete(webContentsId);
  });

  return win;
}

function htmlFilesFromArgv(argv) {
  return argv
    .filter((item) => /\.(html?|xhtml)$/i.test(item))
    .map((item) => path.resolve(item));
}

function setupMenu() {
  const template = [
    {
      label: "File",
      submenu: [
        { label: "New Window", accelerator: "Ctrl+N", click: () => createWindow() },
        {
          label: "Open...",
          accelerator: "Ctrl+O",
          click: () => BrowserWindow.getFocusedWindow()?.webContents.send("menu-open-file")
        },
        {
          label: "Reload",
          accelerator: "Ctrl+R",
          click: () => BrowserWindow.getFocusedWindow()?.webContents.send("menu-reload")
        },
        {
          label: "Open in Browser",
          accelerator: "Ctrl+Shift+B",
          click: () => BrowserWindow.getFocusedWindow()?.webContents.send("menu-open-browser")
        },
        { type: "separator" },
        { role: "close" }
      ]
    },
    {
      label: "Edit",
      submenu: [
        { role: "undo" },
        { role: "redo" },
        { type: "separator" },
        { role: "cut" },
        { role: "copy" },
        { role: "paste" },
        { role: "selectAll" }
      ]
    },
    {
      label: "View",
      submenu: [
        {
          label: "Toggle Dark Mode",
          accelerator: "Ctrl+Shift+D",
          click: () => BrowserWindow.getFocusedWindow()?.webContents.send("menu-toggle-dark")
        },
        {
          label: "Clear Chat",
          accelerator: "Ctrl+K",
          click: () => BrowserWindow.getFocusedWindow()?.webContents.send("menu-clear-chat")
        },
        { type: "separator" },
        { role: "toggleDevTools" }
      ]
    },
    {
      label: "Agent",
      submenu: agents.map((agent, index) => ({
        label: agent.label,
        accelerator: `Ctrl+${index + 1}`,
        click: () => BrowserWindow.getFocusedWindow()?.webContents.send("menu-agent", agent.id)
      }))
    }
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

app.whenReady().then(() => {
  setupMenu();
  const files = htmlFilesFromArgv(process.argv.slice(app.isPackaged ? 1 : 2));
  if (files.length === 0) {
    createWindow();
  } else {
    files.forEach((file) => createWindow(file));
  }

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

ipcMain.handle("get-agents", () => agents);

ipcMain.handle("open-file-dialog", async (event) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  const result = await dialog.showOpenDialog(win, {
    title: "Open HTML File",
    filters: [{ name: "HTML Files", extensions: ["html", "htm"] }],
    properties: ["openFile"]
  });
  if (result.canceled || result.filePaths.length === 0) return null;
  return result.filePaths[0];
});

ipcMain.handle("file-url", (_event, filePath) => pathToFileURL(filePath).href);

ipcMain.handle("prepare-edit-file", (_event, filePath) => prepareEditFile(filePath));

ipcMain.handle("open-in-browser", async (_event, filePath) => {
  if (!filePath) return;
  await shell.openExternal(pathToFileURL(filePath).href);
});

ipcMain.handle("watch-file", (event, filePath) => {
  const id = event.sender.id;
  stopWatching(id);
  if (!filePath) return false;

  let timer = null;
  try {
    const watcher = fs.watch(filePath, () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        if (!event.sender.isDestroyed()) event.sender.send("file-changed", filePath);
      }, 100);
    });
    watchers.set(id, { watcher, timer });
    return true;
  } catch {
    return false;
  }
});

ipcMain.handle("dynamic-models", async (_event, agentId) => dynamicModels(agentId));

ipcMain.handle("agent-status", (_event, agentId) => agentStatus(agentId));

ipcMain.handle("install-agent", async (event, agentId) => installAgent(event.sender, agentId));

ipcMain.handle("check-for-updates", () => checkForUpdates());

ipcMain.handle("install-update", (_event, update) => installUpdate(update));

ipcMain.handle("send-agent", async (event, request) => {
  return runAgent(event.sender, request);
});

ipcMain.handle("reset-agent-session", (event) => {
  claudeSessions.delete(event.sender.id);
  opencodeSessions.delete(event.sender.id);
});

// Writes the clipboard bitmap to a temp PNG. Attachments reach the agent CLI as file
// paths, so a pasted image only has to exist on disk for the agent to read it.
ipcMain.handle("save-clipboard-image", () => {
  const image = clipboard.readImage();
  if (image.isEmpty()) return null;
  const filePath = path.join(os.tmpdir(), `html-agent-editor-paste-${Date.now()}.png`);
  fs.writeFileSync(filePath, image.toPNG());
  return filePath;
});

ipcMain.handle("rewind-last-edit", (event, filePath) => {
  return rewindLastEdit(event.sender.id, filePath);
});

ipcMain.handle("stop-agent", (event) => {
  return stopAgentProcess(event.sender.id);
});

ipcMain.handle("open-authorization-terminal", (_event, command) => {
  openAuthorizationTerminal(command);
});

function stopWatching(id) {
  const entry = watchers.get(id);
  if (!entry) return;
  clearTimeout(entry.timer);
  entry.watcher.close();
  watchers.delete(id);
}

function commandExists(command) {
  const checker = process.platform === "win32"
    ? path.join(process.env.SystemRoot || "C:\\Windows", "System32", "where.exe")
    : "sh";
  const args = process.platform === "win32" ? [command] : ["-lc", `command -v ${shellQuote(command)}`];
  const result = childProcess.spawnSync(checker, args, {
    encoding: "utf8",
    windowsHide: true,
    env: agentEnvironment()
  });
  return result.status === 0;
}

function gitBashPath(env = process.env) {
  const candidates = [
    env.CLAUDE_CODE_GIT_BASH_PATH,
    path.join(env.ProgramFiles || "C:\\Program Files", "Git", "bin", "bash.exe"),
    path.join(env.ProgramFiles || "C:\\Program Files", "Git", "usr", "bin", "bash.exe"),
    path.join(env["ProgramFiles(x86)"] || "C:\\Program Files (x86)", "Git", "bin", "bash.exe"),
    path.join(env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "Programs", "Git", "bin", "bash.exe")
  ].filter(Boolean);
  return candidates.find((candidate) => fs.existsSync(candidate)) || null;
}

function claudeShellDependencyInstalled() {
  if (process.platform !== "win32") return true;
  return commandExists("pwsh") || Boolean(gitBashPath(agentEnvironment()));
}

function agentStatus(agentId) {
  const agent = agents.find((item) => item.id === agentId);
  if (!agent) return { installed: false, ready: false, message: "Unknown agent." };
  const installed = commandExists(agent.id);
  if (installed && process.platform === "win32" && agent.id === "claude" && !claudeShellDependencyInstalled()) {
    return {
      installed: true,
      ready: false,
      installable: true,
      message: "Claude CLI installed, but PowerShell 7 or Git Bash is required."
    };
  }
  return {
    installed,
    ready: installed,
    message: installed ? `${agent.label} CLI ready.` : `${agent.label} CLI not installed.`
  };
}

function installCommand(agentId) {
  if (process.platform === "win32") {
    if (agentId === "claude") return windowsShellCommand("npm install -g @anthropic-ai/claude-code");
    if (agentId === "codex") return windowsShellCommand("npm install -g @openai/codex");
    if (agentId === "opencode") return windowsShellCommand("npm install -g opencode-windows-x64@latest || npm install -g opencode-windows-x64-baseline@latest || npm install -g opencode-ai@latest");
    if (agentId === "agy") return windowsPowerShellCommand("irm https://antigravity.google/cli/install.ps1 | iex");
  }

  if (agentId === "claude") return { executable: "sh", args: ["-lc", "curl -fsSL https://claude.ai/install.sh | bash"], shell: false };
  if (agentId === "codex") return { executable: "sh", args: ["-lc", "curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh"], shell: false };
  if (agentId === "opencode") return { executable: "sh", args: ["-lc", "curl -fsSL https://opencode.ai/install | bash"], shell: false };
  if (agentId === "agy") return { executable: "sh", args: ["-lc", "curl -fsSL https://antigravity.google/cli/install.sh | bash"], shell: false };
  return null;
}

function installSteps(agent) {
  const steps = [];
  if (process.platform === "win32" && ["claude", "codex", "opencode"].includes(agent.id) && !commandExists("npm")) {
    steps.push({
      label: "Node.js/npm dependency",
      command: windowsPowerShellCommand(windowsNodeInstallScript())
    });
  }
  if (process.platform === "win32" && agent.id === "claude" && !claudeShellDependencyInstalled()) {
    steps.push({
      label: "PowerShell 7 dependency for Claude Code",
      command: windowsPowerShellCommand(windowsPowerShell7InstallScript())
    });
  }
  const command = installCommand(agent.id);
  if (command && !commandExists(agent.id)) {
    steps.push({ label: `${agent.label} CLI`, command });
  }
  return steps;
}

function windowsNodeInstallScript() {
  return [
    "$ErrorActionPreference='Stop'",
    "if (Get-Command npm -ErrorAction SilentlyContinue) { npm -v; return }",
    "$versions=Invoke-RestMethod 'https://nodejs.org/dist/index.json'",
    "$release=$versions | Where-Object { $_.version -like 'v22.*' -and $_.files -contains 'win-x64-msi' } | Select-Object -First 1",
    "if (-not $release) { throw 'Could not find Node.js Windows x64 MSI.' }",
    "$version=$release.version",
    "$msi=\"node-$version-x64.msi\"",
    "$url=\"https://nodejs.org/dist/$version/$msi\"",
    "$tmp=Join-Path $env:TEMP $msi",
    "Invoke-WebRequest $url -UseBasicParsing -OutFile $tmp",
    "$proc=Start-Process msiexec.exe -Verb RunAs -ArgumentList @('/i', $tmp, '/qn', '/norestart') -Wait -PassThru",
    "if ($proc.ExitCode -ne 0) { throw \"Node.js installer exited with $($proc.ExitCode).\" }",
    "Remove-Item $tmp -Force -ErrorAction SilentlyContinue",
    "$env:PATH=\"${env:ProgramFiles}\\nodejs;$env:APPDATA\\npm;$env:PATH\"",
    "npm -v"
  ].join("; ");
}

function windowsPowerShell7InstallScript() {
  return [
    "$ErrorActionPreference='Stop'",
    "if (Get-Command pwsh -ErrorAction SilentlyContinue) { pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'; return }",
    "$release=Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'",
    "$asset=$release.assets | Where-Object { $_.name -match 'win-x64\\.msi$' -and $_.name -notmatch 'fxdependent' } | Select-Object -First 1",
    "if (-not $asset) { throw 'Could not find PowerShell 7 Windows x64 MSI.' }",
    "$tmp=Join-Path $env:TEMP $asset.name",
    "Invoke-WebRequest $asset.browser_download_url -UseBasicParsing -OutFile $tmp",
    "$proc=Start-Process msiexec.exe -Verb RunAs -ArgumentList @('/i', $tmp, '/qn', '/norestart') -Wait -PassThru",
    "if ($proc.ExitCode -ne 0) { throw \"PowerShell 7 installer exited with $($proc.ExitCode).\" }",
    "Remove-Item $tmp -Force -ErrorAction SilentlyContinue",
    "$env:PATH=\"${env:ProgramFiles}\\PowerShell\\7;$env:PATH\"",
    "pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'"
  ].join("; ");
}

function windowsShellCommand(command) {
  return {
    executable: process.env.ComSpec || path.join(process.env.SystemRoot || "C:\\Windows", "System32", "cmd.exe"),
    args: ["/d", "/s", "/c", command],
    shell: false
  };
}

function windowsPowerShellCommand(command) {
  return {
    executable: path.join(process.env.SystemRoot || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe"),
    args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
    shell: false
  };
}

function installAgent(webContents, agentId) {
  const agent = agents.find((item) => item.id === agentId);
  if (!agent) return { ok: false, message: "Unknown agent." };
  if (installingAgents.has(agent.id)) return { ok: false, message: `${agent.label} installer is already running.` };

  const steps = installSteps(agent);
  if (steps.length === 0 && commandExists(agent.id)) return { ok: true, alreadyInstalled: true, message: `${agent.label} CLI is already installed and ready.` };
  if (steps.length === 0) return { ok: false, message: `No automatic installer is configured for ${agent.label}.` };
  installingAgents.set(agent.id, { child: null });
  runInstallStep(webContents, agent, steps, 0);
  return { ok: true };
}

function prepareEditFile(filePath) {
  if (!filePath || process.platform !== "win32" || canWriteFile(filePath)) {
    return { filePath };
  }

  const dir = path.join(os.tmpdir(), "HTML Agent Editor");
  fs.mkdirSync(dir, { recursive: true });
  const parsed = path.parse(filePath);
  const target = path.join(dir, `${parsed.name}-${Date.now()}${parsed.ext || ".html"}`);
  fs.copyFileSync(filePath, target);
  return {
    filePath: target,
    originalPath: filePath,
    copied: true,
    message: `Windows blocked editing ${filePath}. Using a writable copy instead: ${target}`
  };
}

function canWriteFile(filePath) {
  try {
    const fd = fs.openSync(filePath, "r+");
    fs.closeSync(fd);
    return true;
  } catch {
    return false;
  }
}

function runInstallStep(webContents, agent, steps, index) {
  const step = steps[index];
  if (!step) {
    installingAgents.delete(agent.id);
    const installed = commandExists(agent.id);
    sendToWebContents(webContents, "agent-install-done", agent.id, {
      ok: installed,
      installed,
      message: installed
        ? `${agent.label} CLI installed and ready.`
        : `Could not install ${agent.label}. Open Thinking to inspect the installer output.`
    });
    return;
  }

  sendToWebContents(webContents, "agent-install-output", agent.id, `Installing ${step.label}...\n`);
  const child = childProcess.spawn(step.command.executable, step.command.args, {
    env: agentEnvironment(),
    windowsHide: true,
    shell: step.command.shell
  });
  installingAgents.set(agent.id, { child });

  const sendOutput = (data) => {
    sendToWebContents(webContents, "agent-install-output", agent.id, stripANSI(data.toString("utf8")));
  };

  child.stdout.on("data", sendOutput);
  child.stderr.on("data", sendOutput);
  child.on("error", (error) => {
    installingAgents.delete(agent.id);
    sendToWebContents(webContents, "agent-install-done", agent.id, {
      ok: false,
      message: `Could not start ${step.label}: ${error.message}`
    });
  });
  child.on("close", (code) => {
    if (code === 0) {
      runInstallStep(webContents, agent, steps, index + 1);
      return;
    }
    installingAgents.delete(agent.id);
    sendToWebContents(webContents, "agent-install-done", agent.id, {
      ok: false,
      code,
      message: `Could not install ${step.label}. Open Thinking to inspect the installer output.`
    });
  });
}

function dynamicModels(agentId) {
  if (agentId === "opencode") {
    const result = childProcess.spawnSync("opencode", ["models"], {
      encoding: "utf8",
      windowsHide: true,
      shell: process.platform === "win32",
      env: agentEnvironment()
    });
    if (result.status !== 0) return [];
    return stripANSI(result.stdout)
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.toLowerCase().startsWith("error:"))
      .map((line) => ({ label: line, id: line }));
  }

  if (agentId === "codex") {
    return readModelsCache(path.join(os.homedir(), ".codex", "models_cache.json"), (root) => {
      const models = Array.isArray(root.models) ? root.models : [];
      return models
        .filter((item) => item && item.slug)
        .map((item) => ({ label: item.display_name || item.slug, id: item.slug }));
    });
  }

  if (agentId === "claude") {
    return providerModels(["anthropic"], false);
  }

  if (agentId === "agy") {
    const result = childProcess.spawnSync("agy", ["models"], {
      encoding: "utf8",
      windowsHide: true,
      shell: process.platform === "win32",
      env: agentEnvironment()
    });
    if (result.status !== 0) return [];
    return stripANSI(result.stdout)
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.toLowerCase().startsWith("error:"))
      .map((line) => ({ label: line, id: line }));
  }

  return [];
}

function providerModels(providers, prefixIDs) {
  return readModelsCache(path.join(os.homedir(), ".hermes", "provider_models_cache.json"), (root) => {
    const names = providers || Object.keys(root).sort();
    const values = [];
    for (const provider of names) {
      const models = root[provider]?.models;
      if (!Array.isArray(models)) continue;
      for (const model of models) {
        const id = prefixIDs ? `${provider}/${model}` : model;
        values.push({ label: id, id });
      }
    }
    return values;
  });
}

function readModelsCache(filePath, mapper) {
  try {
    return mapper(JSON.parse(fs.readFileSync(filePath, "utf8")));
  } catch {
    return [];
  }
}

function authorizationIssue(agent) {
  if (!commandExists(agent.id)) {
    return {
      title: `${agent.label} CLI not found`,
      message: `Install ${agent.label}, then reopen HTML Agent Editor or make sure the CLI is available in PATH.`,
      actionCommand: null
    };
  }

  if (agent.id === "claude") {
    const hasKey = Boolean(process.env.ANTHROPIC_API_KEY);
    const hasCredential = [
      path.join(os.homedir(), ".claude", ".credentials.json"),
      path.join(os.homedir(), ".claude.json")
    ].some((file) => fs.existsSync(file));
    if (hasKey || hasCredential) return null;
    return {
      title: "Authorize Claude",
      message: "Claude needs an authorized subscription/account before HTML Agent Editor can use it. Run Claude once and complete the sign-in flow.",
      actionCommand: agent.loginCommand
    };
  }

  if (agent.id === "codex") {
    const result = childProcess.spawnSync("codex", ["login", "status"], {
      encoding: "utf8",
      windowsHide: true,
      shell: process.platform === "win32",
      env: agentEnvironment()
    });
    const output = `${result.stdout || ""}\n${result.stderr || ""}`;
    if (result.status === 0 && !authOutputMeansMissing(output)) return null;
    return {
      title: "Authorize Codex",
      message: "Codex needs an authorized ChatGPT subscription/account before HTML Agent Editor can use it.",
      actionCommand: agent.loginCommand
    };
  }

  return null;
}

function runAgent(webContents, request) {
  const id = webContents.id;
  if (runningProcesses.has(id)) {
    return { ok: false, message: "Agent is still working. Wait for this run to finish." };
  }

  const agent = agents.find((item) => item.id === request.agentId);
  if (!agent || !request.filePath || !request.prompt) {
    return { ok: false, message: "Missing agent, file, or prompt." };
  }

  const issue = authorizationIssue(agent);
  if (issue) {
    return { ok: false, issue };
  }

  const dir = path.dirname(request.filePath);
  const beforeContent = request.mode === "chat" || request.mode === "edit" ? readFileContent(request.filePath) : null;
  const previousModified = modifiedTime(request.filePath);
  // The renderer decides resume (it tracks per-window session state). Claude needs a
  // concrete session id, kept here keyed by window + file, and shared by both chat and
  // edit so switching modes continues the same session.
  const priorSession = claudeSessions.get(id);
  let claudeSessionId = null;
  let opencodeSessionId = null;
  let resume = false;
  if (agent.id === "claude") {
    if (request.resume && priorSession && priorSession.filePath === request.filePath) {
      resume = true;
      claudeSessionId = priorSession.id;
    } else {
      claudeSessionId = crypto.randomUUID();
    }
  } else if (agent.id === "opencode") {
    // opencode hands out the id, so it can only be reused once a run has reported one.
    const prior = opencodeSessions.get(id);
    if (request.resume && prior && prior.filePath === request.filePath) {
      resume = true;
      opencodeSessionId = prior.id;
    }
  } else {
    resume = Boolean(request.resume);
  }
  const command = agentProcess(agent.id, request.modelId || "", request.prompt, request.filePath, dir, request.mode, resume, claudeSessionId, opencodeSessionId);
  const child = childProcess.spawn(command.executable, command.args, {
    cwd: dir,
    env: agentEnvironment(),
    windowsHide: true,
    shell: command.shell
  });

  let output = "";
  const eventStream = agent.id === "opencode" && !process.env.HTML_AGENT_EDITOR_AGENT_COMMAND;
  let lineBuffer = "";
  let streamedAnswer = "";
  const streamedErrors = [];
  runningProcesses.set(id, child);

  const emit = (text) => {
    if (text && !webContents.isDestroyed()) webContents.send("agent-output", text + "\n");
  };

  const consume = (line) => {
    const parsed = parseOpencodeEvent(line);
    if (parsed.sessionID) opencodeSessionId = parsed.sessionID;
    if (parsed.kind === "answer") streamedAnswer += parsed.text;
    if (parsed.kind === "failure") streamedErrors.push(parsed.text);
    if (parsed.kind !== "ignored") emit(parsed.text);
  };

  const onData = (data) => {
    const text = stripANSI(data.toString("utf8"));
    output += text;
    if (!eventStream) {
      if (!webContents.isDestroyed()) webContents.send("agent-output", text);
      return;
    }
    // Chunks split mid-line, so only complete lines can be parsed as events.
    lineBuffer += text;
    let newline = lineBuffer.indexOf("\n");
    while (newline !== -1) {
      consume(lineBuffer.slice(0, newline));
      lineBuffer = lineBuffer.slice(newline + 1);
      newline = lineBuffer.indexOf("\n");
    }
  };

  child.stdout.on("data", onData);
  child.stderr.on("data", onData);
  child.on("error", (error) => {
    runningProcesses.delete(id);
    if (!webContents.isDestroyed()) {
      webContents.send("agent-done", {
        code: -1,
        changed: false,
        message: `Could not start ${agent.label}: ${error.message}`
      });
    }
  });
  child.on("close", (code) => {
    runningProcesses.delete(id);
    // The final line arrives without a trailing newline, so it is still buffered.
    if (eventStream && lineBuffer.trim()) {
      consume(lineBuffer);
      lineBuffer = "";
    }
    let changed = modifiedTime(request.filePath) !== previousModified;
    let restored = false;
    if (changed && request.mode === "chat" && beforeContent !== null) {
      try {
        fs.writeFileSync(request.filePath, beforeContent);
        changed = false;
        restored = true;
      } catch {
        restored = false;
      }
    }
    if (changed && request.mode === "edit" && beforeContent !== null) {
      const stack = editUndoStacks.get(id) || [];
      stack.push({ filePath: request.filePath, content: beforeContent });
      editUndoStacks.set(id, stack);
    }
    if (code === 0 && agent.id === "claude" && claudeSessionId) {
      claudeSessions.set(id, { id: claudeSessionId, filePath: request.filePath });
    }
    if (code === 0 && agent.id === "opencode" && opencodeSessionId) {
      opencodeSessions.set(id, { id: opencodeSessionId, filePath: request.filePath });
    }
    const issue = authOutputMeansMissing(output)
      ? {
          title: `Authorize ${agent.label}`,
          message: `${agent.label} reported an authorization problem. Authorize with your subscription/account, then run the request again.`,
          actionCommand: agent.loginCommand
        }
      : null;
    if (!webContents.isDestroyed()) {
      webContents.send("agent-done", {
        code,
        changed,
        restored,
        issue,
        answer: eventStream ? streamedAnswer.trim() : null,
        errorMessage: streamedErrors.length ? streamedErrors.join("\n") : null,
        sessionStarted: Boolean(opencodeSessionId)
      });
    }
  });

  if (command.stdin) {
    child.stdin.write(command.stdin);
    child.stdin.end();
  }

  setTimeout(() => {
    if (runningProcesses.get(id) === child && !webContents.isDestroyed()) {
      webContents.send("agent-still-running", agent.label);
    }
  }, 6000);

  return { ok: true };
}

function rewindLastEdit(id, filePath) {
  const stack = editUndoStacks.get(id);
  if (!stack || stack.length === 0) return { ok: false, message: "No edit to rewind yet." };
  const snapshot = stack[stack.length - 1];
  if (filePath && snapshot.filePath !== filePath) {
    return { ok: false, message: "The last edit belongs to a different file." };
  }
  try {
    fs.writeFileSync(snapshot.filePath, snapshot.content);
    stack.pop();
    if (stack.length === 0) editUndoStacks.delete(id);
    return { ok: true, filePath: snapshot.filePath, remaining: stack.length };
  } catch (error) {
    return { ok: false, message: `Could not rewind last edit: ${error.message}` };
  }
}

function stopAgentProcess(id) {
  const child = runningProcesses.get(id);
  if (!child) return false;
  runningProcesses.delete(id);
  child.kill();
  return true;
}

// opencode --format json emits one JSON event per line. Only `text` parts are the model
// speaking; everything else is machinery. Feeding the raw stream straight to the panel is
// what let a tool's HTTP error page surface as the agent's answer.
function parseOpencodeEvent(line) {
  const trimmed = line.trim();
  if (!trimmed) return { kind: "ignored", text: "", sessionID: null };
  let event;
  try {
    event = JSON.parse(trimmed);
  } catch {
    // Anything opencode writes outside the event stream (a crash, a shell error) is still
    // worth showing, but never as the answer.
    return { kind: "process", text: trimmed, sessionID: null };
  }
  const sessionID = event.sessionID || null;
  const part = event.part || {};
  switch (event.type) {
    case "text":
      return { kind: part.text ? "answer" : "ignored", text: part.text || "", sessionID };
    case "reasoning":
      return { kind: part.text ? "process" : "ignored", text: part.text || "", sessionID };
    case "tool_use": {
      // A failed tool is machinery, not the answer -- its error text is exactly what used
      // to be rendered as the agent speaking.
      const tool = part.tool || "tool";
      const state = part.state || {};
      const status = state.status || "running";
      const text = state.error ? `${tool} (${status}): ${state.error}` : `${tool} (${status})`;
      return { kind: "process", text, sessionID };
    }
    case "error": {
      const error = event.error || {};
      const message = (error.data && error.data.message) || error.name || "The agent reported an error.";
      return { kind: "failure", text: message, sessionID };
    }
    default:
      return { kind: "ignored", text: "", sessionID };
  }
}

function agentProcess(agentId, modelId, prompt, filePath, dir, mode, resume, claudeSessionId, opencodeSessionId) {
  if (process.env.HTML_AGENT_EDITOR_AGENT_COMMAND) {
    return {
      executable: process.platform === "win32" ? "cmd.exe" : "sh",
      args: process.platform === "win32"
        ? ["/d", "/s", "/c", `${process.env.HTML_AGENT_EDITOR_AGENT_COMMAND} ${cmdQuote(prompt)}`]
        : ["-lc", `${process.env.HTML_AGENT_EDITOR_AGENT_COMMAND} ${shellQuote(prompt)}`],
      shell: false,
      stdin: null
    };
  }

  const modelArgs = modelId ? ["--model", modelId] : [];
  const contFlag = resume ? ["-c"] : [];
  if (agentId === "opencode") {
    // -c continues whatever session ran last on this machine, so a second window -- or an
    // opencode run in a terminal -- steals the turn. Resume the id this window actually
    // started instead. JSON gives us that id, plus a structured stream so tool logs and
    // HTTP errors can't be mistaken for the answer.
    const sessionArgs = resume && opencodeSessionId ? ["-s", opencodeSessionId] : [];
    return {
      executable: "opencode",
      args: ["run", "--format", "json", ...sessionArgs, ...modelArgs, prompt, "--auto", "--dir", dir, "--file", filePath],
      shell: process.platform === "win32",
      stdin: null
    };
  }
  if (agentId === "claude") {
    // Reuse a server-side session on follow-up turns so the file and prior
    // conversation are not re-sent as prompt text. Deterministic per-window
    // session id avoids cross-window collisions from --continue. Both chat and
    // edit share the session so switching modes stays continuous.
    const sessionArgs = resume && claudeSessionId
      ? ["--resume", claudeSessionId]
      : ["--session-id", claudeSessionId];
    return {
      executable: "claude",
      args: ["--print", ...sessionArgs, ...modelArgs, "--dangerously-skip-permissions", "--add-dir", dir],
      shell: process.platform === "win32",
      stdin: prompt
    };
  }
  if (agentId === "codex") {
    // resume inherits the original session's cwd/sandbox; only a subset of flags is accepted.
    // Persistent full-access session shared by chat and edit so either mode can resume
    // it. Chat safety comes from the post-run file restore, not the sandbox.
    const codexArgs = resume
      ? ["-a", "never", ...modelArgs, "exec", "resume", "--last", "--skip-git-repo-check", "-"]
      : [
          "-a", "never", ...modelArgs, "exec", "--cd", dir,
          "--sandbox", "danger-full-access",
          "--skip-git-repo-check", "--color", "never", "-"
        ];
    return {
      executable: "codex",
      args: codexArgs,
      shell: process.platform === "win32",
      stdin: prompt
    };
  }
  if (agentId === "agy") {
    return {
      executable: "agy",
      args: ["--dangerously-skip-permissions", ...contFlag, ...modelArgs, "-p", prompt],
      shell: process.platform === "win32",
      stdin: null
    };
  }
  return { executable: agentId, args: [prompt], shell: process.platform === "win32", stdin: null };
}

function agentEnvironment() {
  const env = { ...process.env };
  const additions = [
    path.join(env.ProgramFiles || "C:\\Program Files", "nodejs"),
    path.join(env.ProgramFiles || "C:\\Program Files", "PowerShell", "7"),
    path.join(env.APPDATA || path.join(os.homedir(), "AppData", "Roaming"), "npm"),
    path.join(env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "agy", "bin"),
    path.join(os.homedir(), ".claude", "local"),
    path.join(os.homedir(), ".codex", "bin"),
    path.join(os.homedir(), ".opencode", "bin"),
    path.join(os.homedir(), ".hermes", "bin"),
    path.join(os.homedir(), ".antigravity", "bin"),
    path.join(os.homedir(), ".local", "bin")
  ];
  env.PATH = [...additions, env.PATH || ""].join(path.delimiter);
  const bashPath = gitBashPath(env);
  if (bashPath && !env.CLAUDE_CODE_GIT_BASH_PATH) {
    env.CLAUDE_CODE_GIT_BASH_PATH = bashPath;
  }
  return env;
}

async function checkForUpdates() {
  const currentVersion = app.getVersion();
  const release = await getJson(`https://api.github.com/repos/${repoOwner}/${repoName}/releases/latest`);
  const latestVersion = release.tag_name || "";
  if (!isNewerVersion(latestVersion, currentVersion)) {
    return { available: false, currentVersion, latestVersion };
  }

  const asset = preferredUpdateAsset(release.assets || []);
  return {
    available: true,
    currentVersion,
    latestVersion,
    pageURL: release.html_url,
    assetName: asset?.name || null,
    assetURL: asset?.browser_download_url || null
  };
}

async function installUpdate(update) {
  if (!update?.assetURL) {
    if (update?.pageURL) await shell.openExternal(update.pageURL);
    return { ok: false, message: "No matching release asset was found." };
  }

  const updatesDir = path.join(app.getPath("userData"), "updates");
  fs.mkdirSync(updatesDir, { recursive: true });
  const assetName = path.basename(new URL(update.assetURL).pathname);
  const target = path.join(updatesDir, assetName || "HTML-Agent-Editor-Update.exe");
  await downloadFile(update.assetURL, target);
  const openError = await shell.openPath(target);
  if (openError) return { ok: false, message: openError };
  app.quit();
  return { ok: true, path: target };
}

function preferredUpdateAsset(assets) {
  const arch = process.arch === "arm64" ? "arm64" : "x64";
  const names = assets.map((asset) => ({ asset, name: String(asset.name || "").toLowerCase() }));
  if (process.platform === "win32") {
    return names.find((item) => item.name.includes("windows") && item.name.includes(arch) && item.name.endsWith(".exe"))?.asset
      || names.find((item) => item.name.includes("windows") && item.name.includes(arch) && item.name.endsWith(".zip"))?.asset
      || names.find((item) => item.name.includes("windows") && item.name.endsWith(".exe"))?.asset
      || names.find((item) => item.name.includes("windows"))?.asset;
  }
  if (process.platform === "darwin") {
    return names.find((item) => item.name.includes("macos") && item.name.includes(arch) && item.name.endsWith(".zip"))?.asset
      || names.find((item) => item.name.includes("macos"))?.asset;
  }
  return null;
}

function getJson(url) {
  return new Promise((resolve, reject) => {
    httpsGet(url, (res) => {
      let body = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => { body += chunk; });
      res.on("end", () => {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(`GitHub returned ${res.statusCode}`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(error);
        }
      });
    }).on("error", reject);
  });
}

function downloadFile(url, target) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(target);
    httpsGet(url, (res) => {
      if (res.statusCode < 200 || res.statusCode >= 300) {
        file.close(() => fs.rm(target, { force: true }, () => {}));
        reject(new Error(`Download returned ${res.statusCode}`));
        return;
      }
      res.pipe(file);
      file.on("finish", () => file.close(resolve));
    }).on("error", (error) => {
      file.close(() => fs.rm(target, { force: true }, () => {}));
      reject(error);
    });
  });
}

function httpsGet(url, callback) {
  return https.get(url, {
    headers: {
      "User-Agent": "HTML Agent Editor",
      "Accept": "application/vnd.github+json"
    }
  }, (res) => {
    if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
      res.resume();
      httpsGet(new URL(res.headers.location, url).toString(), callback);
      return;
    }
    callback(res);
  });
}

function isNewerVersion(candidate, current) {
  const left = versionParts(candidate);
  const right = versionParts(current);
  const count = Math.max(left.length, right.length);
  for (let index = 0; index < count; index += 1) {
    const a = left[index] || 0;
    const b = right[index] || 0;
    if (a !== b) return a > b;
  }
  return false;
}

function versionParts(value) {
  return String(value || "")
    .replace(/^[vV]/, "")
    .split(/[^0-9]+/)
    .filter(Boolean)
    .map((item) => Number(item) || 0);
}

function sendToWebContents(webContents, channel, ...args) {
  if (webContents && !webContents.isDestroyed()) {
    webContents.send(channel, ...args);
  }
}

function modifiedTime(filePath) {
  try {
    return fs.statSync(filePath).mtimeMs;
  } catch {
    return null;
  }
}

function readFileContent(filePath) {
  try {
    return fs.readFileSync(filePath);
  } catch {
    return null;
  }
}

function stripANSI(value) {
  return value
    .replace(/\x1B\[[0-9;:?]*[ -/]*[@-~]/g, "")
    .replace(/\x1B\].*?(\x07|\x1B\\)/gs, "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n");
}

function authOutputMeansMissing(output) {
  const text = output.toLowerCase();
  return [
    "not logged in",
    "not authenticated",
    "no credentials",
    "login required",
    "authentication required",
    "unauthorized",
    "api key",
    "subscription"
  ].some((marker) => text.includes(marker));
}

function openAuthorizationTerminal(command) {
  if (!command) return;
  if (process.platform === "win32") {
    const scriptPath = path.join(os.tmpdir(), `html-agent-editor-auth-${Date.now()}.cmd`);
    fs.writeFileSync(scriptPath, windowsAuthorizationScript(command), "utf8");
    const cmd = process.env.ComSpec || path.join(process.env.SystemRoot || "C:\\Windows", "System32", "cmd.exe");
    childProcess.spawn(cmd, ["/c", "start", "HTML Agent Editor Auth", cmd, "/k", scriptPath], {
      detached: true,
      stdio: "ignore",
      windowsHide: false
    }).unref();
    return;
  }
  if (process.platform === "darwin") {
    const script = `tell application "Terminal"\nactivate\ndo script ${appleScriptString(command)}\nend tell`;
    childProcess.spawn("osascript", ["-e", script], { detached: true, stdio: "ignore" }).unref();
    return;
  }
  childProcess.spawn("sh", ["-lc", `x-terminal-emulator -e ${shellQuote(command)} || ${command}`], {
    detached: true,
    stdio: "ignore"
  }).unref();
}

function windowsAuthorizationScript(command) {
  const env = agentEnvironment();
  return [
    "@echo off",
    `set "PATH=${env.PATH}"`,
    "cd /d %USERPROFILE%",
    command
  ].join("\r\n");
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function cmdQuote(value) {
  return `"${String(value).replace(/"/g, '""')}"`;
}

function appleScriptString(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}
