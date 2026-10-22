import { z } from "zod";
import {
  AgentSettings,
  AgentTags,
  AgentView,
  ModelRef,
  PublicSettings,
  Settings,
  ToolDefinition,
  ToolPermission,
  ToolResolution
} from "./domain.js";
import { LiveAssistant, TranscriptEvent, ViewBlock } from "./transcript.js";
import {
  WorkCatalog,
  WorkEvent,
  WorkProfile,
  WorkRole,
  WorkTaskPriority,
  WorkTaskState,
  WorkTaskView
} from "./work.js";

export const HostMethods = {
  sysHello: "sys.hello",
  sysPing: "sys.ping",
  sysShutdown: "sys.shutdown",
  settingsGet: "settings.get",
  settingsSet: "settings.set",
  agentCreate: "agent.create",
  agentList: "agent.list",
  agentGet: "agent.get",
  agentUpdate: "agent.update",
  agentDelete: "agent.delete",
  agentGetTranscript: "agent.getTranscript",
  agentSend: "agent.send",
  agentAnswerWidget: "agent.answerWidget",
  agentCancel: "agent.cancel",
  agentApproveTool: "agent.approveTool",
  agentDenyTool: "agent.denyTool",
  workCreate: "work.create",
  workList: "work.list",
  workGet: "work.get",
  workUpdate: "work.update",
  workPostMessage: "work.postMessage",
  workMemberAttach: "work.member.attach",
  workMemberDetach: "work.member.detach",
  workMemberMove: "work.member.move",
  workTaskTranscript: "work.task.transcript",
  workTaskCreate: "work.task.create",
  workTaskAssign: "work.task.assign",
  workTaskTransition: "work.task.transition",
  workDispatch: "work.dispatch",
  workContinue: "work.continue",
  workStopDiscussion: "work.stopDiscussion",
  workCatalogAdd: "work.catalog.add",
  workCatalogRemove: "work.catalog.remove",
  proactiveGet: "proactive.get",
  proactiveConfigure: "proactive.configure",
  proactiveCheck: "proactive.check",
  toolsList: "tools.list"
} as const;

export const HostEvents = {
  agentUpdated: "agent.updated",
  agentMessageDelta: "agent.message.delta",
  agentMessageCompleted: "agent.message.completed",
  agentToolPending: "agent.tool.pending",
  agentToolStarted: "agent.tool.started",
  agentToolCompleted: "agent.tool.completed",
  agentError: "agent.error",
  agentEnded: "agent.ended",
  workUpdated: "work.updated",
  workEventAppended: "work.event.appended",
  workCatalogUpdated: "work.catalog.updated",
  proactiveUpdated: "proactive.updated",
  settingsUpdated: "settings.updated",
  kernelDown: "host.kernel.down"
} as const;

export const WorkCreateParams = z.object({
  kind: z.enum(["room", "work"]).optional(),
  name: z.string().min(1)
}).strict();
export type WorkCreateParams = z.infer<typeof WorkCreateParams>;

export const WorkIdParams = z.object({ id: z.string().min(1) });
export type WorkIdParams = z.infer<typeof WorkIdParams>;

export const WorkUpdateParams = WorkIdParams.extend({
  kind: z.literal("work").optional(),
  name: z.string().min(1).optional()
}).strict();
export type WorkUpdateParams = z.infer<typeof WorkUpdateParams>;

export const WorkPostMessageParams = z.object({
  workId: z.string().min(1),
  body: z.string().min(1),
  clientEventId: z.string().optional(),
  inputAfterSeq: z.number().int().nonnegative().optional(),
  mentionedAgentIds: z.array(z.string()).default([])
});
export type WorkPostMessageParams = z.infer<typeof WorkPostMessageParams>;

export const WorkMemberAttachParams = z.object({
  workId: z.string().min(1),
  agentId: z.string().min(1),
  role: WorkRole.default("worker"),
  expectedRevision: z.number().int().nonnegative()
});
export type WorkMemberAttachParams = z.infer<typeof WorkMemberAttachParams>;

export const WorkMemberDetachParams = z.object({
  workId: z.string().min(1),
  agentId: z.string().min(1),
  expectedRevision: z.number().int().nonnegative()
});
export type WorkMemberDetachParams = z.infer<typeof WorkMemberDetachParams>;

export const WorkMemberMoveParams = z.object({
  fromWorkId: z.string().min(1),
  toWorkId: z.string().min(1),
  agentId: z.string().min(1),
  role: WorkRole.default("worker"),
  expectedRevision: z.number().int().nonnegative()
});
export type WorkMemberMoveParams = z.infer<typeof WorkMemberMoveParams>;

export const WorkTaskTranscriptParams = z.object({
  workId: z.string().min(1), taskId: z.string().min(1),
  sessionId: z.string().optional(), beforeSeq: z.number().int().positive().optional()
});

