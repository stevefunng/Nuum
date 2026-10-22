import { contextBridge, ipcRenderer } from "electron";
import { DesktopMethods, type SecretsState } from "@nuum/protocol";

contextBridge.exposeInMainWorld("nuum", {
  host: {
    request: (method: string, params?: unknown) => ipcRenderer.invoke("host:request", method, params),
    onEvent: (listener: (method: string, params: unknown) => void) => {
      const wrapped = (_event: unknown, method: string, params: unknown): void => listener(method, params);
      ipcRenderer.on("host:event", wrapped);
      return () => {
        ipcRenderer.removeListener("host:event", wrapped);
      };
    }
  },
  desktop: {
    showProactive: () => ipcRenderer.invoke(DesktopMethods.proactiveShow),
    openProactiveAgent: (agentId: string) => ipcRenderer.invoke(DesktopMethods.proactiveOpenAgent, { agentId }),
    showMain: () => ipcRenderer.invoke(DesktopMethods.mainShow),
    quit: () => ipcRenderer.invoke(DesktopMethods.appQuit),
    openPath: (file: string) => ipcRenderer.invoke(DesktopMethods.shellOpenPath, file) as Promise<string>,
    pickWorkspace: () => ipcRenderer.invoke(DesktopMethods.workspacePick) as Promise<string | null>,
    getSecrets: () => ipcRenderer.invoke(DesktopMethods.secretsGet) as Promise<SecretsState>,
    setSecrets: (secrets: SecretsState) => ipcRenderer.invoke(DesktopMethods.secretsSet, secrets)
  }
});
