import path from "node:path";
import {
  KernelErrorCode,
  estimateModelTokens,
  RpcError,
  type ChatMessage,
  type LocalToolAction,
  type ModelImage,
  type ToolCall,
  type ToolResolution,
  type TurnStartParams
} from "@nuum/protocol";
import { createSandbox } from "@nuum/sandbox";
import { ToolRegistry } from "@nuum/tools";
import { selectModel } from "./model/router.js";
import type { KernelEmitter } from "./types.js";

export interface TurnHandle {
  provideContext(requestId: string, messages?: ChatMessage[], error?: string): void;
  cancel(): void;
  decide(toolCallId: string, resolution: ToolResolution): void;
  provideToolResult(toolCallId: string, ok: boolean, output: string, endTurn?: boolean): void;
}

/** 模型选路是唯一的外部副作用，抽成接缝才能在单测里驱动整个 loop。 */
export interface TurnDeps {
  selectModel: typeof selectModel;
}

const MAX_ROUNDS = 16;
const ROUND_LIMIT_NOTICE = `Stopped after ${MAX_ROUNDS} tool rounds without a final answer.`;

/**
 * turn 循环的节奏提醒（对齐 Grok Bot 的 reminder middleware）：模型埋头调工具
 * 时，用户那头看到的是长静默。按「距上次发声工具的调用数」注入一条合成 user
 * 消息拉它回来 —— 只进本轮内存上下文，不 emit 事件，所以不落转录、不进下一轮。
 * 每种提醒每个静默段只发一次；发声工具一调用就重置计数与段标记。
 */
const ACK_TOOL_THRESHOLD = 1;
const SILENCE_TOOL_THRESHOLD = 6;
const RESULT_TOOL_THRESHOLD = 0;

type ReminderKind = "ack" | "silence" | "result";

function reminderText(kind: ReminderKind, voice: string): string {
  if (kind === "ack") {
    return (
      `<system_reminder>You opened this turn by calling tools without first acknowledging the user, ` +
      `so they are watching silence and may think the app froze. Call ${voice} right now — a real tool ` +
      `call, not text you write — with a one-line acknowledgement before any further tool call, then continue the work.</system_reminder>`
    );
  }
  if (kind === "silence") {
    return (
      `<system_reminder>You have made several tool calls without a message, so the user is currently ` +
      `watching silence. Call ${voice} now with a brief, specific update on what you are doing or what ` +
      `you just found, then continue.</system_reminder>`
    );
  }
  return (
    `<system_reminder>The user cannot see tool output or your thinking — only ${voice} reaches them. ` +
    `If you have produced a result or finished what they asked, send it with ${voice} before continuing ` +
    `or ending the turn; if you are still mid-task, keep working and send it once you have it.</system_reminder>`
  );
}

/** 取消是正常收束，不是错误，所以单独立一个信号，别混进 turn.error。 */
class TurnCancelled extends Error {
  constructor() {
    super("Turn cancelled");
    this.name = "TurnCancelled";
  }
}

