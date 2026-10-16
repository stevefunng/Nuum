import { z } from "zod";
import { ChatMessage } from "./domain.js";

export const AssistantPart = z.discriminatedUnion("type", [
  z.object({ type: z.literal("thinking"), text: z.string() }),
  z.object({ type: z.literal("text"), text: z.string() }),
  z.object({
    type: z.literal("tool_call"),
    id: z.string(),
    name: z.string(),
    arguments: z.record(z.unknown())
  })
]);
export type AssistantPart = z.infer<typeof AssistantPart>;

/**
 * 唤醒源。用户唤醒不带 source（就是 `user` 事件），别的来源都是 `wake`。
 */
export const WakeSource = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("agent"),
    fromId: z.string(),
    fromName: z.string(),
    priority: z.boolean().optional()
  }),
  z.object({
    kind: z.literal("work"),
    workId: z.string(),
    workName: z.string(),
    bridgeId: z.string(),
    taskId: z.string().optional(),
    roomInput: z.object({
      membershipRevision: z.number().int(),
      fromSeq: z.number().int(),
      throughSeq: z.number().int(),
      messageIds: z.array(z.string()),
      epoch: z.number().int().nonnegative().optional(),
      mode: z.enum(["background", "continuation"]).optional()
    }).optional()
  }),
  // 本版不产生，占位给下版的定时唤醒。
  z.object({ kind: z.literal("routine"), routineId: z.string(), routineName: z.string() })
]);
export type WakeSource = z.infer<typeof WakeSource>;

/**
 * SendMessage 的载荷 —— 助手对用户的唯一可见出口。
 * 本版支持 text / attachment / widget。
 */

/** 随文本气泡内嵌的图片。本机绝对路径，UI 直接 file:// 读。 */
export const OutboundImage = z.object({
  path: z.string(),
  /** 悬停与全屏查看时的说明文字，也念给读屏。 */
  alt: z.string().optional()
});
export type OutboundImage = z.infer<typeof OutboundImage>;

/** 提问卡片的一个选项。value 缺省即 label；它会原样成为用户的回复文本。 */
export const WidgetOption = z.object({
  label: z.string().min(1),
  value: z.string().optional(),
  description: z.string().optional(),
  style: z.enum(["default", "primary", "danger"]).optional()
});
export type WidgetOption = z.infer<typeof WidgetOption>;

/** 结构化提问卡片：模型发选项问题，用户点选后选项值作为下一条用户消息回来。 */
export const WidgetPayload = z.object({
  prompt: z.string().min(1),
  helpText: z.string().optional(),
  options: z.array(WidgetOption).min(1).max(6),
  /** 允许用户不选选项、自由输入回答。 */
  allowCustom: z.boolean().optional()
});
export type WidgetPayload = z.infer<typeof WidgetPayload>;

/**
 * 旧版 text 载荷：字段名 `text`、images 是纯路径字符串。在解析边界统一规范化，
 * 让仓库其余代码只面对新形状。
 */
function normalizeOutboundPayload(payload: unknown): unknown {
  if (typeof payload !== "object" || payload === null) return payload;
  const raw = payload as Record<string, unknown>;
  if (raw.type !== "text") return payload;
  const normalized: Record<string, unknown> = { ...raw };
  if (typeof raw.text === "string" && raw.content === undefined) normalized.content = raw.text;
  if (Array.isArray(raw.images)) {
    normalized.images = raw.images.map((image) =>
      typeof image === "string" ? { path: image } : image
    );
  }
  return normalized;
}

export const OutboundMessage = z.preprocess(
  normalizeOutboundPayload,
  z.union([
    z.object({
      type: z.literal("text"),
      content: z.string(),
      images: z.array(OutboundImage).optional()
    }),
    z.object({
      type: z.literal("attachment"),
      path: z.string(),
      caption: z.string().optional()
    }),
    z.object({
      type: z.literal("widget"),
      widget: WidgetPayload
    }),
    // 旧版 widget 是 name+props 透传（UI 如实渲染收到的内容）。保留该形状使
    // 旧转录可读；UI 按 widget 字段是对象还是字符串区分两种渲染。
    z.object({
      type: z.literal("widget"),
      widget: z.string(),
      props: z.record(z.unknown()).optional()
    })
  ])
);
export type OutboundMessage = z.infer<typeof OutboundMessage>;

