import { z } from "zod";
import { ThemePreference } from "./domain.js";

export const DesktopMethods = {
  proactiveShow: "proactive.show",
  proactiveOpenAgent: "proactive.openAgent",
  mainShow: "main.show",
  appQuit: "app.quit",
  windowMinimize: "window.minimize",
  windowToggleMaximize: "window.toggleMaximize",
  windowClose: "window.close",
  windowGetState: "window.getState",
  themeGet: "theme.get",
  themeSet: "theme.set",
  workspacePick: "workspace.pick",
  secretsGet: "secrets.get",
  secretsSet: "secrets.set",
  shellOpenPath: "shell.openPath",
  shellOpenExternal: "shell.openExternal"
} as const;

export const WindowState = z.object({
  isMaximized: z.boolean(),
  isFullscreen: z.boolean()
});
export type WindowState = z.infer<typeof WindowState>;

export const ThemeSetParams = z.object({
  theme: ThemePreference
});
export type ThemeSetParams = z.infer<typeof ThemeSetParams>;

export const SecretsState = z.object({
  openaiApiKey: z.string().optional(),
  anthropicApiKey: z.string().optional(),
  deepseekApiKey: z.string().optional()
});
export type SecretsState = z.infer<typeof SecretsState>;

export const OpenExternalParams = z.object({
  url: z.string().url()
});
export type OpenExternalParams = z.infer<typeof OpenExternalParams>;

export const DesktopEvents = { navigateAgent: "desktop.navigateAgent" } as const;
