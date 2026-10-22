import assert from "node:assert/strict";
import { test } from "node:test";
import { executionPolicy, recoverExecutionResult } from "./execution-recovery.js";
import type { TranscriptEvent } from "@nuum/protocol";

test("recovery writes the original tool result once, including a missing tool call", async () => {
  const events: TranscriptEvent[] = [];
  const recovered = { request: { id: "run:tool", contextId: "ctx", name: "shell", input: { command: "echo done" } }, result: { state: "finished" as const, ok: true, output: "done" }, origin: { runId: "run" } };
  const io = { read: async () => events, append: async (draft: any) => { const event = { ...draft, seq: events.length + 1 }; events.push(event); return event; } };
  await recoverExecutionResult(recovered, io);
  await recoverExecutionResult(recovered, io);
  assert.equal(events.length, 2);
  assert.equal(events[0]?.type, "assistant");
  assert.equal(events[1]?.type, "tool");
  if (events[1]?.type === "tool") { assert.equal(events[1].toolCallId, "tool"); assert.equal(events[1].content, "done"); }
});

test("recovery reuses an already persisted call and never duplicates a delivered result", async () => {
  const events: TranscriptEvent[] = [{ type: "assistant", id: "original", seq: 1, createdAt: 1, parts: [{ type: "tool_call", id: "t", name: "shell", arguments: {} }] }];
  const io = { read: async () => events, append: async (draft: any) => { const event = { ...draft, seq: events.length + 1 }; events.push(event); return event; } };
  await recoverExecutionResult({ request: { id: "r:t", contextId: "c", name: "shell", input: {} }, origin: { runId: "r" }, result: { state: "finished", ok: false, output: "cancelled" } }, io);
  assert.equal(events.length, 2);
  assert.equal((events[1] as any).assistantId, "original");
});

test("authorization snapshot changes when command or network policy is revoked", () => {
  const settings = { workspaceId: "w", commands: "ask" as const, commandGrants: [], networkGrants: [{ workspaceId: "w", target: "example.com:443" }] };
  assert.notEqual(executionPolicy(settings), executionPolicy({ ...settings, networkGrants: [] }));
  assert.notEqual(executionPolicy(settings), executionPolicy({ ...settings, commands: "never" }));
});

test("the same model tool id in a later run is a different execution", async () => {
  const events: TranscriptEvent[] = [];
  const io = { read: async () => events, append: async (draft: any) => { const event = { ...draft, seq: events.length + 1 }; events.push(event); return event; } };
  for (const runId of ["first", "second"]) await recoverExecutionResult({ request: { id: `${runId}:tool`, contextId: "ctx", name: "shell", input: {} }, origin: { runId }, result: { state: "finished", ok: true, output: runId } }, io);
  assert.deepEqual(events.filter(event => event.type === "tool").map(event => event.content), ["first", "second"]);
});
