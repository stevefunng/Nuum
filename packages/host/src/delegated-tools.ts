import {
  DELEGATED_TOOL_DEFINITIONS,
  CreateTaskParams, ClaimTaskParams, ReadTaskParams,
  DelegateWorkParams,
  DelegatedToolNames,
  ReadAgentTranscriptParams,
  CheckAgentParams,
  ReadWorkTimelineParams,
  RunWorkCliParams,
  SendMessageParams,
  WorkSendMessageParams,
  SendToAgentParams,
  StopAgentParams,
  HandoffTaskParams,
  PostToWorkParams,
  UpdateAgentParams,
  UpdateStateParams,
  CreateAgentParams,
  type ToolDefinition
} from "@nuum/protocol";
import type { RunContext } from "./run-context.js";

/**
 * Host 自己执行的工具。Kernel 只拿到 definition，撞上就委派过来（§3.2）。
 */
export interface DelegatedTool {
  definition: ToolDefinition;
  /** 省略时只对私人 direct run 开放；跨领域能力必须逐个显式声明。 */
  runKinds?: readonly RunContext["kind"][];
  execute(args: Record<string, unknown>, context: DelegatedToolContext): Promise<string>;
}

export interface DelegatedToolContext {
  agentId: string;
  assistantId: string;
  toolCallId: string;
  runContext: RunContext;
}

/**
 * Host 执行的产品工具（§5.2）。它们没有本地 `execute`，Kernel 撞上就走
 * `turn.tool.delegate` 委派过来。
 *
 * 这里只负责「校验参数 → 调 Host 能力 → 回一句给模型看的话」。真正的副作用
 * 都在 `HostRuntime` 上，这样工具层没有自己的状态。
 */
export interface DelegateHost {
  createTaskFromModel(agentId: string, params: CreateTaskParams, context: DelegatedToolContext): Promise<string>;
  claimTask(agentId: string, params: ClaimTaskParams, context: DelegatedToolContext): Promise<string>;
  readTask(agentId: string, params: ReadTaskParams, context: DelegatedToolContext): Promise<string>;
  sendMessage(
    agentId: string,
    params: SendMessageParams,
    source: Pick<DelegatedToolContext, "assistantId" | "toolCallId">
  ): Promise<string>;
  sendWorkMessage(agentId: string, params: WorkSendMessageParams, context: DelegatedToolContext): Promise<string>;
  updateState(agentId: string, params: UpdateStateParams): Promise<string>;
  createAgentFromModel(agentId: string, params: CreateAgentParams): Promise<string>;
  updateAgentFromModel(agentId: string, params: UpdateAgentParams): Promise<string>;
  sendToAgent(agentId: string, params: SendToAgentParams): Promise<string>;
  readAgentTranscript(agentId: string, params: ReadAgentTranscriptParams): Promise<string>;
  checkAgent(agentId: string, params: CheckAgentParams): Promise<string>;
  stopAgent(agentId: string, params: StopAgentParams): Promise<string>;
  postToWork(agentId: string, params: PostToWorkParams, context: DelegatedToolContext): Promise<string>;
  handoffTask(agentId: string, params: HandoffTaskParams, context: DelegatedToolContext): Promise<string>;
  readWorkTimeline(agentId: string, params: ReadWorkTimelineParams, context: DelegatedToolContext): Promise<string>;
  runWorkCli(agentId: string, params: RunWorkCliParams, context: DelegatedToolContext): Promise<string>;
  delegateWork(agentId: string, params: DelegateWorkParams, context: DelegatedToolContext): Promise<string>;
}

type Handler = (args: Record<string, unknown>, context: DelegatedToolContext) => Promise<string>;

const DEFAULT_RUN_KINDS: readonly RunContext["kind"][] = ["direct"];
const WORK_TOOL_NAMES = new Set<string>([
  "CreateTask", "ClaimTask", "ReadTask",
  DelegatedToolNames.postToWork,
  DelegatedToolNames.handoffTask,
  DelegatedToolNames.readWorkTimeline,
  DelegatedToolNames.runWorkCli,
  DelegatedToolNames.delegateWork
]);

export function isDelegatedToolAvailable(tool: DelegatedTool, context: RunContext): boolean {
  return (tool.runKinds ?? DEFAULT_RUN_KINDS).includes(context.kind);
}

export function delegatedToolsForRunContext(
  tools: Iterable<DelegatedTool>,
  context: RunContext
): DelegatedTool[] {
  return [...tools].filter((tool) => isDelegatedToolAvailable(tool, context))
    .filter((tool) => context.kind !== "work" || !["PostToWork", "HandoffTask"].includes(tool.definition.name))
    .map((tool) => context.kind === "work" && tool.definition.name === "SendMessage" ? {
      ...tool,
      definition: {
        ...tool.definition,
        description: "Send a public message to this room as yourself. Include cardAction so the summary and card update commit together: review by a worker returns results to the permanent owner; review by the owner requests human acceptance. blocked pauses the card until human confirmation. Stop after review or blocked. Silence is allowed when you have nothing useful to add.",
        inputSchema: { type: "object", required: ["type", "content"], properties: {
          type: { type: "string", enum: ["text"] }, content: { type: "string" },
          cardAction: { type: "object", required: ["status"], properties: {
            status: { type: "string", enum: ["review", "blocked"] }, blocker_reason: { type: "string" },
            expectedRevision: { type: "integer" }, deliverables: { type: "array", items: { type: "object", required: ["name", "uri"], properties: { name: { type: "string" }, uri: { type: "string" }, mime_type: { type: "string" } } } }
          } }
        } }
      }
    } : tool);
}

