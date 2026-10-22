import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test, type TestContext } from "node:test";
import type { KernelClient } from "./kernel-client.js";
import type { RunContext } from "./run-context.js";
import { HostRuntime } from "./runtime.js";

const quietKernel: KernelClient = {
  hello: async () => ({ name: "nuum-kernel", version: "0.1.0" }),
  start: async () => ({ ok: true }),
  cancel: async () => ({ ok: true }),
  decide: async () => ({ ok: true }),
  provideToolResult: async () => ({ ok: true }),
  disposeShell: async () => ({ ok: true }),
  summarize: async () => ({ text: "" }),
  tools: async () => [],
  onEvent: () => undefined,
  dispose: () => undefined
};

async function runtime(t: TestContext, kernel: KernelClient = quietKernel): Promise<HostRuntime> {
  const instance = new HostRuntime({
    dataDir: await mkdtemp(path.join(tmpdir(), "nuum-work-runtime-")),
    kernelCommand: "unused",
    kernelArgs: [],
    spawnKernel: () => kernel
  });
  await instance.start();
  t.after(() => instance.dispose());
  return instance;
}

test("a Nunu can join multiple rooms and membership survives restart projections", async (t) => {
  const host = await runtime(t);
  const agent = await host.createAgent({ name: "Builder" });
  const first = await host.createWork({ name: "First" });
  const second = await host.createWork({ name: "Second" });
  await host.attachWorkMember({ workId: first.id, agentId: agent.profile.id, role: "worker", expectedRevision: 0 });
  await host.attachWorkMember({ workId: second.id, agentId: agent.profile.id, role: "worker", expectedRevision: 0 });
  assert.equal((await host.getWork(first.id)).members.length, 1);
  assert.equal((await host.getWork(second.id)).members.length, 1);
  await host.detachWorkMember({ workId: first.id, agentId: agent.profile.id, expectedRevision: 1 });
  assert.equal((await host.getWork(first.id)).members.length, 0);
  assert.equal((await host.getWork(second.id)).members.length, 1);
  await host.workStore.init();
  assert.equal((await host.getWork(second.id)).members.length, 1);
});

test("task mutations use revision CAS and the centralized transition policy", async (t) => {
  const host = await runtime(t);
  const work = await host.createWork({ name: "Launch" });
  const task = await host.createWorkTask({
    workId: work.id,
    title: "Ship",
    description: "",
    acceptanceCriteria: [],
    assigneeIds: [],
    dependencyIds: [],
    priority: "normal"
  });
  assert.equal(task.state, "ready");

  const ready = task;
  const doing = await host.transitionWorkTask({
    workId: work.id,
    taskId: task.id,
    to: "in_progress",
    expectedRevision: ready.revision
  });
  const blocked = await host.transitionWorkTask({
    workId: work.id,
    taskId: task.id,
    to: "blocked",
    expectedRevision: doing.revision,
    blocker: { reason: "Waiting for assets", ownerId: "design" }
  });
  assert.equal(blocked.blocker?.reason, "Waiting for assets");
  assert.deepEqual(blocked.allowedTransitions, ["in_progress", "ready", "cancelled"]);

  await assert.rejects(
    host.transitionWorkTask({
      workId: work.id,
      taskId: task.id,
      to: "done",
      expectedRevision: blocked.revision
    }),
    /not allowed/i
  );
  await assert.rejects(
    host.transitionWorkTask({
      workId: work.id,
      taskId: task.id,
      to: "in_progress",
      expectedRevision: 1
    }),
    /revision/i
  );
});

