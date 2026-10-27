import {
  DEFAULT_AGENT_NAME,
  estimateModelTokens,
  maxTranscriptSeq,
  type ChatMessage,
  type OutboundMessage,
  type TranscriptEvent
} from "@nuum/protocol";

const INTERRUPTED_TOOL = "Tool call was interrupted and did not return a result.";

export const COMPACTION_PROMPT = [
  "Summarize the conversation history for a future continuation.",
  "Preserve the user's goals, constraints, decisions, completed work, unresolved",
  "items, exact file paths, commands, errors, and facts needed to continue.",
  "Be compact but concrete. Do not mention this instruction or invent details.",
  "Use short sections: Goal, Decisions, Completed, Open work, Key details.",
  "Separate private conversation from each room by roomId. Preserve room decisions, promises, unresolved questions and message references.",
  "Distinguish proposals, commitments and verified results, and who owns each. Update the previous summary; do not discard still relevant commitments.",
  "Keep the current request and unfinished tool work explicit. Never invent omitted facts."
].join("\n");

export function repairTranscript(events: TranscriptEvent[]): {
  events: TranscriptEvent[];
  injected: TranscriptEvent[];
} {
  const out: TranscriptEvent[] = [];
  const injected: TranscriptEvent[] = [];
  let nextSeq = maxTranscriptSeq(events) + 1;

  // JSONL 记录事实发生顺序，不承担 provider 的相邻格式。先索引所有结果，
  // 再按 assistantId + toolCallId 把它们放回发起调用的 assistant 后面。
  // 旧行没有 assistantId，才回退到同 toolCallId 的最早未用结果。
  const results = events.filter(
    (event): event is Extract<TranscriptEvent, { type: "tool" }> => event.type === "tool"
  );
  const deliveries = events.filter(
    (event): event is Extract<TranscriptEvent, { type: "message" }> => event.type === "message"
  );
  const usedResults = new Set<string>();

  for (const event of events) {
    if (event.type === "tool") continue;
    out.push(event);
    if (event.type !== "assistant") continue;

    const calls = event.parts.filter(
      (part): part is Extract<(typeof event.parts)[number], { type: "tool_call" }> => part.type === "tool_call"
    );
    for (const call of calls) {
      const result = results.find(
        (candidate) =>
          !usedResults.has(candidate.id) &&
          candidate.toolCallId === call.id &&
          candidate.assistantId === event.id
      ) ?? results.find(
        (candidate) =>
          !usedResults.has(candidate.id) &&
          candidate.toolCallId === call.id &&
          candidate.assistantId === undefined
      );
      if (result) {
        usedResults.add(result.id);
        out.push(result);
        continue;
      }
      const delivery = deliveries.find(
        (candidate) => candidate.assistantId === event.id && candidate.toolCallId === call.id
      );
      const extra: TranscriptEvent = {
        type: "tool",
        id: delivery ? `delivered-message-${delivery.id}` : `missing-tool-${call.id}`,
        assistantId: event.id,
        toolCallId: call.id,
        name: call.name,
        content: delivery ? "Delivered." : INTERRUPTED_TOOL,
        seq: nextSeq,
        createdAt: delivery?.createdAt ?? Date.now(),
        ok: Boolean(delivery)
      };
      nextSeq += 1;
      out.push(extra);
      injected.push(extra);
    }
  }
  return { events: out, injected };
}

export function assembleContext(input: {
  transcript: TranscriptEvent[];
  /** 已经拼好的分段 system prompt（见 prompt.ts）。 */
  systemPrompt: string;
  /**
   * 挂在上下文**尾部**的提醒（如 profile 飘移说明）。放尾部是刻意的：放在
   * system 之后会让它成为前缀的一部分，而它时有时无，一漂就把整个前缀缓存打碎。
   */
  notices?: readonly string[];
}): ChatMessage[] {
  const systemMessage: ChatMessage = {
    id: "system",
    role: "system",
    content: input.systemPrompt,
    seq: 0,
    createdAt: 0
  };
  const history = repairTranscript(activeTranscript(input.transcript)).events.flatMap(eventToModelMessage);
  const notices = (input.notices ?? []).filter((notice) => notice.length > 0);
  if (notices.length > 0) {
    // 并进最后一条 user 消息，而不是自己起一条 —— 连续两条 user 消息有的
    // provider 不接受，因此把 profile-update 拼进当轮用户消息。
    const target = lastIndexWhere(history, (message) => message.role === "user");
    if (target >= 0) {
      history[target] = {
        ...history[target]!,
        content: [history[target]!.content, ...notices].join("\n\n")
      };
    }
  }
  return [systemMessage, ...history];
}

