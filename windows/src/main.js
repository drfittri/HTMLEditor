const { app, BrowserWindow, Menu, dialog, ipcMain, shell } = require("electron");
const { pathToFileURL } = require("url");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const appName = "HTML Agent Editor";
const watchers = new Map();
const runningProcesses = new Map();
const installingAgents = new Map();

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
    id: "hermes",
    label: "Hermes",
    loginCommand: "hermes model",
    models: [
      { label: "Default", id: "" },
      { label: "anthropic/claude-fable-5", id: "anthropic/claude-fable-5" },
      { label: "anthropic/claude-sonnet-4-6", id: "anthropic/claude-sonnet-4-6" },
      { label: "anthropic/claude-haiku-4-5-20251001", id: "anthropic/claude-haiku-4-5-20251001" },
      { label: "copilot/gpt-5.4", id: "copilot/gpt-5.4" },
      { label: "copilot/gpt-5.4-mini", id: "copilot/gpt-5.4-mini" },
      { label: "opencode-go/minimax-m3", id: "opencode-go/minimax-m3" }
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

  win.webContents.on("did-finish-load", () => {
    if (win.initialFilePath) {
      win.webContents.send("open-file-path", win.initialFilePath);
    }
  });

  win.on("closed", () => {
    stopWatching(win.webContents.id);
    stopAgentProcess(win.webContents.id);
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

ipcMain.handle("send-agent", async (event, request) => {
  return runAgent(event.sender, request);
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
  const checker = process.platform === "win32" ? "where.exe" : "sh";
  const args = process.platform === "win32" ? [command] : ["-lc", `command -v ${shellQuote(command)}`];
  const result = childProcess.spawnSync(checker, args, {
    encoding: "utf8",
    windowsHide: true,
    env: agentEnvironment()
  });
  return result.status === 0;
}

function agentStatus(agentId) {
  const agent = agents.find((item) => item.id === agentId);
  if (!agent) return { installed: false, ready: false, message: "Unknown agent." };
  const installed = commandExists(agent.id);
  return {
    installed,
    ready: installed,
    message: installed ? `${agent.label} CLI ready.` : `${agent.label} CLI not installed.`
  };
}

function installCommand(agentId) {
  if (process.platform === "win32") {
    if (agentId === "claude") return { executable: "cmd.exe", args: ["/d", "/s", "/c", "npm install -g @anthropic-ai/claude-code"], shell: false };
    if (agentId === "codex") return { executable: "cmd.exe", args: ["/d", "/s", "/c", "npm install -g @openai/codex"], shell: false };
    if (agentId === "opencode") return { executable: "cmd.exe", args: ["/d", "/s", "/c", "npm install -g opencode-ai@latest"], shell: false };
    if (agentId === "hermes") {
      return {
        executable: "powershell.exe",
        args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "iex (irm https://hermes-agent.nousresearch.com/install.ps1)"],
        shell: false
      };
    }
  }

  if (agentId === "claude") return { executable: "sh", args: ["-lc", "curl -fsSL https://claude.ai/install.sh | bash"], shell: false };
  if (agentId === "codex") return { executable: "sh", args: ["-lc", "curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh"], shell: false };
  if (agentId === "opencode") return { executable: "sh", args: ["-lc", "curl -fsSL https://opencode.ai/install | bash"], shell: false };
  if (agentId === "hermes") return { executable: "sh", args: ["-lc", "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"], shell: false };
  return null;
}

function installAgent(webContents, agentId) {
  const agent = agents.find((item) => item.id === agentId);
  if (!agent) return { ok: false, message: "Unknown agent." };
  if (commandExists(agent.id)) return { ok: true, alreadyInstalled: true };
  if (installingAgents.has(agent.id)) return { ok: false, message: `${agent.label} installer is already running.` };

  const command = installCommand(agent.id);
  if (!command) return { ok: false, message: `No automatic installer is configured for ${agent.label}.` };

  const child = childProcess.spawn(command.executable, command.args, {
    env: agentEnvironment(),
    windowsHide: true,
    shell: command.shell
  });
  installingAgents.set(agent.id, child);

  const sendOutput = (data) => {
    if (!webContents.isDestroyed()) {
      webContents.send("agent-install-output", agent.id, stripANSI(data.toString("utf8")));
    }
  };

  child.stdout.on("data", sendOutput);
  child.stderr.on("data", sendOutput);
  child.on("error", (error) => {
    installingAgents.delete(agent.id);
    if (!webContents.isDestroyed()) {
      webContents.send("agent-install-done", agent.id, {
        ok: false,
        message: `Could not start ${agent.label} installer: ${error.message}`
      });
    }
  });
  child.on("close", (code) => {
    installingAgents.delete(agent.id);
    const installed = commandExists(agent.id);
    if (!webContents.isDestroyed()) {
      webContents.send("agent-install-done", agent.id, {
        ok: code === 0 && installed,
        code,
        installed,
        message: installed
          ? `${agent.label} CLI installed and ready.`
          : `Could not install ${agent.label}. Open Work to inspect the installer output.`
      });
    }
  });

  return { ok: true };
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

  if (agentId === "hermes") {
    return providerModels(null, true);
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
  const previousModified = modifiedTime(request.filePath);
  const command = agentProcess(agent.id, request.modelId || "", request.prompt, request.filePath, dir);
  const child = childProcess.spawn(command.executable, command.args, {
    cwd: dir,
    env: agentEnvironment(),
    windowsHide: true,
    shell: command.shell
  });

  let output = "";
  runningProcesses.set(id, child);

  const onData = (data) => {
    const text = stripANSI(data.toString("utf8"));
    output += text;
    if (!webContents.isDestroyed()) webContents.send("agent-output", text);
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
    const changed = modifiedTime(request.filePath) !== previousModified;
    const issue = authOutputMeansMissing(output)
      ? {
          title: `Authorize ${agent.label}`,
          message: `${agent.label} reported an authorization problem. Authorize with your subscription/account, then run the request again.`,
          actionCommand: agent.loginCommand
        }
      : null;
    if (!webContents.isDestroyed()) {
      webContents.send("agent-done", { code, changed, issue });
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

function stopAgentProcess(id) {
  const child = runningProcesses.get(id);
  if (!child) return false;
  runningProcesses.delete(id);
  child.kill();
  return true;
}

function agentProcess(agentId, modelId, prompt, filePath, dir) {
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
  if (agentId === "opencode") {
    return {
      executable: "opencode",
      args: ["run", ...modelArgs, prompt, "--dangerously-skip-permissions", "--dir", dir, "--file", filePath],
      shell: process.platform === "win32",
      stdin: null
    };
  }
  if (agentId === "claude") {
    return {
      executable: "claude",
      args: ["--print", ...modelArgs, "--dangerously-skip-permissions", "--add-dir", dir],
      shell: process.platform === "win32",
      stdin: prompt
    };
  }
  if (agentId === "codex") {
    return {
      executable: "codex",
      args: [
        "-a",
        "never",
        ...modelArgs,
        "exec",
        "--cd",
        dir,
        "--sandbox",
        "workspace-write",
        "--skip-git-repo-check",
        "--color",
        "never",
        "-"
      ],
      shell: process.platform === "win32",
      stdin: prompt
    };
  }
  if (agentId === "hermes") {
    return {
      executable: "hermes",
      args: ["--oneshot", prompt, ...modelArgs],
      shell: process.platform === "win32",
      stdin: null
    };
  }
  return { executable: agentId, args: [prompt], shell: process.platform === "win32", stdin: null };
}

function agentEnvironment() {
  const env = { ...process.env };
  const additions = [
    path.join(os.homedir(), ".claude", "local"),
    path.join(os.homedir(), ".codex", "bin"),
    path.join(os.homedir(), ".opencode", "bin"),
    path.join(os.homedir(), ".hermes", "bin"),
    path.join(os.homedir(), ".local", "bin")
  ];
  env.PATH = [...additions, env.PATH || ""].join(path.delimiter);
  return env;
}

function modifiedTime(filePath) {
  try {
    return fs.statSync(filePath).mtimeMs;
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
    childProcess.spawn("cmd.exe", ["/c", "start", "cmd.exe", "/k", command], {
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

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function cmdQuote(value) {
  return `"${String(value).replace(/"/g, '""')}"`;
}

function appleScriptString(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}
