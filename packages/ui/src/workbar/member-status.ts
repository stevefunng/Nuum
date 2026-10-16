import type { AgentView, WorkSnapshot } from "@nuum/protocol";

/** Only describe an unfinished execution when the agent is actually running. */
export function memberActivity(agent: AgentView, snapshot: WorkSnapshot): { kind: "idle" | "error" | "discussion" | "task" | "elsewhere"; title?: string } {
  if (agent.runtime.status !== "running") return { kind: agent.runtime.status };
  if (!agent.runtime.activeRunId) return { kind: "elsewhere" };
  const finished = new Set(snapshot.events.flatMap(event => event.type === "execution.finished" ? [event.executionId] : []));
  const execution = [...snapshot.events].reverse().find(event => event.type === "execution.started" && event.agentId === agent.profile.id && event.runId === agent.runtime.activeRunId && !finished.has(event.executionId));
  if (!execution || execution.type !== "execution.started") return { kind: "elsewhere" };
  if (!execution.taskId) return { kind: "discussion" };
  return { kind: "task", title: snapshot.tasks.find(task => task.id === execution.taskId)?.title };
}