export const TranscriptEvent = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("user"),
    id: z.string(),
    seq: z.number().int(),
    createdAt: z.number(),
    text: z.string(),
    /**
     * 这条用户消息是对某个提问卡片（widget message 事件）的回答，值是那张卡
     * 的事件 id。投影据此在卡片上标出选中项；旧转录与普通消息没有该字段。
     */
    widgetAnswerTo: z.string().optional()
  }),
  z.object({
    type: z.literal("wake"),
    id: z.string(),
    seq: z.number().int(),
    createdAt: z.number(),
    source: WakeSource,
    text: z.string(),
    hops: z.number().int().default(0)
  }),
  z.object({
    type: z.literal("assistant"),
    id: z.string(),
    seq: z.number().int(),
    createdAt: z.number(),
    parts: z.array(AssistantPart)
  }),
  z.object({
    type: z.literal("tool"),
    id: z.string(),
    seq: z.number().int(),
    createdAt: z.number(),
    /** 产生这次调用的 assistant 事件。旧转录没有该字段，投影时回退到 toolCallId。 */
    assistantId: z.string().optional(),
    toolCallId: z.string(),
    name: z.string(),
    content: z.string(),
    ok: z.boolean().optional(),
    /** 输出过大时截断进事件，全文另存这个绝对路径（§2.Q2）。 */
    spillPath: z.string().optional()
  }),
  z.object({
    type: z.literal("message"),
    id: z.string(),
    seq: z.number().int(),
    createdAt: z.number(),
    /**
     * 用户可见投递的因果来源。message 是 SendMessage 的投递事件，
     * 不是第二条模型 assistant 消息。可选是为了原样兼容已落盘的旧 JSONL。
     */
    assistantId: z.string().optional(),
    toolCallId: z.string().optional(),
    payload: OutboundMessage
  }),
  z.object({
    type: z.literal("compact"),
    id: z.string(),
    seq: z.number().int(),
    createdAt: z.number(),
    epoch: z.number().int(),
    /** 摘要覆盖到这个 seq（含）。 */
    throughSeq: z.number().int(),
    /** 保留尾部从这个 seq 起（含）。 */
    tailFromSeq: z.number().int(),
    summary: z.string(),
    activeRequest: z.string().optional(),
    roomInputs: z.array(z.object({ workId: z.string(), membershipRevision: z.number().int(), throughSeq: z.number().int() })).optional()
  }),
  z.object({
    type: z.literal("profile"),
    id: z.string(),
    seq: z.number().int(),
    createdAt: z.number(),
    patch: z.object({ name: z.string().optional(), description: z.string().optional(), tags: z.array(z.string()).optional() })
  })
]);
export type TranscriptEvent = z.infer<typeof TranscriptEvent>;

/**
 * 追加事件时不由调用方给 seq —— 序号由 AgentStore 用内存里的 lastSeq 自增。
 * 这样「为了算下一个序号而整文件重读」在类型层面就不可能再发生。
 */
type WithoutSeq<T> = T extends unknown ? Omit<T, "seq"> : never;
export type TranscriptDraft = WithoutSeq<TranscriptEvent>;

export const LiveAssistant = z.object({
  messageId: z.string(),
  parts: z.array(AssistantPart)
});
export type LiveAssistant = z.infer<typeof LiveAssistant>;

export const ToolView = z.object({
  id: z.string(),
  name: z.string(),
  arguments: z.record(z.unknown()),
  output: z.string().optional(),
  status: z.enum(["pending", "ok", "error"])
});
export type ToolView = z.infer<typeof ToolView>;

export const ViewBlock = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("user"),
    id: z.string(),
    text: z.string(),
    /** 对提问卡片的回答：值是被回答的 message 块 id，UI 据此标出选中项。 */
    widgetAnswerTo: z.string().optional()
  }),
  /**
   * 助手的「工作痕迹」：thinking 与非 SendMessage 工具卡。普通
   * assistant text 是模型私有 scratchpad，不进用户 UI 投影。
   */
  z.object({
    type: z.literal("assistant"),
    id: z.string(),
    thinking: z.string(),
    tools: z.array(ToolView),
    live: z.boolean().optional()
  }),
  /** SendMessage 产出的真正助手气泡。 */
  z.object({
    type: z.literal("message"),
    id: z.string(),
    payload: OutboundMessage
  }),
  /** Agent 间消息的用户可见投影。事实仍来自 wake / SendToAgent 调用，不另写事件。 */
  z.object({
    type: z.literal("peer"),
    id: z.string(),
    direction: z.enum(["inbound", "outbound"]),
    agentId: z.string(),
    agentName: z.string(),
    text: z.string(),
    priority: z.boolean()
  }),
  /** 系统条：来自别的 agent 的唤醒、agent 自改人格、上文已压缩。 */
  z.object({
    type: z.literal("notice"),
    id: z.string(),
    kind: z.enum(["wake", "profile", "compact"]),
    text: z.string()
  })
]);
export type ViewBlock = z.infer<typeof ViewBlock>;

export const AgentProjection = z.object({
  blocks: z.array(ViewBlock)
});
export type AgentProjection = z.infer<typeof AgentProjection>;

export function maxTranscriptSeq(events: readonly TranscriptEvent[]): number {
  return events.reduce((max, event) => Math.max(max, event.seq), 0);
}