test("chat and catalog remain Work-owned projections", async (t) => {
  const host = await runtime(t);
  const work = await host.createWork({ name: "Launch" });
  await host.postWorkMessage({ workId: work.id, body: "Status?", mentionedAgentIds: [] });
  const catalog = await host.addWorkCatalogEntry({
    workId: work.id,
    expectedRevision: 0,
    entry: {
      kind: "skill",
      name: "Release checks",
      description: "Run the release checklist",
      manifestPath: "/tmp/release/SKILL.md"
    }
  });

  const snapshot = await host.getWork(work.id);
  assert.equal(snapshot.chat[0]!.type, "chat.posted");
  assert.equal(snapshot.catalog.entries[0]!.kind, "skill");
  assert.equal(catalog.revision, 1);
});

test("dispatch keeps card history separate and handoff returns to Work", async (t) => {
  const started: import("@nuum/protocol").TurnStartParams[] = [];
  const kernel: KernelClient = {
    ...quietKernel,
    start: async (params) => { started.push(params); return { ok: true }; }
  };
  const host = await runtime(t, kernel);
  await host.setSettings({ deepseekApiKey: "test-key" });
  const agent = await host.createAgent({ name: "Builder" });
  const work = await host.createWork({ name: "Launch" });
  await host.attachWorkMember({ workId: work.id, agentId: agent.profile.id, role: "worker", expectedRevision: 0 });
  const task = await host.createWorkTask({
    workId: work.id,
    title: "Build",
    description: "Implement the flow",
    acceptanceCriteria: ["Tests pass"],
    assigneeIds: [agent.profile.id],
    dependencyIds: [],
    priority: "normal"
  });
  const ready = task;
  const doing = await host.transitionWorkTask({ workId: work.id, taskId: task.id, to: "in_progress", expectedRevision: ready.revision });
  const dispatched = await host.dispatchWork({ workId: work.id, agentId: agent.profile.id, taskId: task.id, instruction: "Finish this task" });

  assert.equal(started.length, 1);
  assert.match(started[0]!.messages[0]!.content, /Current Work/);
  assert.deepEqual(started[0]!.delegatedTools.map((tool) => tool.name).sort(), ["CreateTask", "ClaimTask", "ReadTask", "DelegateWork", "SendMessage", "ReadWorkTimeline", "RunWorkCLI"].sort());
  const transcript = await host.getTranscript(agent.profile.id);
  const wake = transcript.entries.find((event) => event.type === "wake");
  assert.equal(wake, undefined);
  const cardSession = await host.sessions.ensure(work.id, task.id, agent.profile.id, 1);
  assert.equal((await host.sessions.read(cardSession))[0]?.type, "wake");

  const context: RunContext = {
    kind: "work",
    workId: work.id,
    taskId: task.id,
    triggerEventId: "dispatch",
    catalogRevision: 0,
    catalog: [],
    requestedBy: { kind: "user", id: "local-user" }
  };
  await host.handoffTask(agent.profile.id, {
    summary: "Implementation is ready",
    status: "review",
    deliverables: [{ name: "Result", uri: "/tmp/result.txt" }]
  }, { agentId: agent.profile.id, assistantId: "assistant", toolCallId: "tool", runContext: context });
  const snapshot = await host.getWork(work.id);
  assert.equal(snapshot.tasks[0]!.state, "review");
  assert.equal(snapshot.tasks[0]!.revision, doing.revision + 2);
  assert.equal(snapshot.chat.at(-1)!.actor.kind, "agent");
  assert.equal(dispatched.queued, false);
});

