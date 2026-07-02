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
  latestUpdate: null,
  checkingUpdate: false,
  showedUpdateIndicator: false,
  dark: localStorage.getItem("darkMode") !== "false",
  selectedElements: [],
  selectedElementContext: null,
  chatMessages: [],
  sessionMessages: [],
  attachedContexts: [],
  mode: localStorage.getItem("chatMode") === "chat" ? "chat" : "edit",
  includeEditContext: localStorage.getItem("includeEditContext") !== "false",
  currentRun: null,
  canRewind: false,
  originalFilePath: null,
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
  updateBtn: document.getElementById("updateBtn"),
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
  editModeBtn: document.getElementById("editModeBtn"),
  chatModeBtn: document.getElementById("chatModeBtn"),
  editContextToggle: document.getElementById("editContextToggle"),
  rewindBtn: document.getElementById("rewindBtn"),
  attachBtn: document.getElementById("attachBtn"),
  attachUrlBtn: document.getElementById("attachUrlBtn"),
  newSessionBtn: document.getElementById("newSessionBtn"),
  contextFileInput: document.getElementById("contextFileInput"),
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
  updateModeControls();
  updateFileControls();
  renderChat();
  checkForUpdates(false);

  elements.openBtn.addEventListener("click", openFileDialog);
  elements.reloadBtn.addEventListener("click", reloadPreview);
  elements.browserBtn.addEventListener("click", openInBrowser);
  elements.updateBtn.addEventListener("click", onUpdateClick);
  elements.themeBtn.addEventListener("click", toggleTheme);
  elements.panelBtn.addEventListener("click", togglePanel);
  elements.workBtn.addEventListener("click", toggleWork);
  elements.pickerBtn.addEventListener("click", togglePicker);
  elements.editModeBtn.addEventListener("click", () => setMode("edit"));
  elements.chatModeBtn.addEventListener("click", () => setMode("chat"));
  elements.editContextToggle.addEventListener("change", toggleEditContext);
  elements.rewindBtn.addEventListener("click", rewindLastEdit);
  elements.attachBtn.addEventListener("click", () => elements.contextFileInput.click());
  elements.attachUrlBtn.addEventListener("click", attachUrlContext);
  elements.newSessionBtn.addEventListener("click", startNewSession);
  elements.contextFileInput.addEventListener("change", () => {
    attachFileContexts(Array.from(elements.contextFileInput.files || []));
    elements.contextFileInput.value = "";
  });
  elements.agentSelect.addEventListener("change", () => selectAgent(elements.agentSelect.value));
  elements.modelSelect.addEventListener("change", () => {
    state.modelId = elements.modelSelect.value;
    if (state.activeAgentId) localStorage.setItem(modelStorageKey(state.activeAgentId), state.modelId);
    const agent = state.agents.find((item) => item.id === state.activeAgentId);
    if (agent) appendChat(`${agent.label} model set to ${modelLabel(state.modelId)}.`, "status");
  });
  elements.composer.addEventListener("submit", sendPrompt);
  elements.promptInput.addEventListener("input", resizePromptInput);
  elements.promptInput.addEventListener("keydown", onPromptKeyDown);
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
  elements.preview.addEventListener("will-navigate", (event) => {
    if (handlePreviewFileNavigation(event.url)) event.preventDefault();
  });
  elements.preview.addEventListener("did-navigate", (event) => {
    handlePreviewFileNavigation(event.url);
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
  const onDragOver = (event) => {
    event.preventDefault();
    elements.previewPane.classList.add("dragging");
  };
  const onDragLeave = () => {
    elements.previewPane.classList.remove("dragging");
  };
  const onDrop = (event) => {
    event.preventDefault();
    elements.previewPane.classList.remove("dragging");
    const files = Array.from(event.dataTransfer.files || []);
    const first = files[0];
    if (!state.filePath && first?.path && /\.(html?|xhtml)$/i.test(first.path)) {
      loadFile(first.path);
      return;
    }
    if (files.length > 0) {
      attachFileContexts(files);
      return;
    }
    const url = event.dataTransfer.getData("text/uri-list") || event.dataTransfer.getData("text/plain");
    if (/^https?:\/\//i.test(url)) attachContext("URL", url);
  };

  for (const target of [elements.previewPane, elements.preview, elements.sidePanel, elements.composer]) {
    target.addEventListener("dragover", onDragOver);
    target.addEventListener("dragleave", onDragLeave);
    target.addEventListener("drop", onDrop);
  }
}

function handlePreviewFileNavigation(url) {
  const filePath = filePathFromFileUrl(url);
  if (!filePath || filePath === state.filePath || !/\.(html?|xhtml)$/i.test(filePath)) return false;
  loadFile(filePath);
  return true;
}

function filePathFromFileUrl(url) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "file:") return null;
    const pathname = decodeURIComponent(parsed.pathname);
    if (navigator.platform.toLowerCase().startsWith("win") && /^\/[a-zA-Z]:/.test(pathname)) {
      return pathname.slice(1).replace(/\//g, "\\");
    }
    return pathname;
  } catch {
    return null;
  }
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
  const prepared = await window.htmlAgent.prepareEditFile(filePath);
  const effectivePath = prepared?.filePath || filePath;
  state.filePath = effectivePath;
  state.originalFilePath = prepared?.originalPath || null;
  state.fileUrl = await window.htmlAgent.fileUrl(effectivePath);
  elements.preview.src = state.fileUrl;
  document.title = `HTML Agent Editor - ${baseName(effectivePath)}`;
  elements.emptyState.classList.add("hidden");
  await window.htmlAgent.watchFile(effectivePath);
  resetSession();
  clearSelection();
  if (prepared?.copied && prepared.message) {
    appendChat(prepared.message, "status");
  }
  if (!state.activeAgentId) {
    const defaultAgent = state.agents.find((agent) => agent.id === "opencode") || state.agents[0];
    if (defaultAgent) await selectAgent(defaultAgent.id);
  } else {
    await selectAgent(state.activeAgentId);
  }
  updateFileControls();
  elements.promptInput.focus();
  resizePromptInput();
}

