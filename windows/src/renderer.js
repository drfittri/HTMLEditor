const state = {
  filePath: null,
  fileUrl: null,
  agents: [],
  activeAgentId: null,
  modelId: "",
  pickerEnabled: true,
  showWork: false,
  running: false,
  installingAgentId: null,
  dark: localStorage.getItem("darkMode") !== "false",
  selectedElements: [],
  selectedElementContext: null,
  chatMessages: [],
  panelWidth: Number(localStorage.getItem("panelWidth") || 360)
};

const elements = {
  body: document.body,
  mainGrid: document.getElementById("mainGrid"),
  previewPane: document.getElementById("previewPane"),
  preview: document.getElementById("preview"),
  emptyState: document.getElementById("emptyState"),
  reloadBtn: document.getElementById("reloadBtn"),
  panelBtn: document.getElementById("panelBtn"),
  browserBtn: document.getElementById("browserBtn"),
  openBtn: document.getElementById("openBtn"),
  themeBtn: document.getElementById("themeBtn"),
  divider: document.getElementById("divider"),
  sidePanel: document.getElementById("sidePanel"),
  agentSelect: document.getElementById("agentSelect"),
  agentStatus: document.getElementById("agentStatus"),
  modelSelect: document.getElementById("modelSelect"),
  workBtn: document.getElementById("workBtn"),
  pickerBtn: document.getElementById("pickerBtn"),
  selectedTitle: document.getElementById("selectedTitle"),
  selectedDetail: document.getElementById("selectedDetail"),
  chatLog: document.getElementById("chatLog"),
  composer: document.getElementById("composer"),
  promptInput: document.getElementById("promptInput"),
  sendBtn: document.getElementById("sendBtn"),
  stopBtn: document.getElementById("stopBtn")
};

init();

async function init() {
  elements.preview.setAttribute("preload", window.htmlAgent.previewPreloadPath());
  state.agents = await window.htmlAgent.getAgents();
  renderAgents();
  applyTheme();
  applyPanelWidth();
  updateFileControls();
  renderChat();

  elements.openBtn.addEventListener("click", openFileDialog);
  elements.reloadBtn.addEventListener("click", reloadPreview);
  elements.browserBtn.addEventListener("click", openInBrowser);
  elements.themeBtn.addEventListener("click", toggleTheme);
  elements.panelBtn.addEventListener("click", togglePanel);
  elements.workBtn.addEventListener("click", toggleWork);
  elements.pickerBtn.addEventListener("click", togglePicker);
  elements.agentSelect.addEventListener("change", () => selectAgent(elements.agentSelect.value));
  elements.modelSelect.addEventListener("change", () => {
    state.modelId = elements.modelSelect.value;
    if (state.activeAgentId) localStorage.setItem(modelStorageKey(state.activeAgentId), state.modelId);
  });
  elements.composer.addEventListener("submit", sendPrompt);
  elements.stopBtn.addEventListener("click", stopAgent);

  elements.preview.addEventListener("ipc-message", (event) => {
    if (event.channel === "element-picked") updateSelectedElements(event.args[0] || []);
  });
  elements.preview.addEventListener("dom-ready", () => {
    updatePickerState();
    if (state.dark) {
      elements.preview.executeJavaScript("document.documentElement.style.colorScheme='dark';", true).catch(() => {});
    }
  });
  elements.preview.addEventListener("new-window", (event) => {
    event.preventDefault();
    if (event.url) window.open(event.url);
  });

  wireDrop();
  wireResize();
  wireIpc();
}