test("room silence advances input while card traces stay isolated and resume", async (t) => {
  let emit: (method: string, params: unknown) => void = () => undefined;
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await runtime(t, { ...quietKernel,
    onEvent: (handler) => { emit = handler; },
    start: async (params) => { starts.push(params); return { ok: true }; }
  });
  await host.setSettings({ deepseekApiKey: "test-key" });
  const agent = await host.createAgent({ name: "Builder" });
  const id = agent.profile.id;
  const work = await host.createWork({ name: "Room" });
  await host.attachWorkMember({ workId: work.id, agentId: id, role: "worker", expectedRevision: 0 });
  const waitIdle = async () => {
    for (let i = 0; i < 100; i++) { if (!host.scheduler.isBusy(id)) return; await new Promise((resolve) => setTimeout(resolve, 10)); }
    assert.fail("run did not settle");
  };
  await historyMessage(host, work.id, "FIRST_ROOM_MESSAGE");
  const first = await host.dispatchWork({ workId: work.id, agentId: id, instruction: "Read" });
  emit("turn.ended", { runId: first.runId, status: "idle" });
  await waitIdle();
  await historyMessage(host, work.id, "SECOND_ROOM_MESSAGE");
  const second = await host.dispatchWork({ workId: work.id, agentId: id, instruction: "Read again" });
  const latest = starts.at(-1)!.messages.at(-1)!.content;
  assert.match(latest, /SECOND_ROOM_MESSAGE/);
  assert.doesNotMatch(latest, /FIRST_ROOM_MESSAGE/);
  emit("turn.ended", { runId: second.runId, status: "idle" });
  await waitIdle();
  const task = await host.createWorkTask({ workId: work.id, title: "Build", description: "", acceptanceCriteria: [], assigneeIds: [id], dependencyIds: [], priority: "normal" });
  const card = await host.dispatchWork({ workId: work.id, taskId: task.id, agentId: id, instruction: "CARD_SECRET_WORK" });
  assert.doesNotMatch(JSON.stringify(starts.at(-1)!.messages), /FIRST_ROOM_MESSAGE|SECOND_ROOM_MESSAGE/);
  emit("turn.delta", { runId: card.runId, messageId: "card-thought", part: "text", delta: "CARD_INTERNAL_TRACE" });
  emit("turn.ended", { runId: card.runId, status: "idle" });
  await waitIdle();
  assert.doesNotMatch(JSON.stringify(await host.store.readTranscript(id)), /CARD_SECRET_WORK|CARD_INTERNAL_TRACE/);
  const interrupted = (await host.getWork(work.id)).interruptions.find(item => item.taskId === task.id)!;
  await host.continueWork(work.id, interrupted.eventId);
  for (let i = 0; i < 100 && starts.length < 4; i++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.match(JSON.stringify(starts.at(-1)!.messages), /CARD_INTERNAL_TRACE/);
});

test("SendMessage in a card run publishes one atomic handoff, not a private reply", async (t) => {
  const host = await runtime(t);
  const agent = await host.createAgent({ name: "Builder" });
  const work = await host.createWork({ name: "Launch" });
  await host.attachWorkMember({ workId: work.id, agentId: agent.profile.id, role: "worker", expectedRevision: 0 });
  const task = await host.createWorkTask({ workId: work.id, title: "Build", description: "", acceptanceCriteria: [], assigneeIds: [agent.profile.id], dependencyIds: [], priority: "normal" });
  const ready = task;
  await host.transitionWorkTask({ workId: work.id, taskId: task.id, to: "in_progress", expectedRevision: ready.revision });
  const { createDelegatedTools } = await import("./delegated-tools.js");
  const send = createDelegatedTools(host).find((tool) => tool.definition.name === "SendMessage")!;
  const context = { agentId: agent.profile.id, assistantId: "a1", toolCallId: "c1", runContext: {
    kind: "work" as const, workId: work.id, taskId: task.id, triggerEventId: "trigger", catalogRevision: 0, catalog: [], requestedBy: { kind: "user" as const, id: "local-user" }
  } };
  await send.execute({ type: "text", content: "Ready to review", cardAction: { status: "review" } }, context);
  await send.execute({ type: "text", content: "Ready to review", cardAction: { status: "review" } }, context);
  const snapshot = await host.getWork(work.id);
  assert.equal(snapshot.tasks[0]!.state, "review");
  assert.equal(snapshot.chat.filter(message => message.body === "Ready to review").length, 1);
  assert.equal(snapshot.chat.at(-1)!.body, "Ready to review");
  assert.equal((await host.store.readTranscript(agent.profile.id)).length, 0);
});


test("room re-entry provides the recent 24 messages and explicitly marks omitted history", async (t) => {
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await runtime(t, { ...quietKernel, start: async (params) => { starts.push(params); return { ok: true }; } });
  await host.setSettings({ deepseekApiKey: "test-key" });
  const agent = await host.createAgent({ name: "Reader" });
  const work = await host.createWork({ name: "Backlog" });
  await host.attachWorkMember({ workId: work.id, agentId: agent.profile.id, role: "worker", expectedRevision: 0 });
  for (let i = 0; i < 30; i++) await historyMessage(host, work.id, `pending-message-${i}`);
  await host.dispatchWork({ workId: work.id, agentId: agent.profile.id, instruction: "Respond to the latest message" });
  const input = JSON.stringify(starts.at(-1)!.messages);
  assert.match(input, /pending-message-29/);
  const receipts = (await host.store.readTranscript(agent.profile.id)).filter((event) => event.type === "wake" && event.source.kind === "work");
  assert.equal(receipts.length, 1);
  assert.doesNotMatch(input, /pending-message-0\b/);
  assert.match(input, /older messages may be omitted/);
});

test("a queued card cannot start after the user cancels it", async (t) => {
  let emit: (method: string, params: unknown) => void = () => undefined;
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await runtime(t, { ...quietKernel, onEvent: (handler) => { emit = handler; }, start: async (params) => { starts.push(params); return { ok: true }; } });
  await host.setSettings({ deepseekApiKey: "test-key" });
  const agent = await host.createAgent({ name: "Builder" });
  const work = await host.createWork({ name: "Queue" });
  await host.attachWorkMember({ workId: work.id, agentId: agent.profile.id, role: "worker", expectedRevision: 0 });
  const running = await host.dispatchWork({ workId: work.id, agentId: agent.profile.id, instruction: "Discuss" });
  const task = await host.createWorkTask({ workId: work.id, title: "Cancelled card", description: "", acceptanceCriteria: [], assigneeIds: [agent.profile.id], dependencyIds: [], priority: "normal" });
  const queued = await host.dispatchWork({ workId: work.id, agentId: agent.profile.id, taskId: task.id, instruction: "Do not execute after cancellation" });
  assert.equal(queued.queued, true);
  await host.transitionWorkTask({ workId: work.id, taskId: task.id, to: "cancelled", expectedRevision: (await host.getWork(work.id)).tasks[0]!.revision });
  emit("turn.ended", { runId: running.runId, status: "idle" });
  for (let i = 0; i < 100 && host.scheduler.isBusy(agent.profile.id); i++) await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(starts.length, 1);
  assert.ok((await host.workStore.readTimeline(work.id)).some((event) => event.type === "execution.finished" && event.status === "failed"));
});

test("creator remains owner, worker returns to its card session, blocked requires human resume", async (t) => {
  let emit: (method: string, params: unknown) => void = () => {};
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await runtime(t, { ...quietKernel, onEvent: handler => { emit = handler; }, start: async (params) => { starts.push(params); return { ok: true }; } });
  await host.setSettings({ deepseekApiKey: "test-key" });
  const a = (await host.createAgent({ name: "Owner" })).profile.id;
  const b = (await host.createAgent({ name: "Worker" })).profile.id;
  const work = await host.createWork({ name: "Delivery" });
  for (const id of [a,b]) await host.attachWorkMember({ workId: work.id, agentId: id, role: "worker", expectedRevision: 0 });
  const ctx = (agentId: string, taskId?: string, toolCallId = "create") => ({ agentId, assistantId: "assistant", toolCallId, runContext: { kind: "work" as const, workId: work.id, taskId, triggerEventId: "trigger", catalogRevision: 0, catalog: [], requestedBy: { kind: "user" as const, id: "local-user" } } });
  const task = JSON.parse(await host.createTaskFromModel(a, { title: "Build", description: "", acceptanceCriteria: [], assigneeIds: [] }, ctx(a)));
  assert.equal(task.ownerAgentId, a);
  await host.delegateWork(a, { agent_id: b, task_id: task.id, instruction: "Build component" }, ctx(a, task.id, "delegate"));
  assert.equal((await host.getWork(work.id)).tasks[0]!.ownerAgentId, a);
  for (let i = 0; i < 100 && starts.length < 1; i++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(starts.length, 1);
  await host.sendWorkMessage(b, { type: "text", content: "Worker result", cardAction: { status: "review", deliverables: [] } }, ctx(b, task.id, "result"));
  // Shared room roots serialize runs; delivery does not release the worker slot until turn.ended.
  emit("turn.ended", { runId: starts[0]!.runId, status: "idle" });
  for (let i = 0; i < 100 && starts.length < 2; i++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(starts.length, 2);
  assert.match(JSON.stringify(starts[1]!.messages), /Worker result/);
  assert.equal((await host.getWork(work.id)).tasks[0]!.state, "in_progress");
  assert.equal((await host.store.readTranscript(a)).length, 0);
  await host.sendWorkMessage(a, { type: "text", content: "Need approval", cardAction: { status: "blocked", blocker_reason: "User decision", deliverables: [] } }, ctx(a, task.id, "blocked"));
  const blocked = (await host.getWork(work.id)).tasks[0]!;
  await assert.rejects(host.claimTask(a, { taskId: task.id, expectedRevision: blocked.revision }, ctx(a, task.id, "claim")), /cannot|human/i);
  await assert.rejects(host.delegateWork(a, { agent_id: b, task_id: task.id, instruction: "Ignore blocker" }, ctx(a, task.id, "bad")), /human|blocked/i);
  await host.transitionWorkTask({ workId: work.id, taskId: task.id, to: "in_progress", expectedRevision: blocked.revision });
  assert.equal((await host.getWork(work.id)).tasks[0]!.ownerAgentId, a);
});

test("room discussion rotates, picks up agent mentions next round and stops on silence", async (t) => {
  let emit: (method: string, params: unknown) => void = () => undefined;
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await runtime(t, { ...quietKernel, onEvent: handler => { emit = handler; }, start: async params => { starts.push(params); return { ok: true }; } });
  await host.setSettings({ deepseekApiKey: "test-key" });
  const a = (await host.createAgent({ name: "Alice" })).profile.id;
  const b = (await host.createAgent({ name: "Bob" })).profile.id;
  const work = await host.createWork({ name: "Discussion", kind: "room" });
  for (const id of [a,b]) await host.attachWorkMember({ workId: work.id, agentId: id, role: "worker", expectedRevision: 0 });
  const waitStarts = async (count: number) => { for (let i=0; i<100 && starts.length<count; i++) await new Promise(resolve => setTimeout(resolve, 10)); assert.equal(starts.length, count); };
  await host.postWorkMessage({ workId: work.id, body: "@Alice start", mentionedAgentIds: [] });
  await waitStarts(1);
  const context = host.scheduler.contextFor(starts[0]!.runId)!;
  await assert.rejects(host.delegateWork(a, { agent_id: b, instruction: "Bypass discussion budget" }, { agentId: a, assistantId: "a", toolCallId: "bypass", runContext: context }), /requires a card/);
  await host.postToWork(a, { message: "@Bob please check" }, { agentId: a, assistantId: "a", toolCallId: "one", runContext: context });
  await host.postToWork(a, { message: "Second message" }, { agentId: a, assistantId: "a", toolCallId: "two", runContext: context });
  await assert.rejects(host.postToWork(a, { message: "Third" }, { agentId: a, assistantId: "a", toolCallId: "three", runContext: context }), /budget/);
  emit("turn.ended", { runId: starts[0]!.runId, status: "idle" });
  await waitStarts(2);
  assert.equal(host.scheduler.agentIdFor(starts[1]!.runId), b);
  await host.postToWork(b, { message: "(pass)" }, { agentId: b, assistantId: "b", toolCallId: "pass", runContext: host.scheduler.contextFor(starts[1]!.runId)! });
  emit("turn.ended", { runId: starts[1]!.runId, status: "idle" });
  await waitStarts(3);
  assert.equal(host.scheduler.agentIdFor(starts[2]!.runId), a);
  emit("turn.ended", { runId: starts[2]!.runId, status: "idle" });
  for (let i=0; i<30; i++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(starts.length, 3);
  assert.equal((await host.getWork(work.id)).chat.length, 3);
});

test("discussion stops at ten public messages even when every member keeps speaking", async (t) => {
  let emit: (method: string, params: unknown) => void = () => undefined;
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await runtime(t, { ...quietKernel, onEvent: handler => { emit = handler; }, start: async params => { starts.push(params); return { ok: true }; } });
  await host.setSettings({ deepseekApiKey: "test-key" });
  const work = await host.createWork({ name: "Bounded", kind: "room" });
  for (let i=0; i<6; i++) {
    const id = (await host.createAgent({ name: `Member ${i}` })).profile.id;
    await host.attachWorkMember({ workId: work.id, agentId: id, role: "worker", expectedRevision: 0 });
  }
  await host.postWorkMessage({ workId: work.id, body: "Discuss", mentionedAgentIds: [] });
  for (let i=0; i<10; i++) {
    for (let retry=0; retry<100 && starts.length<=i; retry++) await new Promise(resolve => setTimeout(resolve, 10));
    assert.equal(starts.length, i+1);
    const runId = starts[i]!.runId;
    const agentId = host.scheduler.agentIdFor(runId)!;
    await host.postToWork(agentId, { message: `Contribution ${i}` }, { agentId, assistantId: `a${i}`, toolCallId: "send", runContext: host.scheduler.contextFor(runId)! });
    emit("turn.ended", { runId, status: "idle" });
  }
  for (let i=0; i<30; i++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(starts.length, 10);
  assert.equal((await host.getWork(work.id)).chat.length, 11);
});

test("a new user message preserves publication from the already started member", async (t) => {
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await runtime(t, { ...quietKernel, start: async params => { starts.push(params); return { ok: true }; } });
  await host.setSettings({ deepseekApiKey: "test-key" });
  const id = (await host.createAgent({ name: "Reader" })).profile.id;
  const work = await host.createWork({ name: "Epoch", kind: "room" });
  await host.attachWorkMember({ workId: work.id, agentId: id, role: "worker", expectedRevision: 0 });
  await host.postWorkMessage({ workId: work.id, body: "First", mentionedAgentIds: [] });
  for (let i=0; i<100 && !starts.length; i++) await new Promise(resolve => setTimeout(resolve, 10));
  const context = host.scheduler.contextFor(starts[0]!.runId)!;
  await host.postWorkMessage({ workId: work.id, body: "Actually, change direction", mentionedAgentIds: [] });
  await host.postToWork(id, { message: "Reply already in progress" }, { agentId: id, assistantId: "a", toolCallId: "send", runContext: context });
  assert.equal((await host.getWork(work.id)).chat.length, 3);
});

test("NunuBar wakes without a mention just like a local room", async (t) => {
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await runtime(t, { ...quietKernel, start: async params => { starts.push(params); return { ok: true }; } });
  await host.setSettings({ deepseekApiKey: "test-key" });
  const id = (await host.createAgent({ name: "Responder" })).profile.id;
  const work = await host.createWork({ name: "Bar", kind: "work" });
  await host.attachWorkMember({ workId: work.id, agentId: id, role: "worker", expectedRevision: 0 });
  await host.postWorkMessage({ workId: work.id, body: "Please discuss", mentionedAgentIds: [] });
  for (let i = 0; i < 50 && !starts.length; i++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(starts.length, 1);
});

async function historyMessage(host: HostRuntime, workId: string, body: string) {
  return host.workStore.appendEvent(workId, { type: "chat.posted", id: crypto.randomUUID(), workId,
    messageId: crypto.randomUUID(), createdAt: Date.now(), actor: { kind: "user", id: "local-user" }, body, mentionedAgentIds: [] });
}

async function until(predicate: () => boolean | Promise<boolean>, label: string) {
  for (let i = 0; i < 200; i++) {
    if (await predicate()) return;
    await new Promise(resolve => setTimeout(resolve, 5));
  }
  assert.fail(`Timed out: ${label}`);
}

async function revive(t: TestContext, original: HostRuntime, starts: import("@nuum/protocol").TurnStartParams[]) {
  await original.dispose();
  const host = new HostRuntime({ dataDir: original.store.dataDir, kernelCommand: "unused", kernelArgs: [], spawnKernel: () => ({ ...quietKernel, start: async params => { starts.push(params); return { ok: true }; } }) });
  host.store.secrets.deepseekApiKey = "test-key";
  await host.start();
  t.after(() => host.dispose());
  return host;
}

test("restart does not replay an uncertain discussion; explicit continue opens a fresh discussion", async (t) => {
  const firstStarts: import("@nuum/protocol").TurnStartParams[] = [];
  const first = await runtime(t, { ...quietKernel, start: async params => { firstStarts.push(params); return { ok: true }; } });
  await first.setSettings({ deepseekApiKey: "test-key" });
  const agent = await first.createAgent({ name: "A" });
  const work = await first.createWork({ name: "Restart", kind: "room" });
  await first.attachWorkMember({ workId: work.id, agentId: agent.profile.id, role: "worker", expectedRevision: 0 });
  await first.postWorkMessage({ workId: work.id, body: "Discuss", mentionedAgentIds: [] });
  await until(() => firstStarts.length === 1, "first start");
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await revive(t, first, starts);
  const snapshot = await host.getWork(work.id);
  assert.equal(starts.length, 0);
  assert.equal(snapshot.interruptions.filter(item => item.kind === "discussion").length, 1);
  await host.continueWork(work.id, snapshot.interruptions[0]!.eventId);
  await until(() => starts.length === 1, "explicit continuation");
  assert.equal((await host.getWork(work.id)).events.filter(event => event.type === "discussion.started").length, 2);
  assert.equal((await host.getWork(work.id)).interruptions.length, 0);
});

test("an uncertain card stays stopped after restart and resumes its existing private session", async (t) => {
  const first = await runtime(t);
  await first.setSettings({ deepseekApiKey: "test-key" });
  const agent = await first.createAgent({ name: "Worker" });
  const work = await first.createWork({ name: "Card restart" });
  await first.attachWorkMember({ workId: work.id, agentId: agent.profile.id, role: "worker", expectedRevision: 0 });
  const task = await first.createWorkTask({ workId: work.id, title: "Build", description: "", acceptanceCriteria: [], assigneeIds: [agent.profile.id], dependencyIds: [], priority: "normal" });
  await first.dispatchWork({ workId: work.id, taskId: task.id, agentId: agent.profile.id, instruction: "Build safely" });
  const originalSession = (await first.sessions.list(work.id, task.id))[0]!;
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await revive(t, first, starts);
  const snapshot = await host.getWork(work.id);
  assert.equal(starts.length, 0);
  assert.equal(snapshot.interruptions[0]?.taskId, task.id);
  await host.continueWork(work.id, snapshot.interruptions[0]!.eventId);
  await until(() => starts.length === 1, "card continuation");
  assert.equal((await host.sessions.list(work.id, task.id))[0]?.id, originalSession.id);
  assert.equal((await host.store.readTranscript(agent.profile.id)).length, 0);
});

test("explicit stop rejects late replies and is not resurrected after restart", async (t) => {
  const firstStarts: import("@nuum/protocol").TurnStartParams[] = [];
  const first = await runtime(t, { ...quietKernel, start: async params => { firstStarts.push(params); return { ok: true }; } });
  await first.setSettings({ deepseekApiKey: "test-key" });
  const agentId = (await first.createAgent({ name: "A" })).profile.id;
  const work = await first.createWork({ name: "Stop", kind: "room" });
  await first.attachWorkMember({ workId: work.id, agentId, role: "worker", expectedRevision: 0 });
  await first.postWorkMessage({ workId: work.id, body: "Discuss", mentionedAgentIds: [] });
  await until(() => firstStarts.length === 1, "start");
  const context = first.scheduler.contextFor(firstStarts[0]!.runId)!;
  await first.stopWorkDiscussion(work.id);
  await assert.rejects(first.postToWork(agentId, { message: "Late reply" }, { agentId, assistantId: "a", toolCallId: "late", runContext: context }), /stopped|cancelled/i);
  const starts: import("@nuum/protocol").TurnStartParams[] = [];
  const host = await revive(t, first, starts);
  assert.equal(starts.length, 0);
  assert.equal((await host.getWork(work.id)).interruptions.length, 0);
});

test("a single card cannot acquire a second worker before the first result", async (t) => {
  const host = await runtime(t);
  await host.setSettings({ deepseekApiKey: "test-key" });
  const a = (await host.createAgent({ name: "A" })).profile.id;
  const b = (await host.createAgent({ name: "B" })).profile.id;
  const work = await host.createWork({ name: "Serial card" });
  for (const agentId of [a, b]) await host.attachWorkMember({ workId: work.id, agentId, role: "worker", expectedRevision: 0 });
  const task = await host.createWorkTask({ workId: work.id, title: "Build", description: "", acceptanceCriteria: [], assigneeIds: [], dependencyIds: [], priority: "normal" });
  await host.dispatchWork({ workId: work.id, taskId: task.id, agentId: a, instruction: "Build" });
  await assert.rejects(host.dispatchWork({ workId: work.id, taskId: task.id, agentId: b, instruction: "Also build" }), /already has a worker/i);
});

test("snapshot watermark matches its full log prefix including non-chat events", async (t) => {
  const host = await runtime(t);
  const work = await host.createWork({ name: "Ordered" });
  const agent = await host.createAgent({ name: "A" });
  await historyMessage(host, work.id, "First");
  await host.attachWorkMember({ workId: work.id, agentId: agent.profile.id, role: "worker", expectedRevision: 0 });
  await historyMessage(host, work.id, "Third");
  const snapshot = await host.getWork(work.id);
  assert.equal(snapshot.throughSeq, 3);
  assert.deepEqual(snapshot.chat.map(event => event.seq), [1, 3]);
  assert.equal(snapshot.events.at(-1)?.seq, snapshot.throughSeq);
});

test("stopping an agent whose discussion is queued stops the entire discussion", async (t) => {
  const host = await runtime(t);
  await host.setSettings({ deepseekApiKey: "test-key" });
  const a = (await host.createAgent({ name: "A" })).profile.id;
  const b = (await host.createAgent({ name: "B" })).profile.id;
  const work = await host.createWork({ name: "Queued stop", kind: "room" });
  for (const agentId of [a, b]) await host.attachWorkMember({ workId: work.id, agentId, role: "worker", expectedRevision: 0 });
  await host.send(a, "Hold the main slot");
  await host.postWorkMessage({ workId: work.id, body: "Discuss", mentionedAgentIds: [] });
  await until(() => host.scheduler.queuedForAgent(a).length === 1, "queued discussion");
  await host.cancel(a);
  await until(async () => !(await host.getWork(work.id)).discussionRunning, "discussion stopped");
  const snapshot = await host.getWork(work.id);
  assert.equal(snapshot.events.some(event => event.type === "execution.started" && event.agentId === b), false);
  assert.equal(snapshot.interruptions.length, 0);
});
