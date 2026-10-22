import { ExternalGrant, NetworkTarget } from "./permission-rules.js";
import { ProactivePolicy } from "./proactive.js";
import { z } from "zod";
import { WorkMembership } from "./work.js";

export const ProviderId = z.enum(["openai", "anthropic", "deepseek"]);
export type ProviderId = z.infer<typeof ProviderId>;

export const DEFAULT_MODEL_ID: Record<ProviderId, string> = {
  openai: "gpt-4o",
  anthropic: "claude-sonnet-4-20250514",
  deepseek: "deepseek-chat"
};

export const LocalToolAction = z.enum(["read-file", "list-directory", "write-file", "run-command", "network"]);
export type LocalToolAction = z.infer<typeof LocalToolAction>;

export const ToolPermission = z.enum(["always", "ask", "never"]);
export type ToolPermission = z.infer<typeof ToolPermission>;

export const ToolApproval = z.object({
  action: LocalToolAction,
  /** 文件类是 canonical absolute path；命令类是命令首 token。 */
  target: z.string().min(1)
});
export type ToolApproval = z.infer<typeof ToolApproval>;

export const AgentStatus = z.enum(["idle", "running", "error"]);
export type AgentStatus = z.infer<typeof AgentStatus>;

export const ToolResolution = z.enum(["always", "once", "deny", "never"]);
export type ToolResolution = z.infer<typeof ToolResolution>;

export const ThemePreference = z.enum(["light", "dark", "system"]);
export type ThemePreference = z.infer<typeof ThemePreference>;

export const ModelRef = z.object({
  provider: ProviderId,
  model: z.string().min(1)
});
export type ModelRef = z.infer<typeof ModelRef>;

export const ToolCall = z.object({
  id: z.string(),
  name: z.string(),
  arguments: z.record(z.unknown())
});
export type ToolCall = z.infer<typeof ToolCall>;

export const MessageRole = z.enum(["system", "user", "assistant", "tool"]);
export type MessageRole = z.infer<typeof MessageRole>;

export const ModelImage = z.object({
  mimeType: z.enum(["image/jpeg", "image/png", "image/gif", "image/webp"]),
  /** Base64 payload; only lives in the active Kernel turn, never in the transcript. */
  data: z.string()
});
export type ModelImage = z.infer<typeof ModelImage>;

export const ChatMessage = z.object({
  id: z.string(),
  role: MessageRole,
  content: z.string(),
  images: z.array(ModelImage).optional(),
  thinking: z.string().optional(),
  toolCalls: z.array(ToolCall).optional(),
  toolCallId: z.string().optional(),
  name: z.string().optional(),
  seq: z.number().int(),
  createdAt: z.number()
});
export type ChatMessage = z.infer<typeof ChatMessage>;

/**
 * profile.json — 人格与身份，用户可改，Host 是唯一写者。
 */
export const AgentTags = z.array(z.string().trim().min(1)).transform((tags) => [...new Set(tags)]);

export const AgentProfile = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string(),
  tags: AgentTags.optional(),
  avatarColor: z.string().optional(),
  avatarShape: z.string().optional(),
  /** 头像材质（哑光/玻璃/毛绒/极光隐藏款）。创建时随机定下并绑定，不再变更。 */
  avatarMaterial: z.string().optional(),
  createdAt: z.number()
});
export type AgentProfile = z.infer<typeof AgentProfile>;

/**
 * settings.json — 该 agent 的可配项。
 */
export { NetworkTarget } from "./permission-rules.js";
export const ExecutionPreferences = z.object({
  workspaceId: z.string(),
  commands: z.enum(["ask", "always", "never"]).default("ask"),
  commandGrants: z.array(z.object({ workspaceId: z.string(), command: z.string().min(1) })).default([]),
  externalGrants: z.array(ExternalGrant).optional(),
  networkGrants: z.array(z.object({ workspaceId: z.string(), target: NetworkTarget })).default([])
});
export type ExecutionPreferences = z.infer<typeof ExecutionPreferences>;

