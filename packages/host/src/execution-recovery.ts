import { createHash } from "node:crypto";
import type { ExecutionPreferences, ExecutionRecord, TranscriptDraft, TranscriptEvent } from "@nuum/protocol";

export function executionPolicy(preferences: ExecutionPreferences): string {
  return createHash("sha256").update(JSON.stringify(preferences)).digest("hex");
}

/** Uses the existing session transcript as the only durable result store. Ack follows this write. */
export async function recoverExecutionResult(record: ExecutionRecord, io: {
  read(): Promise<TranscriptEvent[]>;
  append(draft: TranscriptDraft): Promise<TranscriptEvent>;
}): Promise<TranscriptEvent | undefined> {
  if (record.result.state !== "finished" || !record.origin) return;
  const prefix = `${record.origin.runId}:`;
  if (!record.request.id.startsWith(prefix)) throw new Error("Execution result does not match its Host-owned run");
  const toolCallId = record.request.id.slice(prefix.length);
  const events = await io.read();
  if (events.some(event => event.type === "tool" && event.executionId === record.request.id)) return;
  const call = events.findLast(event => event.type === "assistant" && event.parts.some(part =>
    part.type === "tool_call" && (part.executionId === record.request.id || (!part.executionId && part.id === toolCallId))));
  if (call && events.some(event => event.type === "tool" && !event.executionId && event.assistantId === call.id && event.toolCallId === toolCallId)) return;
  const assistantId = call?.id ?? `recovered-call:${record.request.id}`;
  if (!call) await io.append({
    type: "assistant", id: assistantId, createdAt: Date.now(),
    parts: [{ type: "tool_call", id: toolCallId, executionId: record.request.id, name: record.request.name, arguments: record.request.input }]
  });
  const original = call?.type === "assistant" ? call.parts.find(part => part.type === "tool_call" && part.id === toolCallId) : undefined;
  return io.append({ type: "tool", id: `recovered-result:${record.request.id}`, assistantId, toolCallId,
    permissionTaskKey: record.origin.taskKey, executionId: record.request.id, name: original?.type === "tool_call" ? original.name : record.request.name,
    content: record.result.output, ok: record.result.ok, createdAt: Date.now() });
}
