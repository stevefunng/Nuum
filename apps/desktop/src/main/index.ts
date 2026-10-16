import { ProactiveTray } from "./proactive-tray.js";
import { HostEvents, DesktopEvents, AgentIdParams } from "@nuum/protocol";
import { app, BrowserWindow, dialog, Menu, ipcMain, safeStorage, shell } from "electron";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DesktopMethods, JsonRpcPeer, createStdioDuplex, type SecretsState } from "./host-bridge.js";

function findRepoRoot(start: string): string {
  let dir = start;
  for (let i = 0; i < 8; i += 1) {
    if (existsSync(path.join(dir, "pnpm-workspace.yaml"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error(`Cannot find monorepo root from ${start}`);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = findRepoRoot(here);
// Isolated local smoke runs can keep test state outside the user's normal profile.
if (process.env.NUUM_USER_DATA_DIR) app.setPath("userData", path.resolve(process.env.NUUM_USER_DATA_DIR));
const dataDir = path.join(app.getPath("userData"), "data");
mkdirSync(dataDir, { recursive: true });

let host: ChildProcessWithoutNullStreams | null = null;
let peer: JsonRpcPeer | null = null;
let window: BrowserWindow | null = null;
let proactiveTray: ProactiveTray | null = null;
let quitting = false;

let interfaceLanguage = "zh-CN";
function installMenu(language: string): void {
  interfaceLanguage = language;
  proactiveTray?.setLanguage(language);
  const label = (zh: string, en: string) => language === "en" ? en : zh;
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { label: "Nuum", submenu: [
      { role: "about", label: label("关于 Nuum", "About Nuum") },
      { type: "separator" },
      { role: "hide", label: label("隐藏 Nuum", "Hide Nuum") },
      { role: "hideOthers", label: label("隐藏其他应用", "Hide Others") },
      { role: "unhide", label: label("显示全部", "Show All") },
      { type: "separator" },
      { role: "quit", label: label("退出 Nuum", "Quit Nuum") }
    ] },
    { label: label("文件", "File"), submenu: [{ role: "close", label: label("关闭窗口", "Close Window") }] },
    { label: label("编辑", "Edit"), submenu: [
      { role: "undo", label: label("撤销", "Undo") }, { role: "redo", label: label("重做", "Redo") },
      { type: "separator" },
      { role: "cut", label: label("剪切", "Cut") }, { role: "copy", label: label("复制", "Copy") },
      { role: "paste", label: label("粘贴", "Paste") }, { role: "selectAll", label: label("全选", "Select All") }
    ] },
    { label: label("显示", "View"), submenu: [
      { role: "reload", label: label("重新加载", "Reload") },
      { role: "toggleDevTools", label: label("开发者工具", "Developer Tools") },
      { type: "separator" },
      { role: "resetZoom", label: label("实际大小", "Actual Size") },
      { role: "zoomIn", label: label("放大", "Zoom In") }, { role: "zoomOut", label: label("缩小", "Zoom Out") },
      { role: "togglefullscreen", label: label("切换全屏", "Toggle Full Screen") }
    ] },
    { label: label("窗口", "Window"), submenu: [
      { role: "minimize", label: label("最小化", "Minimize") }, { role: "zoom", label: label("缩放", "Zoom") },
      { role: "front", label: label("前置全部窗口", "Bring All to Front") }
    ] }
  ]));
}

function sendToRenderer(method: string, params: unknown): void {
  proactiveTray?.send(method, params);
  if (!window || window.isDestroyed()) return;
  try {
    window.webContents.send("host:event", method, params);
  } catch {
    // Window can disappear between the check and send while quitting.
  }
}

function secretsPath(): string {
  return path.join(app.getPath("userData"), "secrets.bin");
}

function readSecrets(): SecretsState {
  try {
    const raw = readFileSync(secretsPath());
    const json = safeStorage.isEncryptionAvailable()
      ? safeStorage.decryptString(raw)
      : raw.toString("utf8");
    return JSON.parse(json) as SecretsState;
  } catch {
    return {};
  }
}

function writeSecrets(secrets: SecretsState): void {
  const json = JSON.stringify(secrets);
  const payload = safeStorage.isEncryptionAvailable() ? safeStorage.encryptString(json) : Buffer.from(json, "utf8");
  writeFileSync(secretsPath(), payload);
}

function startHost(): JsonRpcPeer {
  const hostEntry = path.join(repoRoot, "packages/host/dist/main.js");
  const kernelEntry = path.join(repoRoot, "packages/kernel/dist/main.js");
  const child = spawn("node", [hostEntry, "--data-dir", dataDir, "--kernel-entry", kernelEntry], {
    stdio: ["pipe", "pipe", "pipe"]
  });
  host = child;
  child.stderr.on("data", (chunk) => process.stderr.write(chunk));
  child.on("exit", () => {
    host = null;
    peer = null;
    sendToRenderer("host.kernel.down", { reason: "host-exit" });
    void proactiveTray?.refresh();
  });
  const next = new JsonRpcPeer(createStdioDuplex(child.stdout, child.stdin));
  next.onEvent((method, params) => {
    sendToRenderer(method, params);
    if (method === HostEvents.proactiveUpdated) void proactiveTray?.refresh();
  });
  peer = next;
  return next;
}

function createWindow(): void {
  window = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 560,
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 16, y: 15 },
    backgroundColor: "#111111",
    webPreferences: {
      preload: path.join(here, "../preload/index.mjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });
  window.on("close", (event) => {
    if (!quitting && proactiveTray) { event.preventDefault(); window?.hide(); }
  });
  window.on("closed", () => {
    window = null;
  });
  if (process.env.ELECTRON_RENDERER_URL) {
    void window.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    void window.loadFile(path.join(here, "../renderer/index.html"));
  }
}

app.whenReady().then(async () => {
  const hostPeer = startHost();
  await hostPeer.request("sys.hello");
  const secrets = readSecrets();
  if (secrets.openaiApiKey || secrets.anthropicApiKey || secrets.deepseekApiKey) {
    await hostPeer.request("settings.set", {
      openaiApiKey: secrets.openaiApiKey,
      anthropicApiKey: secrets.anthropicApiKey,
      deepseekApiKey: secrets.deepseekApiKey
    });
  }
  const preferences = await hostPeer.request("settings.get") as { language?: string };
  installMenu(preferences.language ?? "zh-CN");
  createWindow();
  proactiveTray = new ProactiveTray(here, async (method) => {
    if (!peer) throw new Error("Host is not running");
    return peer.request(method);
  }, showMainWindow, () => app.quit());
  proactiveTray.setLanguage(interfaceLanguage);
});

function showMainWindow(): void {
  if (!window || window.isDestroyed()) createWindow();
  if (window?.isMinimized()) window.restore();
  window?.show(); window?.focus();
}
app.on("activate", showMainWindow);

ipcMain.handle(DesktopMethods.proactiveShow, () => proactiveTray?.show());
ipcMain.handle(DesktopMethods.mainShow, () => { proactiveTray?.hide(); showMainWindow(); });
ipcMain.handle(DesktopMethods.appQuit, () => app.quit());
ipcMain.handle(DesktopMethods.proactiveOpenAgent, async (_event, raw) => {
  const { id } = AgentIdParams.parse({ id: raw?.agentId });
  if (!peer) throw new Error("Host is not running");
  await peer.request("agent.get", { id });
  proactiveTray?.hide();
  showMainWindow();
  const send = () => sendToRenderer(DesktopEvents.navigateAgent, { agentId: id });
  if (window?.webContents.isLoading()) window.webContents.once("did-finish-load", send);
  else send();
});

ipcMain.handle("host:request", async (_event, method: string, params: unknown) => {
  if (!peer) throw new Error("Host is not running");
  try {
    const result = await peer.request(method, params);
    if (method === "settings.set") {
      const language = (result as { language?: string }).language;
      if (language === "en" || language === "zh-CN") installMenu(language);
    }
    return result;
  } catch (error) {
    throw new Error(error instanceof Error ? error.message : String(error));
  }
});

ipcMain.handle(DesktopMethods.windowMinimize, () => window?.minimize());
ipcMain.handle(DesktopMethods.windowToggleMaximize, () => {
  if (!window) return;
  if (window.isMaximized()) window.unmaximize();
  else window.maximize();
});
ipcMain.handle(DesktopMethods.windowClose, () => window?.close());
ipcMain.handle(DesktopMethods.windowGetState, () => ({
  isMaximized: window?.isMaximized() ?? false,
  isFullscreen: window?.isFullScreen() ?? false
}));
ipcMain.handle(DesktopMethods.themeGet, () => ({ theme: "system" }));
ipcMain.handle(DesktopMethods.workspacePick, async () => {
  const result = await dialog.showOpenDialog({ title: interfaceLanguage === "en" ? "Choose a folder" : "选择文件夹", buttonLabel: interfaceLanguage === "en" ? "Choose" : "选择", properties: ["openDirectory"] });
  return result.canceled ? null : result.filePaths[0] ?? null;
});
ipcMain.handle(DesktopMethods.secretsGet, () => readSecrets());
ipcMain.handle(DesktopMethods.secretsSet, (_event, secrets: SecretsState) => {
  writeSecrets(secrets);
  return { ok: true };
});
ipcMain.handle(DesktopMethods.shellOpenExternal, (_event, url: string) => shell.openExternal(url));

function stopHost(): void {
  const child = host;
  host = null;
  peer = null;
  child?.kill("SIGTERM");
}

app.on("window-all-closed", () => { if (quitting || !proactiveTray) app.quit(); });

// Cmd+Q 不经过 window-all-closed。父进程被强杀的情况由 Host 自己的 stdin 关闭兜底。
app.on("before-quit", () => {
  quitting = true;
  proactiveTray?.destroy(); proactiveTray = null;
  stopHost();
});