function wireIpc() {
  window.htmlAgent.onOpenFilePath((filePath) => loadFile(filePath));
  window.htmlAgent.onMenuOpenFile(openFileDialog);
  window.htmlAgent.onMenuReload(reloadPreview);
  window.htmlAgent.onMenuOpenBrowser(openInBrowser);
  window.htmlAgent.onMenuToggleDark(toggleTheme);
  window.htmlAgent.onMenuClearChat(clearChat);
  window.htmlAgent.onMenuAgent((agentId) => selectAgent(agentId));
  window.htmlAgent.onFileChanged((filePath) => {
    if (filePath === state.filePath) reloadPreview();
  });
  window.htmlAgent.onAgentOutput((text) => appendProcess(text));
  window.htmlAgent.onAgentStillRunning((label) => appendChat(`${label}: still running...`, "status"));
  window.htmlAgent.onAgentDone((result) => finishAgent(result));
  window.htmlAgent.onAgentInstallOutput((agentId, text) => {
    if (agentId === state.installingAgentId) appendProcess(text);
  });
  window.htmlAgent.onAgentInstallDone((agentId, result) => finishAgentInstall(agentId, result));
}

function wireDrop() {
  elements.previewPane.addEventListener("dragover", (event) => {
    event.preventDefault();
    elements.previewPane.classList.add("dragging");
  });
  elements.previewPane.addEventListener("dragleave", () => {
    elements.previewPane.classList.remove("dragging");
  });
  elements.previewPane.addEventListener("drop", (event) => {
    event.preventDefault();
    elements.previewPane.classList.remove("dragging");
    const file = Array.from(event.dataTransfer.files || [])[0];
    if (file?.path && /\.(html?|xhtml)$/i.test(file.path)) loadFile(file.path);
  });
}

function wireResize() {
  let resizing = false;
  elements.divider.addEventListener("pointerdown", (event) => {
    resizing = true;
    elements.divider.setPointerCapture(event.pointerId);
  });
  elements.divider.addEventListener("pointermove", (event) => {
    if (!resizing || elements.mainGrid.classList.contains("panel-collapsed")) return;
    const width = Math.min(760, Math.max(320, window.innerWidth - event.clientX));
    state.panelWidth = width;
    localStorage.setItem("panelWidth", String(width));
    applyPanelWidth();
  });
  elements.divider.addEventListener("pointerup", () => {
    resizing = false;
  });
}

function applyPanelWidth() {
  const width = Math.min(760, Math.max(320, state.panelWidth));
  elements.mainGrid.style.gridTemplateColumns = elements.mainGrid.classList.contains("panel-collapsed")
    ? "minmax(360px, 1fr) 0 0"
    : `minmax(360px, 1fr) 1px ${width}px`;
}

async function openFileDialog() {
  const filePath = await window.htmlAgent.openFileDialog();
  if (filePath) loadFile(filePath);
}

async function loadFile(filePath) {
  state.filePath = filePath;
  state.fileUrl = await window.htmlAgent.fileUrl(filePath);
  elements.preview.src = state.fileUrl;
  document.title = `HTML Agent Editor - ${baseName(filePath)}`;
  elements.emptyState.classList.add("hidden");
  await window.htmlAgent.watchFile(filePath);
  resetChat();
  clearSelection();
  if (!state.activeAgentId) {
    const defaultAgent = state.agents.find((agent) => agent.id === "opencode") || state.agents[0];
    if (defaultAgent) await selectAgent(defaultAgent.id);
  } else {
    await selectAgent(state.activeAgentId);
  }
  updateFileControls();
  elements.promptInput.focus();
}

function reloadPreview() {
  if (!state.filePath) {
    appendChat("Open an HTML file first.", "error");
    return;
  }
  elements.preview.reloadIgnoringCache();
}

async function openInBrowser() {
  if (!state.filePath) {
    appendChat("Open an HTML file first.", "error");
    return;
  }
  await window.htmlAgent.openInBrowser(state.filePath);
}

function toggleTheme() {
  state.dark = !state.dark;
  localStorage.setItem("darkMode", state.dark ? "true" : "false");
  applyTheme();
}

function applyTheme() {
  elements.body.classList.toggle("light", !state.dark);
  elements.themeBtn.textContent = state.dark ? "Light" : "Dark";
}

function togglePanel() {
  elements.mainGrid.classList.toggle("panel-collapsed");
  elements.panelBtn.classList.toggle("is-active", !elements.mainGrid.classList.contains("panel-collapsed"));
  if (elements.mainGrid.classList.contains("panel-collapsed")) {
    state.pickerEnabled = false;
    clearSelection();
  }
  applyPanelWidth();
}

