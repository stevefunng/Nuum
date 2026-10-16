import assert from "node:assert/strict";
import test from "node:test";
import type { AgentView, WorkSnapshot } from "@nuum/protocol";
import { memberActivity } from "./member-status";

test("member preview uses active execution, never a historical reply or assigned task", () => {
  const agent = { profile: { id: "a" }, runtime: { status: "running", activeRunId: "r" } } as AgentView;
  const snapshot = { events: [], tasks: [{ id: "t", title: "Draft report" }] } as unknown as WorkSnapshot;
  assert.equal(memberActivity(agent, snapshot).kind, "elsewhere");
  snapshot.events = [{ type: "execution.started", executionId: "e", runId: "r", agentId: "a", taskId: "t" }] as WorkSnapshot["events"];
  assert.deepEqual(memberActivity(agent, snapshot), { kind: "task", title: "Draft report" });
  agent.runtime.activeRunId = "other-run";
  assert.equal(memberActivity(agent, snapshot).kind, "elsewhere");
  agent.runtime.activeRunId = "r";
  agent.runtime.status = "idle";
  assert.equal(memberActivity(agent, snapshot).kind, "idle");
  agent.runtime.status = "running";
  snapshot.events.push({ type: "execution.finished", executionId: "e" } as WorkSnapshot["events"][number]);
  assert.equal(memberActivity(agent, snapshot).kind, "elsewhere");
  snapshot.events.push({ type: "execution.started", executionId: "e2", runId: "r", agentId: "a" } as WorkSnapshot["events"][number]);
  assert.equal(memberActivity(agent, snapshot).kind, "discussion");
});
