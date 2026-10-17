import type { AgentStatus } from "@nuum/protocol";

/** Runtime is authoritative: old tool records never imply current activity. */
export function nunuActivityState(status: AgentStatus | undefined, awaitingApproval: boolean, executingTool: boolean) {
  if (awaitingApproval) return "waiting";
  if (status === "error") return "error";
  if (status !== "running") return "idle";
  return executingTool ? "working" : "thinking";
}