function toggleWork() {
  state.showWork = !state.showWork;
  elements.workBtn.textContent = state.showWork ? "Hide" : "Work";
  elements.workBtn.classList.toggle("is-active", state.showWork);
  renderChat();
}

function togglePicker() {
  state.pickerEnabled = !state.pickerEnabled;
  updatePickerState();
}

function updatePickerState() {
  elements.pickerBtn.classList.toggle("is-active", state.pickerEnabled);
  elements.preview.executeJavaScript(
    `document.dispatchEvent(new CustomEvent('html-agent-set-picker-enabled',{detail:{enabled:${state.pickerEnabled ? "true" : "false"}}}));`,
    true
  ).catch(() => {});
}

function clearSelection() {
  state.selectedElements = [];
  state.selectedElementContext = null;
  elements.selectedTitle.textContent = "No element selected";
  elements.selectedDetail.textContent = "Click any visible element in the preview. The selected DOM context will be sent with your next message.";
  elements.preview.executeJavaScript(
    "document.dispatchEvent(new CustomEvent('html-agent-clear-selection'));",
    true
  ).catch(() => {});
}

function updateSelectedElements(items) {
  state.selectedElements = items.map((item) => {
    const tag = item.tag || "element";
    const className = item.className || "";
    let label = `<${tag}>`;
    if (item.id) label += `#${item.id}`;
    if (className) label += `.${className.split(/\s+/).slice(0, 2).join(".")}`;
    return {
      label,
      selector: item.selector || "",
      text: item.text || "",
      html: item.outerHTML || ""
    };
  });
  updateSelectedSummary();
}

function updateSelectedSummary() {
  if (state.selectedElements.length === 0) {
    state.selectedElementContext = null;
    elements.selectedTitle.textContent = "No element selected";
    elements.selectedDetail.textContent = "Click any visible element in the preview. The selected DOM context will be sent with your next message.";
    return;
  }

  if (state.selectedElements.length === 1) {
    const selected = state.selectedElements[0];
    elements.selectedTitle.textContent = selected.label;
    elements.selectedDetail.textContent = selected.selector || selected.text;
  } else {
    elements.selectedTitle.textContent = `${state.selectedElements.length} elements selected`;
    elements.selectedDetail.textContent = state.selectedElements
      .slice(0, 3)
      .map((item) => item.selector || item.label)
      .join("\n");
  }

  state.selectedElementContext = state.selectedElements.map((selected, index) => {
    return [
      `Selected element ${index + 1}:`,
      `selector: ${selected.selector}`,
      `label: ${selected.label}`,
      `visible text: ${selected.text}`,
      "outerHTML:",
      selected.html
    ].join("\n");
  }).join("\n\n");
}

function renderAgents() {
  elements.agentSelect.innerHTML = "";
  elements.agentSelect.append(new Option("Choose agent", ""));
  for (const agent of state.agents) {
    elements.agentSelect.append(new Option(agent.label, agent.id));
  }
  updateAgentStatus(null);
  renderModels(null);
}

async function selectAgent(agentId) {
  const agent = state.agents.find((item) => item.id === agentId);
  if (!agent) return;
  state.activeAgentId = agent.id;
  elements.agentSelect.value = agent.id;
  updateAgentStatus({ ready: false, message: "Checking CLI..." });
  const status = await window.htmlAgent.getAgentStatus(agent.id);
  if (state.activeAgentId !== agent.id) return;
  updateAgentStatus(status);
  if (!status.installed) offerAgentInstall(agent);
  const dynamicModels = await window.htmlAgent.getDynamicModels(agent.id);
  if (state.activeAgentId !== agent.id) return;
  const models = mergeModels(agent.models, dynamicModels);
  renderModels(models);
  elements.promptInput.focus();
}

function updateAgentStatus(status) {
  elements.agentStatus.classList.toggle("ready", Boolean(status?.ready));
  elements.agentStatus.title = status?.message || "No agent selected";
}

