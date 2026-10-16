import { z } from "zod";
import {
  ChatMessage,
  LocalToolAction,
  ModelRef,
  Secrets,
  ToolApproval,
  ToolDefinition,
  ToolPermission,
  ToolResolution
} from "./domain.js";

export const KernelMethods = {
  sysHello: "sys.hello",
  sysPing: "sys.ping",
  sysShutdown: "sys.shutdown",
  turnStart: "turn.start",
  turnProvideContext: "turn.provideContext",
  turnCancel: "turn.cancel",
  turnApproveTool: "turn.approveTool",
  turnDenyTool: "turn.denyTool",
  turnProvideToolResult: "turn.provideToolResult",
  shellDispose: "shell.dispose",
  summarizeRun: "summarize.run",
  summarizeCancel: "summarize.cancel",
  toolsList: "tools.list"
} as const;

export const KernelEvents = {
  turnContext: "turn.context",
  turnDelta: "turn.delta",
  turnToolPending: "turn.tool.pending",
  turnToolStarted: "turn.tool.started",
  turnToolDelegate: "turn.tool.delegate",
  turnToolCompleted: "turn.tool.completed",
  turnError: "turn.error",
  turnEnded: "turn.ended"
} as const;

/**
 * Kernel 完全不知道 agent 存在，只认 `runId` —— 一次唤醒到收束的内存态调度键。
 * `runId → agentId` 的映射由 Host 自己维护。
 */
export const TurnStartParams = z.object({
  runId: z.string(),
  messages: z.array(ChatMessage),
  contextWindow: z.number().positive().optional(),
  model: ModelRef,
  roots: z.object({
    home: z.string(),
    project: z.string().nullable(),
    scratch: z.string(),
    terminals: z.string(),
    denied: z.array(z.string()),
    readOnly: z.array(z.string()).optional()
  }),
  toolPermission: ToolPermission,
  approvals: z.array(ToolApproval).default([]),
  refused: z.array(ToolApproval).default([]),
  /** Kernel 自己执行的工具，按名字从本地 registry 取。 */
  localToolNames: z.array(z.string()),
  /**
   * Host 执行的工具。这里必须给完整 definition 而不只是名字：Kernel 的 registry
   * 里没有它们，只传名字会被过滤掉，模型也就看不见这个工具、永远不会调。
   */
  delegatedTools: z.array(ToolDefinition).default([]),
  /**
   * 「发声」工具名 —— 模型对用户可见的出口（direct run 是 SendMessage，work run
   * 是 PostToWork/HandoffTask）。turn 循环的静默提醒按它计数；缺省 SendMessage。
   */
  voiceToolNames: z.array(z.string()).default(["SendMessage"]),
  secrets: Secrets
});
export type TurnStartParams = z.infer<typeof TurnStartParams>;

export const TurnRunParams = z.object({
  runId: z.string()
});
export type TurnRunParams = z.infer<typeof TurnRunParams>;

export const ShellDisposeParams = z.object({ terminals: z.string() });
export type ShellDisposeParams = z.infer<typeof ShellDisposeParams>;

export const TurnToolDecision = z.object({
  runId: z.string(),
  toolCallId: z.string(),
  resolution: ToolResolution
});
export type TurnToolDecision = z.infer<typeof TurnToolDecision>;

export const TurnToolResult = z.object({
  runId: z.string(),
  toolCallId: z.string(),
  ok: z.boolean(),
  output: z.string(),
  endTurn: z.boolean().optional()
});
export type TurnToolResult = z.infer<typeof TurnToolResult>;

/**
 * 一次无工具、不落盘、不发事件的单发模型调用。压缩与记忆抽取都要调模型，而
 * Kernel 是唯一持有 model port 的地方 —— Host 绝不直接碰模型（§3.2）。
 */
export const SummarizeRunParams = z.object({
  /** 只作关联标识：这条调用独立于 turn runs，通过 summarize.cancel 取消。 */
  runId: z.string(),
  systemPrompt: z.string(),
  timeoutMs: z.number().positive().optional(),
  maxOutputTokens: z.number().int().positive().optional(),
  messages: z.array(ChatMessage),
  model: ModelRef,
  secrets: Secrets
});
export type SummarizeRunParams = z.infer<typeof SummarizeRunParams>;

export const SummarizeRunResult = z.object({ text: z.string() });
export type SummarizeRunResult = z.infer<typeof SummarizeRunResult>;

export const TurnDeltaEvent = z.object({
  runId: z.string(),
  messageId: z.string(),
  delta: z.string(),
  part: z.enum(["text", "thinking"]).optional()
});
export type TurnDeltaEvent = z.infer<typeof TurnDeltaEvent>;

export const TurnToolPendingEvent = z.object({
  runId: z.string(),
  toolCallId: z.string(),
  name: z.string(),
  arguments: z.record(z.unknown()),
  mutating: z.boolean(),
  action: LocalToolAction,
  target: z.string()
});
export type TurnToolPendingEvent = z.infer<typeof TurnToolPendingEvent>;

export const TurnToolStartedEvent = z.object({
  runId: z.string(),
  toolCallId: z.string(),
  name: z.string(),
  arguments: z.record(z.unknown())
});
export type TurnToolStartedEvent = z.infer<typeof TurnToolStartedEvent>;

export const TurnToolDelegateEvent = z.object({
  runId: z.string(),
  toolCallId: z.string(),
  name: z.string(),
  arguments: z.record(z.unknown())
});
export type TurnToolDelegateEvent = z.infer<typeof TurnToolDelegateEvent>;

export const TurnToolCompletedEvent = z.object({
  runId: z.string(),
  toolCallId: z.string(),
  name: z.string(),
  ok: z.boolean(),
  output: z.string()
});
export type TurnToolCompletedEvent = z.infer<typeof TurnToolCompletedEvent>;

export const TurnErrorEvent = z.object({
  runId: z.string(),
  code: z.number(),
  message: z.string()
});
export type TurnErrorEvent = z.infer<typeof TurnErrorEvent>;

export const TurnEndedEvent = z.object({
  runId: z.string(),
  status: z.enum(["idle", "error", "cancelled"])
});
export type TurnEndedEvent = z.infer<typeof TurnEndedEvent>;

export type KernelHello = { name: "nuum-kernel"; version: "0.1.0" };
export const KernelToolList = z.array(ToolDefinition);

export const TurnContextResult = z.object({
  runId: z.string(), requestId: z.string(), messages: z.array(ChatMessage).optional(), error: z.string().optional()
});
export type TurnContextResult = z.infer<typeof TurnContextResult>;