/**
 * 工具集由「handler 在不在」决定，不由一份写死的名单决定。这样一个工具要么
 * 真能跑、要么模型根本看不见它 —— 不存在「声明了但调用就报没实现」这种状态。
 */
export function createDelegatedTools(host: Partial<DelegateHost>): DelegatedTool[] {
  const handlers: Record<string, Handler | undefined> = {
    CreateTask: host.createTaskFromModel ? (args, context) => host.createTaskFromModel!(context.agentId, CreateTaskParams.parse(args), context) : undefined,
    ClaimTask: host.claimTask ? (args, context) => host.claimTask!(context.agentId, ClaimTaskParams.parse(args), context) : undefined,
    ReadTask: host.readTask ? (args, context) => host.readTask!(context.agentId, ReadTaskParams.parse(args), context) : undefined,
    [DelegatedToolNames.sendMessage]: host.sendMessage
      ? (args, context) => context.runContext.kind === "work"
        ? host.sendWorkMessage!(context.agentId, WorkSendMessageParams.parse(args), context)
        : host.sendMessage!(context.agentId, SendMessageParams.parse(args), context)
      : undefined,
    [DelegatedToolNames.updateState]: host.updateState
      ? (args, context) => host.updateState!(context.agentId, UpdateStateParams.parse(args))
      : undefined,
    [DelegatedToolNames.createAgent]: host.createAgentFromModel
      ? (args, context) => host.createAgentFromModel!(context.agentId, CreateAgentParams.parse(args))
      : undefined,
    [DelegatedToolNames.updateAgent]: host.updateAgentFromModel
      ? (args, context) => host.updateAgentFromModel!(context.agentId, UpdateAgentParams.parse(args))
      : undefined,
    [DelegatedToolNames.sendToAgent]: host.sendToAgent
      ? (args, context) => host.sendToAgent!(context.agentId, SendToAgentParams.parse(args))
      : undefined,
    [DelegatedToolNames.readAgentTranscript]: host.readAgentTranscript
      ? (args, context) => host.readAgentTranscript!(context.agentId, ReadAgentTranscriptParams.parse(args))
      : undefined,
    [DelegatedToolNames.checkAgent]: host.checkAgent
      ? (args, context) => host.checkAgent!(context.agentId, CheckAgentParams.parse(args))
      : undefined,
    [DelegatedToolNames.stopAgent]: host.stopAgent
      ? (args, context) => host.stopAgent!(context.agentId, StopAgentParams.parse(args))
      : undefined,
    [DelegatedToolNames.postToWork]: host.postToWork
      ? (args, context) => host.postToWork!(context.agentId, PostToWorkParams.parse(args), context)
      : undefined,
    [DelegatedToolNames.handoffTask]: host.handoffTask
      ? (args, context) => host.handoffTask!(context.agentId, HandoffTaskParams.parse(args), context)
      : undefined,
    [DelegatedToolNames.readWorkTimeline]: host.readWorkTimeline
      ? (args, context) => host.readWorkTimeline!(context.agentId, ReadWorkTimelineParams.parse(args), context)
      : undefined,
    [DelegatedToolNames.runWorkCli]: host.runWorkCli
      ? (args, context) => host.runWorkCli!(context.agentId, RunWorkCliParams.parse(args), context)
      : undefined,
    [DelegatedToolNames.delegateWork]: host.delegateWork
      ? (args, context) => host.delegateWork!(context.agentId, DelegateWorkParams.parse(args), context)
      : undefined
  };

  return DELEGATED_TOOL_DEFINITIONS.filter(
    (definition: ToolDefinition) => handlers[definition.name] !== undefined
  ).map((definition: ToolDefinition) => ({
    definition,
    ...(definition.name === "SendMessage" ? { runKinds: ["direct", "work"] as const } : WORK_TOOL_NAMES.has(definition.name)
      ? { runKinds: ["work"] as const }
      : {}),
    execute: async (args, context) => {
      try {
        return await handlers[definition.name]!(args, context);
      } catch (error) {
        // schema 错要说清哪儿错了 —— 模型只能靠这句话改参数重试。
        throw new Error(describeToolFailure(definition.name, error));
      }
    }
  }));
}

function describeToolFailure(name: string, error: unknown): string {
  if (error instanceof Error && error.name === "ZodError") {
    return `${name}: invalid arguments — ${compactZodMessage(error.message)}`;
  }
  return error instanceof Error ? error.message : String(error);
}

function compactZodMessage(raw: string): string {
  try {
    const issues = JSON.parse(raw) as { path?: (string | number)[]; message?: string }[];
    return issues
      .map((issue) => `${(issue.path ?? []).join(".") || "(root)"}: ${issue.message ?? "invalid"}`)
      .join("; ");
  } catch {
    return raw.replace(/\s+/g, " ").slice(0, 300);
  }
}