async function offerAgentInstall(agent) {
  if (state.installingAgentId) return;
  const ok = confirm(`${agent.label} CLI is not installed yet.\n\nInstall it now? HTML Agent Editor will install any missing dependencies first, then install ${agent.label} and update you here.`);
  if (!ok) return;
  state.installingAgentId = agent.id;
  appendChat(`Installing ${agent.label} CLI...`, "status");
  const result = await window.htmlAgent.installAgent(agent.id);
  if (!result.ok) {
    state.installingAgentId = null;
    appendChat(result.message || `Could not start ${agent.label} installer.`, "error");
  }
}

async function finishAgentInstall(agentId, result) {
  const agent = state.agents.find((item) => item.id === agentId);
  state.installingAgentId = null;
  appendChat(result.message || `${agent?.label || "Agent"} installer finished.`, result.ok ? "status" : "error");
  if (state.activeAgentId === agentId) {
    updateAgentStatus(await window.htmlAgent.getAgentStatus(agentId));
  }
}

function renderModels(models) {
  elements.modelSelect.innerHTML = "";
  if (!models) {
    elements.modelSelect.append(new Option("Choose an agent", ""));
    elements.modelSelect.disabled = true;
    return;
  }
  for (const model of models) {
    elements.modelSelect.append(new Option(model.label, model.id));
  }
  const saved = localStorage.getItem(modelStorageKey(state.activeAgentId)) || "";
  state.modelId = models.some((model) => model.id === saved) ? saved : "";
  elements.modelSelect.value = state.modelId;
  elements.modelSelect.disabled = !state.filePath;
}

function mergeModels(defaults, dynamic) {
  const seen = new Set();
  const merged = [];
  for (const model of [...defaults, ...dynamic]) {
    if (seen.has(model.id)) continue;
    seen.add(model.id);
    merged.push(model);
  }
  return merged;
}

function modelStorageKey(agentId) {
  return `HTMLAgentEditor.SelectedModel.${agentId}`;
}

async function sendPrompt(event) {
  event.preventDefault();
  const prompt = elements.promptInput.value.trim();
  if (!state.filePath) {
    appendChat("Open an HTML file first.", "error");
    return;
  }
  if (!prompt) {
    appendChat("Type a change request first.", "error");
    return;
  }
  if (!state.activeAgentId) {
    appendChat("Choose an agent first.", "error");
    return;
  }
  if (state.running) {
    appendChat("Agent is still working. Wait for this run to finish.", "status");
    return;
  }

  const agent = state.agents.find((item) => item.id === state.activeAgentId);
  const status = await window.htmlAgent.getAgentStatus(agent.id);
  updateAgentStatus(status);
  if (!status.installed) {
    offerAgentInstall(agent);
    appendChat(`${agent.label} CLI needs to be installed before it can run.`, "error");
    return;
  }
  appendChat(prompt, "user");
  elements.promptInput.value = "";
  setRunning(true);

  const result = await window.htmlAgent.sendAgent({
    agentId: state.activeAgentId,
    modelId: state.modelId,
    filePath: state.filePath,
    prompt: agentPrompt(prompt)
  });

  if (!result.ok) {
    setRunning(false);
    if (result.issue) {
      presentAgentIssue(result.issue, agent);
      appendChat(`${agent.label} needs authorization before it can run.`, "error");
    } else {
      appendChat(result.message || "Could not start agent.", "error");
    }
    return;
  }

  appendChat(`${agent.label}: running...`, "status");
}

function agentPrompt(userText) {
  const lines = [
    "Edit the currently open HTML file with the smallest correct change.",
    "Token/output budget: be terse. Do not narrate steps, commands, diffs, file contents, or logs.",
    `File: ${state.filePath || "unknown"}`
  ];
  if (state.selectedElementContext) {
    const targetText = state.selectedElements.length === 1 ? "the selected element" : "all selected elements";
    lines.push(`Selected element context:\n${state.selectedElementContext}`);
    lines.push(`Unless the user clearly asks for a broader change, apply the requested change to ${targetText}.`);
  } else {
    lines.push("No specific element selected.");
  }
  lines.push(`User request: ${userText}`);
  lines.push("Apply the edit directly. Preserve unrelated content. Final answer only: one sentence under 25 words naming what changed.");
  return lines.join("\n");
}

