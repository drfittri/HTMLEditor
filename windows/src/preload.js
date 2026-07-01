const { contextBridge, ipcRenderer } = require("electron");
const { pathToFileURL } = require("url");
const path = require("path");

contextBridge.exposeInMainWorld("htmlAgent", {
  getAgents: () => ipcRenderer.invoke("get-agents"),
  getDynamicModels: (agentId) => ipcRenderer.invoke("dynamic-models", agentId),
  openFileDialog: () => ipcRenderer.invoke("open-file-dialog"),
  fileUrl: (filePath) => ipcRenderer.invoke("file-url", filePath),
  openInBrowser: (filePath) => ipcRenderer.invoke("open-in-browser", filePath),
  watchFile: (filePath) => ipcRenderer.invoke("watch-file", filePath),
  sendAgent: (request) => ipcRenderer.invoke("send-agent", request),
  stopAgent: () => ipcRenderer.invoke("stop-agent"),
  openAuthorizationTerminal: (command) => ipcRenderer.invoke("open-authorization-terminal", command),
  previewPreloadPath: () => pathToFileURL(path.join(__dirname, "preview-preload.js")).href,
  onOpenFilePath: (callback) => ipcRenderer.on("open-file-path", (_event, filePath) => callback(filePath)),
  onMenuOpenFile: (callback) => ipcRenderer.on("menu-open-file", callback),
  onMenuReload: (callback) => ipcRenderer.on("menu-reload", callback),
  onMenuOpenBrowser: (callback) => ipcRenderer.on("menu-open-browser", callback),
  onMenuToggleDark: (callback) => ipcRenderer.on("menu-toggle-dark", callback),
  onMenuClearChat: (callback) => ipcRenderer.on("menu-clear-chat", callback),
  onMenuAgent: (callback) => ipcRenderer.on("menu-agent", (_event, agentId) => callback(agentId)),
  onFileChanged: (callback) => ipcRenderer.on("file-changed", (_event, filePath) => callback(filePath)),
  onAgentOutput: (callback) => ipcRenderer.on("agent-output", (_event, text) => callback(text)),
  onAgentDone: (callback) => ipcRenderer.on("agent-done", (_event, result) => callback(result)),
  onAgentStillRunning: (callback) => ipcRenderer.on("agent-still-running", (_event, label) => callback(label))
});