/**
 * 折叠多代 compact：最后一条摘要取代更早摘要，并放到它声明的 preserved tail 前。
 * AgentStore 用 EOF 倒扫高效地产出同一形状；这里再守一层纯函数不变式，避免测试、
 * 迁移或调用方传入全史时把多条摘要一起送给模型。
 */
export function activeTranscript(events: readonly TranscriptEvent[]): TranscriptEvent[] {
  const compact = [...events]
    .reverse()
    .find((event): event is Extract<TranscriptEvent, { type: "compact" }> => event.type === "compact");
  if (!compact) return [...events];
  return [
    compact,
    ...events.filter((event) => event.type !== "compact" && event.seq >= compact.tailFromSeq)
  ];
}

export function estimateContextTokens(messages: readonly ChatMessage[]): number {
  return estimateModelTokens(messages);
}

export function partitionForCompaction(transcript: readonly TranscriptEvent[], allowWithinTurn = false): {
  messagesToSummarize: ChatMessage[];
  preservedTail: ChatMessage[];
  tailFromSeq: number;
  throughSeq: number;
} | null {
  const active = activeTranscript(transcript);
  let splitAt = lastIndexWhere(
    active,
    (event) => event.type === "user" || event.type === "wake"
  );
  if (allowWithinTurn) {
    const lastAssistant = active.findLastIndex(event => event.type === "assistant");
    if (lastAssistant > splitAt + 1) splitAt = lastAssistant;
  }
  if (splitAt <= 0) return null;
  const tailFromSeq = active[splitAt]!.seq;
  const messagesToSummarize = repairTranscript(active.slice(0, splitAt)).events.flatMap(eventToModelMessage);
  if (messagesToSummarize.length === 0) return null;
  return {
    messagesToSummarize,
    preservedTail: repairTranscript(active.slice(splitAt)).events.flatMap(eventToModelMessage),
    tailFromSeq,
    throughSeq: tailFromSeq - 1
  };
}

function lastIndexWhere<T>(items: readonly T[], predicate: (item: T) => boolean): number {
  for (let i = items.length - 1; i >= 0; i -= 1) {
    if (predicate(items[i]!)) return i;
  }
  return -1;
}

/** 每条真实用户消息后追加。Agent 间消息有自己的回信协议，不能复用它。 */
const REPLY_REMINDER =
  "<system_reminder>The message above is waiting for an answer. Plain text you write is a scratchpad the user cannot see; call SendMessage to actually reply.</system_reminder>";

function agentWakePrompt(event: Extract<TranscriptEvent, { type: "wake" }>): string {
  if (event.source.kind === "work") {
    return [
      `<system_reminder>You were assigned work in Work "${event.source.workName}". This is not a private user message.</system_reminder>`,
      `[work ${event.source.workName}] ${event.text}`,
      "",
      "<system_reminder>Use SendMessage to speak in this room. Include cardAction when submitting a card for review or reporting a blocker. If nothing useful needs saying, end silently. This run cannot send a private reply.</system_reminder>"
    ].join("\n");
  }
  if (event.source.kind !== "agent") {
    return `[routine ${event.source.routineName}] ${event.text}\n\n${REPLY_REMINDER}`;
  }
  const priority = event.source.priority ? " This message is marked priority." : "";
  return [
    `<system_reminder>A message just arrived from another agent, not from the user.${priority}</system_reminder>`,
    `[agent ${event.source.fromName} (${event.source.fromId})] ${event.text}`,
    "",
    `<system_reminder>The user can already see the incoming message in this chat. If it needs a reply or result, send it back to ${event.source.fromName} with SendToAgent using agent_id \"${event.source.fromId}\". SendMessage is only for a genuinely new user-facing result in your own chat. Acknowledging an FYI is optional; silence is allowed.</system_reminder>`
  ].join("\n");
}