export const AgentSettings = z.object({
  execution: ExecutionPreferences.optional(),
  model: ModelRef,
  workspace: z.object({
    projectRoot: z.string().nullable(),
    /** null 跟随全局默认。 */
    toolPermission: ToolPermission.nullable()
  }).optional(),
  hiddenFromSidebar: z.boolean().optional(),
  proactive: ProactivePolicy.optional(),
  workMembership: WorkMembership.optional()
});
export type AgentSettings = z.infer<typeof AgentSettings>;

/**
 * 运行态一律派生，从不落盘：status 来自内存调度，unread 来自已读游标与末条 seq
 * 的比对，lastActivityAt 来自末条事件的 createdAt。所以进程重启后不可能留下
 * 磁盘上的假 running。
 */
export const AgentRuntime = z.object({
  activeRunId: z.string().optional(),
  status: AgentStatus,
  unread: z.boolean(),
  lastActivityAt: z.number()
});
export type AgentRuntime = z.infer<typeof AgentRuntime>;

export const AgentView = z.object({
  roomMemberships: z.record(WorkMembership).optional(),
  profile: AgentProfile,
  settings: AgentSettings,
  runtime: AgentRuntime
});
export type AgentView = z.infer<typeof AgentView>;

export const DEFAULT_AGENT_NAME = "Assistant";

export const SidebarOrganization = z.object({
  pinnedAgentIds: z.array(z.string()),
  sections: z.array(z.object({
    id: z.string().min(1),
    name: z.string().trim().min(1).max(80),
    agentIds: z.array(z.string()),
    isCollapsed: z.boolean().optional()
  }))
}).superRefine((value, context) => {
  const groupIds = value.sections.map((section) => section.id);
  const members = value.sections.flatMap((section) => section.agentIds);
  if (new Set(groupIds).size !== groupIds.length || new Set(members).size !== members.length || new Set(value.pinnedAgentIds).size !== value.pinnedAgentIds.length) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: "Sidebar groups, memberships and pins must be unique" });
  }
});
export type SidebarOrganization = z.infer<typeof SidebarOrganization>;

export const Language = z.enum(["zh-CN", "en"]);
export type Language = z.infer<typeof Language>;

export const Settings = z.object({
  defaultToolPermission: ToolPermission,
  defaultModel: ModelRef,
  theme: ThemePreference,
  language: Language.optional(),
  sidebar: SidebarOrganization.optional()
});
export type Settings = z.infer<typeof Settings>;

export const PublicSettings = Settings.extend({
  hasOpenaiKey: z.boolean(),
  hasAnthropicKey: z.boolean(),
  hasDeepseekKey: z.boolean()
});
export type PublicSettings = z.infer<typeof PublicSettings>;

export const Secrets = z.object({
  openaiApiKey: z.string().optional(),
  anthropicApiKey: z.string().optional(),
  deepseekApiKey: z.string().optional()
});
export type Secrets = z.infer<typeof Secrets>;

export function secretForProvider(secrets: Secrets, provider: ProviderId): string | undefined {
  if (provider === "openai") return secrets.openaiApiKey;
  if (provider === "anthropic") return secrets.anthropicApiKey;
  return secrets.deepseekApiKey;
}

const PROVIDER_FALLBACK: ProviderId[] = ["deepseek", "openai", "anthropic"];

export function resolveAvailableModel(secrets: Secrets, preferred?: ModelRef): ModelRef | undefined {
  if (preferred && secretForProvider(secrets, preferred.provider)) return preferred;
  for (const provider of PROVIDER_FALLBACK) {
    if (secretForProvider(secrets, provider)) {
      return { provider, model: DEFAULT_MODEL_ID[provider] };
    }
  }
  return undefined;
}

export const ToolDefinition = z.object({
  name: z.string(),
  description: z.string(),
  inputSchema: z.record(z.unknown()),
  mutating: z.boolean(),
  /** delegated 工具没有；本地工具必须声明，供 Kernel 做按动作权限判定。 */
  action: LocalToolAction.optional()
});
export type ToolDefinition = z.infer<typeof ToolDefinition>;

export const DEFAULT_SETTINGS: Settings = {
  defaultToolPermission: "ask",
  defaultModel: { provider: "deepseek", model: DEFAULT_MODEL_ID.deepseek },
  theme: "dark",
  language: "zh-CN"
};
