import type { WorkEvent, WorkTask } from "@nuum/protocol";

export function workIntent(event: WorkEvent, task?: WorkTask) {
  if (event.type === "work.requested" || event.type === "dispatch.requested") return { agentId: event.agentId, taskId: event.taskId, instruction: event.instruction };
  if (event.type === "task.delegated") return { agentId: event.agentId, taskId: event.taskId, instruction: event.instruction };
  if (event.type === "task.handed_off" && event.returnToAgentId) return {
    agentId: event.returnToAgentId, taskId: event.taskId,
    instruction: `Worker ${event.actor.id} returned a result. Continue in your own card session.\n${event.summary}\nDeliverables: ${JSON.stringify(event.deliverables)}`
  };
  if (event.type === "task.transitioned" && event.to === "in_progress" && ["blocked", "review"].includes(event.from) && task?.ownerAgentId) return {
    agentId: task.ownerAgentId, taskId: event.taskId, instruction: "The user confirmed resuming your card. Review its latest public state and continue."
  };
  return undefined;
}

/** Later business decisions supersede an old card command, even across a restart. */
export function currentCardSource(events: readonly WorkEvent[], source: WorkEvent, taskId: string): boolean {
  return !events.some(event => event.seq > source.seq && "taskId" in event && event.taskId === taskId &&
    ["task.delegated", "task.handed_off", "task.transitioned", "work.requested"].includes(event.type));
}

export function pendingCardDelegation(events: readonly WorkEvent[], taskId: string) {
  let pending: Extract<WorkEvent, { type: "task.delegated" }> | undefined;
  for (const event of events) {
    if (!("taskId" in event) || event.taskId !== taskId) continue;
    if (event.type === "task.delegated") pending = event;
    if (event.type === "task.handed_off" || event.type === "task.transitioned") pending = undefined;
  }
  return pending;
}