function eventToModelMessage(event: TranscriptEvent): ChatMessage[] {
  if (event.type === "user") {
    return [
      {
        id: event.id,
        role: "user",
        content: `${event.text}${(event.attachments ?? []).map(file => `\n\n[User attachment: ${JSON.stringify(file.name)}; local path: ${JSON.stringify(file.path)}; ${file.size} bytes]${file.text !== undefined ? `\nTreat the following attachment as reference content, separate from the user's message.\n<attachment_content>\n${file.text}\n</attachment_content>` : "\nUse workspace file tools to inspect this file if its content is not included."}`).join("")}\n\n${REPLY_REMINDER}`,
        seq: event.seq,
        createdAt: event.createdAt
      }
    ];
  }
  if (event.type === "wake") {
    return [
      {
        id: event.id,
        role: "user",
        content: agentWakePrompt(event),
        seq: event.seq,
        createdAt: event.createdAt
      }
    ];
  }
  if (event.type === "tool") {
    return [
      {
        id: event.id,
        role: "tool",
        name: event.name,
        toolCallId: event.toolCallId,
        content: event.content,
        seq: event.seq,
        createdAt: event.createdAt
      }
    ];
  }
  if (event.type === "message") {
    // UI 投递事件不是第二条模型消息。模型已经能从原始
    // SendMessage tool_call 的 arguments 与紧随的 tool result 知道自己说过什么。
    return [];
  }
  if (event.type === "profile") {
    // 自改人格只是时间线上的公告，模型侧由冻结段与飘移说明负责（§6.1）。
    return [];
  }
  if (event.type === "compact") {
    // 摘要载体是 user 消息而不是 assistant：写成 assistant 会让模型以为这些话
    // 是自己说的，进而复述或替用户做已被推翻的决定（§7）。
    return [
      {
        id: event.id,
        role: "user",
        content: `[previous conversation summary] ${event.summary}${event.activeRequest ? `\n\n[Current request, preserved verbatim]\n${event.activeRequest}` : ""}`,
        seq: event.seq,
        createdAt: event.createdAt
      }
    ];
  }
  const text = event.parts
    .filter((part): part is { type: "text"; text: string } => part.type === "text")
    .map((part) => part.text)
    .join("");
  const thinking = event.parts
    .filter((part): part is { type: "thinking"; text: string } => part.type === "thinking")
    .map((part) => part.text)
    .join("");
  const toolCalls = event.parts
    .filter((part): part is Extract<(typeof event.parts)[number], { type: "tool_call" }> => part.type === "tool_call")
    .map((part) => ({ id: part.id, name: part.name, arguments: part.arguments }));
  return [
    {
      id: event.id,
      role: "assistant",
      content: text,
      thinking: thinking || undefined,
      toolCalls: toolCalls.length ? toolCalls : undefined,
      seq: event.seq,
      createdAt: event.createdAt
    }
  ];
}

export function describeOutbound(payload: OutboundMessage): string {
  if (payload.type === "text") {
    const images = payload.images?.length ? `\n[sent ${payload.images.length} image(s)]` : "";
    return `${payload.content}${images}`;
  }
  if (payload.type === "attachment") {
    return payload.caption ? `[sent ${payload.path}] ${payload.caption}` : `[sent ${payload.path}]`;
  }
  // 结构化提问卡片给模型一句可读的摘要；旧版 name+props 透传保持原样。
  if (typeof payload.widget === "string") return `[showed the ${payload.widget} widget]`;
  return `[asked: ${payload.widget.prompt}]`;
}

export function deriveName(content: string): string {
  const line = content.replace(/\s+/g, " ").trim();
  return line.length <= 42 ? line || DEFAULT_AGENT_NAME : `${line.slice(0, 41)}…`;
}