export const WorkTaskCreateParams = z.object({
  workId: z.string().min(1),
  title: z.string().min(1),
  description: z.string().default(""),
  acceptanceCriteria: z.array(z.string()).default([]),
  assigneeIds: z.array(z.string()).default([]),
  dependencyIds: z.array(z.string()).default([]),
  priority: WorkTaskPriority.default("normal")
});
export type WorkTaskCreateParams = z.infer<typeof WorkTaskCreateParams>;

export const WorkTaskAssignParams = z.object({
  workId: z.string().min(1),
  taskId: z.string().min(1),
  assigneeIds: z.array(z.string()),
  expectedRevision: z.number().int().positive()
});
export type WorkTaskAssignParams = z.infer<typeof WorkTaskAssignParams>;

export const WorkTaskTransitionParams = z.object({
  workId: z.string().min(1),
  taskId: z.string().min(1),
  to: WorkTaskState,
  expectedRevision: z.number().int().positive(),
  blocker: z.object({
    reason: z.string().min(1),
    ownerId: z.string().optional(),
    resumeCondition: z.string().optional()
  }).optional()
});
export type WorkTaskTransitionParams = z.infer<typeof WorkTaskTransitionParams>;

export const WorkDispatchParams = z.object({
  workId: z.string().min(1),
  agentId: z.string().min(1),
  taskId: z.string().min(1).optional(),
  instruction: z.string().min(1)
});
export type WorkDispatchParams = z.infer<typeof WorkDispatchParams>;

const WorkCatalogInput = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("skill"),
    name: z.string().min(1),
    description: z.string().default(""),
    manifestPath: z.string().min(1)
  }),
  z.object({
    kind: z.literal("cli"),
    name: z.string().min(1),
    description: z.string().default(""),
    executable: z.string().min(1),
    allowedSubcommands: z.array(z.string()).default([])
  }),
  z.object({
    kind: z.literal("knowledge"),
    name: z.string().min(1),
    description: z.string().default(""),
    roots: z.array(z.string().min(1)),
    readOnly: z.literal(true).default(true)
  }),
  z.object({
    kind: z.literal("local-tool"),
    name: z.string().min(1),
    description: z.string().default(""),
    toolNames: z.array(z.string().min(1))
  })
]);

export const WorkCatalogAddParams = z.object({
  workId: z.string().min(1),
  expectedRevision: z.number().int().nonnegative(),
  entry: WorkCatalogInput
});
export type WorkCatalogAddParams = z.infer<typeof WorkCatalogAddParams>;

export const WorkCatalogRemoveParams = z.object({
  workId: z.string().min(1),
  entryId: z.string().min(1),
  expectedRevision: z.number().int().nonnegative()
});
export type WorkCatalogRemoveParams = z.infer<typeof WorkCatalogRemoveParams>;

export const WorkContinueParams = z.object({ workId: z.string().min(1), eventId: z.string().min(1), inputAfterSeq: z.number().int().nonnegative().optional() });
export type WorkContinueParams = z.infer<typeof WorkContinueParams>;

export const WorkSnapshot = z.object({
  discussionRunning: z.boolean(),
  interruptions: z.array(z.object({ eventId: z.string(), agentId: z.string().optional(), taskId: z.string().optional(), error: z.string(), kind: z.enum(["discussion", "execution"]) })),
  throughSeq: z.number().int().nonnegative(),
  profile: WorkProfile,
  members: z.array(AgentView),
  catalog: WorkCatalog,
  events: z.array(WorkEvent),
  tasks: z.array(WorkTaskView),
  chat: z.array(WorkEvent).transform((events) => events.filter((event) => event.type === "chat.posted"))
});
export type WorkSnapshot = z.infer<typeof WorkSnapshot>;

export const WorkEventAppendedEvent = z.object({
  workId: z.string(),
  event: WorkEvent
});

export const WorkCatalogUpdatedEvent = z.object({
  workId: z.string(),
  catalog: WorkCatalog
});

export const SettingsSetParams = z.object({
  defaultToolPermission: ToolPermission.optional(),
  defaultModel: ModelRef.optional(),
  theme: Settings.shape.theme.optional(),
  language: Settings.shape.language,
  sidebar: Settings.shape.sidebar,
  openaiApiKey: z.string().nullable().optional(),
  anthropicApiKey: z.string().nullable().optional(),
  deepseekApiKey: z.string().nullable().optional()
});
export type SettingsSetParams = z.infer<typeof SettingsSetParams>;

export const AgentCreateParams = z.object({
  name: z.string().optional(),
  description: z.string().optional(),
  tags: AgentTags.optional(),
  avatarColor: z.string().optional(),
  avatarShape: z.string().optional(),
  avatarMaterial: z.string().optional(),
  model: ModelRef.optional(),
  workspace: AgentSettings.shape.workspace.optional()
});
export type AgentCreateParams = z.infer<typeof AgentCreateParams>;

