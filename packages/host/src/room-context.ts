import type { WorkEvent, TranscriptEvent } from "@nuum/protocol";
import { projectWork } from "./work-store.js";

/** Continuity describes the effective session, never a permanent delivery watermark. */
export function selectRoomInput(events: WorkEvent[], transcript: readonly TranscriptEvent[], workId: string, membershipRevision: number, triggerIds: readonly string[] = [], inputAfterSeq?: number) {
  const epoch = transcript.findLast(event => event.type === "compact")?.epoch ?? 0;
  const lastInput = transcript.findLast(event => event.type === "user" || event.type === "wake");
  const prior = lastInput?.type === "wake" && lastInput.source.kind === "work" && lastInput.source.workId === workId && !lastInput.source.taskId ? lastInput.source.roomInput : undefined;
  const continuous = prior?.epoch === epoch && prior.membershipRevision === membershipRevision && inputAfterSeq === undefined;
  const chat = projectWork(events).chat;
  const candidates = continuous ? chat.filter(message => message.seq > prior.throughSeq)
    : inputAfterSeq !== undefined ? chat.filter(message => message.seq > inputAfterSeq) : chat.slice(-24);
  const triggers = new Set(events.filter(event => triggerIds.includes(event.id) && event.type === "chat.posted").map(event => event.seq));
  const included = new Set(candidates.map(message => message.seq));
  const messages = chat.filter(message => included.has(message.seq) || (triggers.has(message.seq) && (!continuous || message.seq > prior.throughSeq)));
  return { messages, epoch, mode: continuous ? "continuation" as const : "background" as const,
    fromSeq: continuous ? prior.throughSeq : Math.max(0, (messages[0]?.seq ?? 1) - 1),
    throughSeq: events.at(-1)?.seq ?? 0, omitted: chat.length - messages.length };
}