async function stopAgent() {
  await window.htmlAgent.stopAgent();
  setRunning(false);
  appendChat("Agent run stopped.", "status");
}

function finishAgent(result) {
  setRunning(false);
  if (result.issue) {
    const agent = state.agents.find((item) => item.id === state.activeAgentId);
    presentAgentIssue(result.issue, agent);
    appendChat(`${agent?.label || "Agent"} needs authorization before it can run.`, "error");
    return;
  }
  if (result.code === 0) {
    reloadPreview();
    appendChat(result.changed ? "Done. Preview reloaded." : "Done, but the file appears unchanged. Open Work to inspect the agent output.", result.changed ? "status" : "error");
  } else {
    appendChat(`Agent exited with status ${result.code}. Open Work to inspect the output.`, "error");
  }
}

function presentAgentIssue(issue) {
  const commandText = issue.actionCommand ? `\n\nCommand: ${issue.actionCommand}` : "";
  const shouldOpen = issue.actionCommand && confirm(`${issue.title}\n\n${issue.message}${commandText}\n\nOpen an authorization terminal?`);
  if (shouldOpen) window.htmlAgent.openAuthorizationTerminal(issue.actionCommand);
  if (!issue.actionCommand) alert(`${issue.title}\n\n${issue.message}`);
}

function setRunning(isRunning) {
  state.running = isRunning;
  elements.sendBtn.classList.toggle("hidden", isRunning);
  elements.stopBtn.classList.toggle("hidden", !isRunning);
  elements.promptInput.disabled = isRunning;
  elements.agentSelect.disabled = !state.filePath || isRunning;
  elements.modelSelect.disabled = !state.filePath || !state.activeAgentId || isRunning;
}

function appendProcess(text) {
  const clean = text.trim();
  if (!clean) return;
  appendChat(clean, "process");
}

function appendChat(text, kind = "status") {
  if (!text) return;
  state.chatMessages.push({ text, kind });
  renderChat();
}

function renderChat() {
  elements.chatLog.innerHTML = "";
  let hiddenProcessCount = 0;
  for (const message of state.chatMessages) {
    if (message.kind === "process" && !state.showWork) {
      hiddenProcessCount += 1;
      continue;
    }
    elements.chatLog.append(messageElement(message));
  }
  if (hiddenProcessCount > 0 && !state.showWork) {
    elements.chatLog.append(messageElement({
      kind: "process",
      text: `${hiddenProcessCount} work update${hiddenProcessCount === 1 ? "" : "s"} hidden. Use Work to view.`
    }));
  }
  elements.chatLog.scrollTop = elements.chatLog.scrollHeight;
}

function messageElement(message) {
  const row = document.createElement("div");
  row.className = `message ${message.kind}`;
  if (message.kind !== "status" && message.kind !== "process") {
    const role = document.createElement("div");
    role.className = "role";
    role.textContent = roleName(message.kind);
    row.append(role);
  }
  const body = document.createElement("div");
  body.textContent = message.text;
  row.append(body);
  return row;
}

function roleName(kind) {
  if (kind === "user") return "You";
  if (kind === "error") return "Needs attention";
  return "Agent";
}

function resetChat() {
  state.chatMessages = [];
  renderChat();
}

function clearChat() {
  state.chatMessages = [];
  appendChat("Chat cleared.", "status");
}

function updateFileControls() {
  const hasFile = Boolean(state.filePath);
  elements.reloadBtn.disabled = !hasFile;
  elements.browserBtn.disabled = !hasFile;
  elements.agentSelect.disabled = !hasFile || state.running;
  elements.modelSelect.disabled = !hasFile || !state.activeAgentId || state.running;
}

function baseName(filePath) {
  return filePath.split(/[\\/]/).pop() || filePath;
}