export function eventFromChatMessage(message: ChatMessage): TranscriptEvent | null {
  if (message.role === "system") return null;
  if (message.role === "user") {
    return {
      type: "user",
      id: message.id,
      seq: message.seq,
      createdAt: message.createdAt,
      text: message.content
    };
  }
  if (message.role === "tool") {
    return {
      type: "tool",
      id: message.id,
      seq: message.seq,
      createdAt: message.createdAt,
      toolCallId: message.toolCallId ?? "",
      name: message.name ?? "",
      content: message.content
    };
  }
  const parts: AssistantPart[] = [];
  if (message.thinking) parts.push({ type: "thinking", text: message.thinking });
  if (message.content) parts.push({ type: "text", text: message.content });
  for (const call of message.toolCalls ?? []) {
    parts.push({ type: "tool_call", id: call.id, name: call.name, arguments: call.arguments });
  }
  return {
    type: "assistant",
    id: message.id,
    seq: message.seq,
    createdAt: message.createdAt,
    parts
  };
}

export function parseTranscriptLine(raw: unknown): TranscriptEvent | null {
  if (raw && typeof raw === "object" && "type" in raw && !("role" in raw)) {
    return TranscriptEvent.parse(raw);
  }
  return eventFromChatMessage(ChatMessage.parse(raw));
}

/**
 * 单行容错入口：坏行返回 null 而不是抛。转录读取必须逐行走这里 —— 让一行坏 JSON
 * 冒泡到整份读取的 catch，会把整段历史读成空。
 */
export function tryParseTranscriptLine(line: string): TranscriptEvent | null {
  try {
    return parseTranscriptLine(JSON.parse(line) as unknown);
  } catch {
    return null;
  }
}

export function appendAssistantDelta(
  parts: readonly AssistantPart[],
  kind: "text" | "thinking",
  delta: string
): AssistantPart[] {
  const next = [...parts];
  const last = next.at(-1);
  if (last && last.type === kind) {
    next[next.length - 1] = { type: kind, text: last.text + delta };
    return next;
  }
  next.push({ type: kind, text: delta });
  return next;
}

export function appendAssistantToolCall(
  parts: readonly AssistantPart[],
  call: { id: string; name: string; arguments: Record<string, unknown> }
): AssistantPart[] {
  return [...parts, { type: "tool_call", id: call.id, name: call.name, arguments: call.arguments }];
}

function joinParts(parts: readonly AssistantPart[], kind: "text" | "thinking"): string {
  return parts
    .filter((part): part is { type: "text" | "thinking"; text: string } => part.type === kind)
    .map((part) => part.text)
    .join("");
}

function assistantBlock(
  id: string,
  parts: readonly AssistantPart[],
  results: Map<string, { content: string; ok?: boolean }>,
  live?: boolean
): ViewBlock {
  const tools = parts
    .filter((part): part is Extract<AssistantPart, { type: "tool_call" }> => part.type === "tool_call")
    // 消息工具由 message / peer 气泡投影，不再同时渲染一张内部工具卡；
    // 只有 SendToAgent 真失败时才退回工具状态，让错误不会被吞掉。
    .filter((part) => {
      if (part.name === "SendMessage") return false;
      if (part.name !== "SendToAgent") return true;
      const result = results.get(part.id);
      // 未收到回执时仍是一条运行中的工具活动；只有确认投递成功后才换成 peer 气泡。
      return !result || result.ok === false;
    })
    .map((part) => {
      const result = results.get(part.id);
      return {
        id: part.id,
        name: part.name,
        arguments: part.arguments,
        output: result?.content,
        status: result ? (result.ok === false ? "error" as const : "ok" as const) : "pending" as const
      };
    });
  return {
    type: "assistant",
    id,
    thinking: joinParts(parts, "thinking"),
    tools,
    ...(live ? { live: true } : {})
  };
}