function onPromptKeyDown(event) {
  if (event.key !== "Enter" || event.shiftKey) return;
  event.preventDefault();
  elements.composer.requestSubmit();
}

function resizePromptInput() {
  elements.promptInput.style.height = "auto";
  elements.promptInput.style.height = `${Math.min(elements.promptInput.scrollHeight, 150)}px`;
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

async function onUpdateClick() {
  if (state.latestUpdate) {
    await installUpdate(state.latestUpdate);
    return;
  }
  await checkForUpdates(true);
}

async function checkForUpdates(manual) {
  if (state.checkingUpdate) return;
  state.checkingUpdate = true;
  elements.updateBtn.title = "Checking for updates...";
  try {
    const result = await window.htmlAgent.checkForUpdates();
    if (result.available) {
      state.latestUpdate = result;
      elements.updateBtn.classList.add("is-active");
      elements.updateBtn.title = `Update available: ${result.latestVersion}`;
      if (manual || !state.showedUpdateIndicator) {
        state.showedUpdateIndicator = true;
        const ok = confirm(`Update available: ${result.latestVersion}\n\nInstall it now?`);
        if (ok) await installUpdate(result, true);
      }
    } else {
      state.latestUpdate = null;
      elements.updateBtn.classList.remove("is-active");
      elements.updateBtn.title = "Check for updates";
      if (manual) alert("HTML Agent Editor is up to date.");
    }
  } catch {
    elements.updateBtn.title = "Could not check for updates";
    if (manual) alert("GitHub could not be reached. Try again later.");
  } finally {
    state.checkingUpdate = false;
  }
}

async function installUpdate(update, confirmed = false) {
  if (!confirmed) {
    const ok = confirm(`Install ${update.latestVersion}?\n\nHTML Agent Editor will download the latest release and launch it.`);
    if (!ok) return;
  }
  elements.updateBtn.disabled = true;
  elements.updateBtn.textContent = "Updating";
  try {
    const result = await window.htmlAgent.installUpdate(update);
    if (!result.ok) {
      elements.updateBtn.disabled = false;
      elements.updateBtn.textContent = "Update";
      alert(result.message || "Could not start the update.");
    }
  } catch (error) {
    elements.updateBtn.disabled = false;
    elements.updateBtn.textContent = "Update";
    alert(error?.message || "Could not start the update.");
  }
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
  elements.workBtn.textContent = state.showWork ? "Hide" : "Think";
  elements.workBtn.classList.toggle("is-active", state.showWork);
  elements.workBtn.title = state.showWork ? "Hide visible agent thinking and output" : "Show visible agent thinking and output";
  renderChat();
}

function togglePicker() {
  state.pickerEnabled = !state.pickerEnabled;
  updatePickerState();
}

function setMode(mode) {
  state.mode = mode === "chat" ? "chat" : "edit";
  localStorage.setItem("chatMode", state.mode);
  updateModeControls();
  elements.promptInput.focus();
}

function updateModeControls() {
  const isChat = state.mode === "chat";
  elements.editModeBtn.classList.toggle("is-active", !isChat);
  elements.chatModeBtn.classList.toggle("is-active", isChat);
  elements.editModeBtn.setAttribute("aria-pressed", String(!isChat));
  elements.chatModeBtn.setAttribute("aria-pressed", String(isChat));
  elements.editContextToggle.checked = state.includeEditContext;
  elements.editContextToggle.disabled = isChat || state.running;
  elements.editContextToggle.closest(".context-checkbox")?.classList.toggle("is-active", state.includeEditContext && !isChat);
  elements.promptInput.placeholder = isChat ? "Ask about the selected element" : "Ask for an edit";
  elements.rewindBtn.disabled = !state.canRewind || state.running;
  elements.attachBtn.classList.toggle("is-active", state.attachedContexts.length > 0);
  elements.attachUrlBtn.classList.toggle("is-active", state.attachedContexts.length > 0);
}

function toggleEditContext() {
  state.includeEditContext = elements.editContextToggle.checked;
  localStorage.setItem("includeEditContext", state.includeEditContext ? "true" : "false");
  appendChat(state.includeEditContext ? "Edit mode will include prior context." : "Edit mode will ignore prior context.", "status");
  updateModeControls();
}

async function rewindLastEdit() {
  if (!state.filePath) {
    appendChat("Open an HTML file first.", "error");
    return;
  }
  const result = await window.htmlAgent.rewindLastEdit(state.filePath);
  if (result.ok) {
    state.canRewind = false;
    updateModeControls();
    reloadPreview();
    appendChat("Rewound the last edit. Preview reloaded.", "status");
  } else {
    appendChat(result.message || "No edit to rewind yet.", "error");
  }
}

function attachFileContexts(files) {
  for (const file of files) {
    if (!file?.path) continue;
    const label = imageFilePattern().test(file.path) ? `Image ${baseName(file.path)}` : `File ${baseName(file.path)}`;
    attachContext(label, `${file.path}\nfileURL: ${fileUrlFromPath(file.path)}`);
  }
}

function attachUrlContext() {
  const value = prompt("Attach URL as context:");
  if (!value) return;
  attachContext("URL", value.trim());
}

function attachContext(label, value) {
  const clean = String(value || "").trim();
  if (!clean) return;
  if (state.attachedContexts.some((item) => item.value === clean)) {
    appendChat(`Context already attached: ${label}`, "status");
    return;
  }
  state.attachedContexts.push({ label, value: clean });
  appendChat(`Attached context: ${label}`, "status");
  updateModeControls();
}

function imageFilePattern() {
  return /\.(png|jpe?g|gif|webp|heic|tiff?|svg)$/i;
}

function fileUrlFromPath(filePath) {
  const normalized = String(filePath).replace(/\\/g, "/");
  if (/^[a-zA-Z]:\//.test(normalized)) {
    const drive = normalized.slice(0, 2);
    const rest = normalized.slice(2).split("/").map((part) => encodeURIComponent(part)).join("/");
    return `file:///${drive}${rest}`;
  }
  const encoded = normalized.split("/").map((part) => encodeURIComponent(part)).join("/");
  return `file://${encoded.startsWith("/") ? "" : "/"}${encoded}`;
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
  if (!status.installed || status.installable) offerAgentInstall(agent, status);
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

async function offerAgentInstall(agent, status = null) {
  if (state.installingAgentId) return;
  const prompt = status?.installed
    ? `${status.message}\n\nInstall the missing dependency now? HTML Agent Editor will run the official installer for you.`
    : `${agent.label} CLI is not installed yet.\n\nInstall it now? HTML Agent Editor will run any required official dependency installers first, then install ${agent.label}.`;
  const ok = confirm(prompt);
  if (!ok) return;
  state.installingAgentId = agent.id;
  appendChat(status?.installed ? `Installing missing ${agent.label} dependency...` : `Installing ${agent.label} CLI...`, "status");
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

function modelLabel(modelId) {
  return modelId || "Default";
}

async function sendPrompt(event) {
  event.preventDefault();
  const prompt = elements.promptInput.value.trim();
  if (!state.filePath) {
    appendChat("Open an HTML file first.", "error");
    return;
  }
  if (!prompt) {
    appendChat(state.mode === "chat" ? "Type a question first." : "Type a change request first.", "error");
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
  if (!status.ready) {
    offerAgentInstall(agent, status);
    appendChat(status.message || `${agent.label} needs setup before it can run.`, "error");
    return;
  }
  const mode = state.mode;
  appendChat(prompt, "user");
  elements.promptInput.value = "";
  resizePromptInput();
  setRunning(true);
  state.currentRun = { mode, prompt, output: "" };
  appendChat(`${agent.label}: using model ${modelLabel(state.modelId)} in ${mode} mode.`, "status");
  const agentRequest = mode === "chat" ? chatPrompt(prompt) : agentPrompt(prompt);

  const result = await window.htmlAgent.sendAgent({
    agentId: state.activeAgentId,
    modelId: state.modelId,
    filePath: state.filePath,
    mode,
    prompt: agentRequest
  });

  if (!result.ok) {
    setRunning(false);
    state.currentRun = null;
    if (result.issue) {
      presentAgentIssue(result.issue, agent);
      appendChat(`${agent.label} needs authorization before it can run.`, "error");
    } else {
      appendChat(result.message || "Could not start agent.", "error");
    }
    return;
  }

  appendSessionMessage("user", prompt, mode);
  appendChat(`${agent.label}: running...`, "status");
}

function agentPrompt(userText) {
  const lines = [
    "Edit the currently open HTML file with the smallest correct change.",
    "Token/output budget: be terse. Do not narrate steps, commands, diffs, file contents, or logs.",
    `File: ${state.filePath || "unknown"}`
  ];
  if (state.includeEditContext) {
    const history = sessionContext();
    if (history) {
      lines.push("Prior conversation in this session for context only:");
      lines.push(history);
    }
    const attachments = attachmentContext();
    if (attachments) {
      lines.push("Attached context references:");
      lines.push(attachments);
    }
  } else {
    lines.push("Ignore prior chat, prior edit summaries, and attached context for this edit.");
  }
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

function chatPrompt(userText) {
  const lines = [
    "Answer the user's question about the currently open HTML document or selected element.",
    "This is chat mode: do not edit files, do not run write commands, and do not modify the document.",
    "Be more explanatory than edit mode: give enough context for the user to understand the element, revision, or tradeoff.",
    "Do not reveal hidden chain-of-thought. If useful, provide a brief visible rationale or checklist.",
    `Open file name: ${baseName(state.filePath || "unknown")}`
  ];
  const history = sessionContext("chat");
  if (history) {
    lines.push("Prior conversation in this session:");
    lines.push(history);
  }
  const attachments = attachmentContext();
  if (attachments) {
    lines.push("Attached context references:");
    lines.push(attachments);
  }
  if (state.selectedElementContext) {
    lines.push(`Selected element context:\n${state.selectedElementContext}`);
  } else {
    lines.push("No specific element selected.");
  }
  lines.push(`Question: ${userText}`);
  lines.push("Final answer only. Use concise paragraphs or bullets when helpful.");
  return lines.join("\n");
}

function sessionContext(mode = null) {
  return state.sessionMessages
    .filter((message) => !mode || message.mode === mode)
    .slice(-10)
    .map((message) => `${message.role === "user" ? "User" : "Assistant"}: ${message.text}`)
    .join("\n");
}

function attachmentContext() {
  return state.attachedContexts
    .map((item) => `- ${item.label}: ${item.value}`)
    .join("\n");
}

function appendSessionMessage(role, text, mode) {
  if (!text) return;
  state.sessionMessages.push({ role, text, mode });
  if (state.sessionMessages.length > 20) {
    state.sessionMessages = state.sessionMessages.slice(-20);
  }
}

async function stopAgent() {
  await window.htmlAgent.stopAgent();
  setRunning(false);
  state.currentRun = null;
  appendChat("Agent run stopped.", "status");
}

function finishAgent(result) {
  const run = state.currentRun;
  state.currentRun = null;
  setRunning(false);
  if (result.issue) {
    const agent = state.agents.find((item) => item.id === state.activeAgentId);
    presentAgentIssue(result.issue, agent);
    appendChat(`${agent?.label || "Agent"} needs authorization before it can run.`, "error");
    return;
  }
  if (run?.mode === "chat") {
    if (result.code === 0) {
      const answer = cleanAgentAnswer(run.output);
      appendChat(answer || "I could not find a usable answer in the agent output. Open Thinking to inspect it.", answer ? "assistant" : "error");
      if (answer) appendSessionMessage("assistant", answer, "chat");
      if (result.restored) {
        reloadPreview();
        appendChat("Chat mode restored the file after the agent attempted a change.", "status");
      }
      if (result.changed) {
        reloadPreview();
        appendChat("The file appears to have changed during chat mode. Preview reloaded so you can inspect it.", "error");
      }
    } else {
      appendChat(`Agent exited with status ${result.code}. Open Thinking to inspect the output.`, "error");
    }
    return;
  }
  if (result.code === 0) {
    reloadPreview();
    if (result.changed) {
      state.canRewind = true;
      updateModeControls();
    }
      const summary = result.changed ? "Done. Preview reloaded." : "Done, but the file appears unchanged. Open Thinking to inspect the agent output.";
    appendChat(summary, result.changed ? "status" : "error");
    appendSessionMessage("assistant", summary, "edit");
  } else {
    appendChat(`Agent exited with status ${result.code}. Open Thinking to inspect the output.`, "error");
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
  elements.editModeBtn.disabled = isRunning;
  elements.chatModeBtn.disabled = isRunning;
  elements.editContextToggle.disabled = isRunning || state.mode === "chat";
  elements.rewindBtn.disabled = isRunning || !state.canRewind;
  elements.attachBtn.disabled = isRunning;
  elements.attachUrlBtn.disabled = isRunning;
  elements.newSessionBtn.disabled = isRunning;
  elements.agentSelect.disabled = !state.filePath || isRunning;
  elements.modelSelect.disabled = !state.filePath || !state.activeAgentId || isRunning;
}

function appendProcess(text) {
  if (state.running && state.currentRun) state.currentRun.output += text;
  const clean = text.trim();
  if (!clean) return;
  appendChat(clean, "process");
}

function cleanAgentAnswer(text) {
  return String(text || "").trim();
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
      text: `${hiddenProcessCount} thinking update${hiddenProcessCount === 1 ? "" : "s"} hidden. Use Think to view.`
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

function resetSession() {
  state.chatMessages = [];
  state.sessionMessages = [];
  state.attachedContexts = [];
  state.canRewind = false;
  updateModeControls();
  renderChat();
}

function clearChat() {
  state.chatMessages = [];
  appendChat("Chat cleared.", "status");
}

function startNewSession() {
  state.chatMessages = [];
  state.sessionMessages = [];
  state.attachedContexts = [];
  appendChat("New session started.", "status");
  updateModeControls();
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