export const AgentIdParams = z.object({ id: z.string() });
export type AgentIdParams = z.infer<typeof AgentIdParams>;

/** 合并语义：未给的字段不动；`name` 给了就不能为空。 */
export const AgentUpdateParams = z.object({
  id: z.string(),
  name: z.string().min(1).optional(),
  description: z.string().optional(),
  tags: AgentTags.optional(),
  avatarColor: z.string().optional(),
  avatarShape: z.string().optional(),
  avatarMaterial: z.string().optional(),
  model: ModelRef.optional(),
  workspace: AgentSettings.shape.workspace.optional(),
  execution: AgentSettings.shape.execution.optional(),
  hiddenFromSidebar: z.boolean().optional()
});
export type AgentUpdateParams = z.infer<typeof AgentUpdateParams>;

export const TranscriptQuery = z.object({
  id: z.string(),
  beforeSeq: z.number().int().optional(),
  limit: z.number().int().positive().optional()
});
export type TranscriptQuery = z.infer<typeof TranscriptQuery>;

export const TranscriptPage = z.object({
  id: z.string(),
  entries: z.array(TranscriptEvent),
  nextBeforeSeq: z.number().int().optional()
});
export type TranscriptPage = z.infer<typeof TranscriptPage>;

export const AgentSendParams = z.object({
  id: z.string(),
  content: z.string().min(1)
});
export type AgentSendParams = z.infer<typeof AgentSendParams>;

/** 回答提问卡片：value 原样成为用户消息，messageId 指回那张卡片供投影标选中项。 */
export const AgentAnswerWidgetParams = z.object({
  id: z.string(),
  messageId: z.string(),
  value: z.string().min(1)
});
export type AgentAnswerWidgetParams = z.infer<typeof AgentAnswerWidgetParams>;

export const AgentToolDecision = z.object({
  id: z.string(),
  toolCallId: z.string(),
  resolution: ToolResolution
});
export type AgentToolDecision = z.infer<typeof AgentToolDecision>;

export const AgentSnapshot = z.object({
  view: AgentView,
  events: z.array(TranscriptEvent),
  blocks: z.array(ViewBlock),
  live: LiveAssistant.nullable()
});
export type AgentSnapshot = z.infer<typeof AgentSnapshot>;

export const AgentUpdatedEvent = z.object({
  agent: AgentView
});
export type AgentUpdatedEvent = z.infer<typeof AgentUpdatedEvent>;

/** 事件都带 runId，供 UI 区分并行的 run。runId 不落盘。 */
export const AgentMessageDeltaEvent = z.object({
  agentId: z.string(),
  runId: z.string(),
  messageId: z.string(),
  delta: z.string(),
  part: z.enum(["text", "thinking"]).default("text")
});
export type AgentMessageDeltaEvent = z.infer<typeof AgentMessageDeltaEvent>;

export const AgentMessageCompletedEvent = z.object({
  agentId: z.string(),
  event: TranscriptEvent
});
export type AgentMessageCompletedEvent = z.infer<typeof AgentMessageCompletedEvent>;

export const AgentToolPendingEvent = z.object({
  agentId: z.string(),
  runId: z.string(),
  toolCallId: z.string(),
  name: z.string(),
  arguments: z.record(z.unknown()),
  action: z.enum(["read-file", "list-directory", "write-file", "run-command", "network"]),
  target: z.string(),
  justification: z.string().optional(),
  allowAlways: z.boolean().optional(),
  details: z.string().optional()
});
export type AgentToolPendingEvent = z.infer<typeof AgentToolPendingEvent>;

export const AgentToolStartedEvent = AgentToolPendingEvent.omit({ action: true, target: true });
export type AgentToolStartedEvent = z.infer<typeof AgentToolStartedEvent>;

export const AgentToolCompletedEvent = z.object({
  agentId: z.string(),
  runId: z.string(),
  toolCallId: z.string(),
  name: z.string(),
  ok: z.boolean(),
  output: z.string()
});
export type AgentToolCompletedEvent = z.infer<typeof AgentToolCompletedEvent>;

export const AgentErrorEvent = z.object({
  agentId: z.string(),
  runId: z.string(),
  code: z.number(),
  message: z.string()
});
export type AgentErrorEvent = z.infer<typeof AgentErrorEvent>;

/** `cancelled` 是第三档：UI 得能分清「跑完了」和「被用户掐了」。 */
export const AgentEndedEvent = z.object({
  agentId: z.string(),
  runId: z.string(),
  status: z.enum(["idle", "error", "cancelled"])
});
export type AgentEndedEvent = z.infer<typeof AgentEndedEvent>;

export type HostHello = { name: "nuum-host"; version: string };

export const PublicSettingsSchema = PublicSettings;
export const ToolDefinitionList = z.array(ToolDefinition);
export const AgentSettingsSchema = AgentSettings;