export function projectAgent(
  events: readonly TranscriptEvent[],
  live?: LiveAssistant | null
): AgentProjection {
  const blocks: ViewBlock[] = [];
  const results = new Map<string, { content: string; ok?: boolean }>();
  const knownCalls = new Set<string>();
  for (const event of events) {
    if (event.type === "assistant") {
      for (const part of event.parts) {
        if (part.type !== "tool_call") continue;
        knownCalls.add(part.id);
        knownCalls.add(`${event.id}\0${part.id}`);
      }
    }
    if (event.type === "tool") {
      const result = { content: event.content, ok: event.ok };
      if (!results.has(event.toolCallId)) results.set(event.toolCallId, result);
      if (event.assistantId) results.set(`${event.assistantId}\0${event.toolCallId}`, result);
    }
  }

  for (const event of events) {
    if (event.type === "user") {
      blocks.push({
        type: "user",
        id: event.id,
        text: event.text,
        ...(event.widgetAnswerTo ? { widgetAnswerTo: event.widgetAnswerTo } : {})
      });
      continue;
    }
    if (event.type === "wake") {
      if (event.source.kind === "agent") {
        blocks.push({
          type: "peer",
          id: event.id,
          direction: "inbound",
          agentId: event.source.fromId,
          agentName: event.source.fromName,
          text: event.text,
          priority: event.source.priority ?? false
        });
      } else {
        blocks.push({ type: "notice", id: event.id, kind: "wake", text: event.source.kind === "work" ? `Participated in room: ${event.source.workName}` : describeWake(event) });
      }
      continue;
    }
    if (event.type === "message") {
      blocks.push({ type: "message", id: event.id, payload: event.payload });
      continue;
    }
    if (event.type === "compact") {
      blocks.push({
        type: "notice",
        id: event.id,
        kind: "compact",
        text: `Earlier messages were summarized to fit the context window. The originals are still on disk.`
      });
      continue;
    }
    if (event.type === "profile") {
      blocks.push({ type: "notice", id: event.id, kind: "profile", text: describeProfilePatch(event.patch) });
      continue;
    }
    if (event.type === "assistant") {
      const causalResults = new Map<string, { content: string; ok?: boolean }>();
      for (const part of event.parts) {
        if (part.type !== "tool_call") continue;
        const result = results.get(`${event.id}\0${part.id}`) ?? results.get(part.id);
        if (result) causalResults.set(part.id, result);
      }
      const block = assistantBlock(event.id, event.parts, causalResults);
      if (block.type === "assistant" && (block.thinking || block.tools.length > 0)) blocks.push(block);
      blocks.push(...outboundPeerBlocks(event.parts, causalResults));
      continue;
    }
    if (knownCalls.has(`${event.assistantId ?? ""}\0${event.toolCallId}`) || knownCalls.has(event.toolCallId)) {
      continue;
    }
    blocks.push({
      type: "assistant",
      id: event.id,
      thinking: "",
      tools: [
        {
          id: event.toolCallId,
          name: event.name,
          arguments: {},
          output: event.content,
          status: event.ok === false ? "error" : "ok"
        }
      ]
    });
  }
  if (live && !blocks.some((block) => block.type === "assistant" && block.id === live.messageId)) {
    const block = assistantBlock(live.messageId, live.parts, new Map(), true);
    if (block.type === "assistant" && (block.thinking || block.tools.length > 0)) blocks.push(block);
    blocks.push(...outboundPeerBlocks(live.parts, new Map()));
  }
  return { blocks };
}

function outboundPeerBlocks(
  parts: readonly AssistantPart[],
  results: Map<string, { content: string; ok?: boolean }>
): Extract<ViewBlock, { type: "peer" }>[] {
  return parts.flatMap((part) => {
    if (part.type !== "tool_call" || part.name !== "SendToAgent") return [];
    const agentId = stringArgument(part.arguments, "agent_id");
    const text = stringArgument(part.arguments, "message");
    const result = results.get(part.id);
    // tool_call 只是发送意图；成功回执才是可投影为“已发出消息”的事实。
    if (!agentId || !text || !result || result.ok === false) return [];
    return [{
      type: "peer" as const,
      id: part.id,
      direction: "outbound" as const,
      agentId,
      agentName: agentNameFromDelivery(result?.content) ?? agentId,
      text,
      priority: part.arguments.priority === true
    }];
  });
}

function stringArgument(arguments_: Record<string, unknown>, key: string): string | null {
  const value = arguments_[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function agentNameFromDelivery(content?: string): string | null {
  if (!content) return null;
  const match = /^(?:Sent|Delivered) to (.+?)(?: as priority|,|\.|$)/.exec(content);
  return match?.[1]?.trim() || null;
}

export function describeWake(event: Extract<TranscriptEvent, { type: "wake" }>): string {
  if (event.source.kind === "agent") {
    const priority = event.source.priority ? " (priority)" : "";
    return `From ${event.source.fromName}${priority}: ${event.text}`;
  }
  if (event.source.kind === "work") {
    const task = event.source.taskId ? ` task ${event.source.taskId}` : "";
    return `From Work ${event.source.workName}${task}: ${event.text}`;
  }
  return `Routine ${event.source.routineName}: ${event.text}`;
}

function describeProfilePatch(patch: { name?: string; description?: string; tags?: string[] }): string {
  const parts: string[] = [];
  if (patch.name !== undefined) parts.push(`name to "${patch.name}"`);
  if (patch.description !== undefined) parts.push("its description");
  if (patch.tags !== undefined) parts.push("its tags");
  return parts.length > 0 ? `This agent changed ${parts.join(" and ")}.` : "This agent changed its profile.";
}