export function startTurn(
  params: TurnStartParams,
  emit: KernelEmitter,
  registry: ToolRegistry,
  deps: TurnDeps = { selectModel }
): TurnHandle {
  const abort = new AbortController();
  const decisions = new Map<string, (value: ToolResolution) => void>();
  const delegations = new Map<string, (value: { ok: boolean; output: string; endTurn?: boolean }) => void>();
  const contexts = new Map<string, (value: { messages?: ChatMessage[]; error?: string }) => void>();
  const delegated = new Set(params.delegatedTools.map((tool) => tool.name));
  let activeSandbox: ReturnType<typeof createSandbox> | null = null;
  void run().catch((error) => {
    if (error instanceof TurnCancelled || abort.signal.aborted) {
      emit("turn.ended", { runId: params.runId, status: "cancelled" });
      return;
    }
    const code = error instanceof RpcError ? error.code : KernelErrorCode.INTERNAL;
    const message = error instanceof Error ? error.message : String(error);
    emit("turn.error", { runId: params.runId, code, message });
    emit("turn.ended", { runId: params.runId, status: "error" });
  });

  return {
    provideContext(requestId, messages, error) { contexts.get(requestId)?.({ messages, error }); },
    cancel() {
      abort.abort();
      void activeSandbox?.disposeShell();
    },
    decide(toolCallId, resolution) {
      decisions.get(toolCallId)?.(resolution);
    },
    provideToolResult(toolCallId, ok, output, endTurn) {
      delegations.get(toolCallId)?.({ ok, output, endTurn });
    }
  };

  async function run(): Promise<void> {
    const { port, apiKey } = deps.selectModel(params.model, params.secrets);
    const sandbox = createSandbox({
      roots: params.roots,
      permission: params.toolPermission,
      approvals: params.approvals,
      refused: params.refused
    });
    activeSandbox = sandbox;
    // 委派工具也要进模型看得见的工具表，否则模型根本不会去调它。
    const tools = [...registry.list(params.localToolNames), ...params.delegatedTools];
    const messages = [...params.messages];
    const voiceTools = new Set(params.voiceToolNames);
    const voice = voiceTools.values().next().value ?? "SendMessage";
    let toolCallsSinceVoice = 0;
    let voiceSentThisTurn = false;
    const reminded = new Set<ReminderKind>();
    for (let round = 0; round < MAX_ROUNDS; round += 1) {
      if (abort.signal.aborted) throw new TurnCancelled();
      if (params.contextWindow) {
        const requestId = crypto.randomUUID();
        const pending = waitFor(contexts, requestId);
        const usedTokens = estimateModelTokens(messages, tools);
        emit("turn.context", { runId: params.runId, requestId, usedTokens });
        const next = await pending;
        if (next.error) throw new Error(next.error);
        if (next.messages) {
          // Images and reminders are Kernel-local; keep them when Host rebuilds the persisted history.
          const local = messages.filter(message => message.images?.length || message.id.startsWith("reminder-"));
          messages.splice(0, messages.length, ...next.messages, ...local.filter(message => !next.messages!.some(item => item.id === message.id)));
        }
        if (estimateModelTokens(messages, tools) > params.contextWindow * 0.9) throw new Error("Context capacity exhausted; execution paused without replaying tools.");
        if (abort.signal.aborted) throw new TurnCancelled();
      }
      const messageId = crypto.randomUUID();
      let text = "";
      let thinking = "";
      const toolCalls: ToolCall[] = [];
      try {
        for await (const chunk of port.streamChat({ model: params.model, messages, tools, apiKey, ...(params.contextWindow ? { maxOutputTokens: Math.max(1, Math.min(4096, Math.floor(params.contextWindow * 0.1))) } : {}) }, abort.signal)) {
          if (chunk.type === "thinking") {
            thinking += chunk.text;
            emit("turn.delta", { runId: params.runId, messageId, delta: chunk.text, part: "thinking" });
          } else if (chunk.type === "text") {
            text += chunk.text;
            emit("turn.delta", { runId: params.runId, messageId, delta: chunk.text, part: "text" });
          } else {
            toolCalls.push({ id: chunk.id, name: chunk.name, arguments: chunk.arguments });
          }
        }
      } catch (error) {
        if (abort.signal.aborted) throw new TurnCancelled();
        throw error;
      }
      messages.push({
        id: messageId,
        role: "assistant",
        content: text,
        thinking: thinking || undefined,
        toolCalls: toolCalls.length ? toolCalls : undefined,
        seq: messages.length,
        createdAt: Date.now()
      });
      const toolImages: ModelImage[] = [];
      if (toolCalls.length === 0) {
        emit("turn.ended", { runId: params.runId, status: "idle" });
        return;
      }
      for (const call of toolCalls) {
        const result = await resolveToolCall(call, sandbox);
        messages.push({
          id: crypto.randomUUID(),
          role: "tool",
          name: call.name,
          toolCallId: call.id,
          content: result.output,
          seq: messages.length,
          createdAt: Date.now()
        });
        toolImages.push(...(result.images ?? []));
        emit("turn.tool.completed", {
          runId: params.runId,
          toolCallId: call.id,
          name: call.name,
          ok: result.ok,
          output: result.output
        });
        if (result.ok && result.endTurn) {
          emit("turn.ended", { runId: params.runId, status: "idle" });
          return;
        }
        if (voiceTools.has(call.name)) {
          toolCallsSinceVoice = 0;
          voiceSentThisTurn = true;
          reminded.clear();
        } else {
          toolCallsSinceVoice += 1;
        }
      }
      if (toolImages.length > 0) {
        messages.push({
          id: crypto.randomUUID(),
          role: "user",
          content: "Images returned by the preceding local read tool calls.",
          images: toolImages,
          seq: messages.length,
          createdAt: Date.now()
        });
      }
      const reminder = reminderToInject();
      if (reminder != null) {
        reminded.add(reminder);
        messages.push({
          id: `reminder-${reminder}-${crypto.randomUUID()}`,
          role: "user",
          content: reminderText(reminder, voice),
          seq: messages.length,
          createdAt: Date.now()
        });
      }
    }
    // 轮次用尽时不能装作正常收束：把原因作为最后一段文本告诉用户。
    emit("turn.delta", {
      runId: params.runId,
      messageId: crypto.randomUUID(),
      delta: ROUND_LIMIT_NOTICE,
      part: "text"
    });
    emit("turn.ended", { runId: params.runId, status: "idle" });

    /** ack（从未发声）→ result（发过声又埋头）→ silence（长静默），每轮至多一条。 */
    function reminderToInject(): ReminderKind | null {
      if (!voiceSentThisTurn && toolCallsSinceVoice > ACK_TOOL_THRESHOLD && !reminded.has("ack")) {
        return "ack";
      }
      if (voiceSentThisTurn && toolCallsSinceVoice > RESULT_TOOL_THRESHOLD && !reminded.has("result")) {
        return "result";
      }
      if (toolCallsSinceVoice > SILENCE_TOOL_THRESHOLD && !reminded.has("silence")) {
        return "silence";
      }
      return null;
    }
  }

  async function resolveToolCall(
    call: ToolCall,
    sandbox: ReturnType<typeof createSandbox>
  ): Promise<{ ok: boolean; output: string; images?: ModelImage[]; endTurn?: boolean }> {
    if (delegated.has(call.name)) {
      emit("turn.tool.delegate", {
        runId: params.runId,
        toolCallId: call.id,
        name: call.name,
        arguments: call.arguments
      });
      return waitFor(delegations, call.id);
    }
    const tool = registry.get(call.name);
    if (!tool) throw new RpcError(KernelErrorCode.TOOL, `Unknown tool: ${call.name}`);
    const declaredAction = tool.definition.action;
    if (!declaredAction) {
      throw new RpcError(KernelErrorCode.TOOL, `Local tool ${call.name} does not declare a permission action`);
    }
    const { action, target } = permissionRequest(
      call.name,
      declaredAction,
      call.arguments,
      params.roots.terminals
    );
    const verdict = await sandbox.authorize(action, target);
    if (verdict.decision === "deny") {
      return { ok: false, output: verdict.reason ?? `Permission denied for ${action} ${verdict.target}` };
    }
    if (verdict.decision === "ask") {
      emit("turn.tool.pending", {
        runId: params.runId,
        toolCallId: call.id,
        name: call.name,
        arguments: call.arguments,
        mutating: action === "read-file" ? false : tool.definition.mutating,
        action,
        target: verdict.target
      });
      const resolution = await waitFor(decisions, call.id);
      if (resolution === "deny" || resolution === "never") {
        sandbox.refuse(action, verdict.target);
        if (resolution === "never") sandbox.setPermission("never");
        return { ok: false, output: "User denied this tool call." };
      }
      sandbox.grantOnce(action, verdict.target);
    }
    emit("turn.tool.started", {
      runId: params.runId,
      toolCallId: call.id,
      name: call.name,
      arguments: call.arguments
    });
    try {
      const result = await tool.execute(call.arguments, {
        runId: params.runId,
        sandbox,
        abortSignal: abort.signal
      });
      return typeof result === "string"
        ? { ok: true, output: result }
        : { ok: true, output: result.text, images: result.images };
    } catch (error) {
      if (abort.signal.aborted) throw new TurnCancelled();
      return { ok: false, output: error instanceof Error ? error.message : String(error) };
    }
  }

  /** 审批与委派是同一种等待：挂一个 resolver，abort 时按取消收束。 */
  function waitFor<T>(waiters: Map<string, (value: T) => void>, toolCallId: string): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const onAbort = (): void => {
        waiters.delete(toolCallId);
        reject(new TurnCancelled());
      };
      abort.signal.addEventListener("abort", onAbort, { once: true });
      waiters.set(toolCallId, (value) => {
        abort.signal.removeEventListener("abort", onAbort);
        waiters.delete(toolCallId);
        resolve(value);
      });
    });
  }
}

function permissionRequest(
  toolName: string,
  action: LocalToolAction,
  input: Record<string, unknown>,
  terminalsRoot: string
): { action: LocalToolAction; target: string } {
  if (toolName === "shell" && typeof input.shell_id === "string") {
    return { action: "read-file", target: path.join(terminalsRoot, `${input.shell_id}.txt`) };
  }
  if (action === "run-command") {
    return { action, target: typeof input.command === "string" ? input.command : "" };
  }
  for (const key of ["path", "target_directory", "working_directory"]) {
    if (typeof input[key] === "string" && input[key].length > 0) {
      return { action, target: input[key] };
    }
  }
  return { action, target: "." };
}
