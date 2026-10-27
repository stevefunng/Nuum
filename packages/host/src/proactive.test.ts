import { testTempDir } from "../../../scripts/test-temp.mjs";
import assert from "node:assert/strict";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { AgentStore } from "./agent-store.js";
import { ProactiveService } from "./proactive.js";

async function fixture(t: { after(fn: () => Promise<void>): void }) {
  const dir = await testTempDir(path.join(tmpdir(), "nuum-proactive-"));
  const store = new AgentStore(dir);
  let now = 1_000_000;
  const service = new ProactiveService(store, () => ({ provider: "deepseek", model: "deepseek-chat" }), () => undefined, () => now);
  t.after(async () => { await service.dispose(); await store.dispose(); });
  await store.init();
  return { store, service, advance: (ms: number) => { now += ms; } };
}

test("proactive is opt-in and repeated enable creates one persistent default entity", async (t) => {
  const { service, store } = await fixture(t);
  assert.equal((await service.snapshot()).defaultAgentId, null);
  assert.equal(store.listAgents().length, 0);
  const first = await service.configure({ expectedRevision: 0, enabled: true });
  const id = first.defaultAgentId!;
  assert.ok(id);
  assert.equal(first.agents[0]!.state, "waiting-context");
  await assert.rejects(() => service.configure({ expectedRevision: 0, enabled: true }), /revision/i);
  assert.equal(store.listAgents().length, 1);
  await service.dispose();
  const restarted = new ProactiveService(store, () => ({ provider: "deepseek", model: "deepseek-chat" }), () => undefined);
  t.after(async () => restarted.dispose());
  assert.equal((await restarted.snapshot()).defaultAgentId, id);
  assert.equal(store.requireAgent(id).settings.proactive?.enabled, true);
});

test("pause, expiry and disable gate checks; no sources never pretends to evaluate", async (t) => {
  const { service, advance } = await fixture(t);
  let snapshot = await service.configure({ expectedRevision: 0, enabled: true });
  const id = snapshot.defaultAgentId!;
  await service.check(id);
  assert.equal((await service.snapshot()).agents[0]!.activity[0]!.kind, "waiting-context");
  snapshot = await service.configure({ agentId: id, expectedRevision: 1, pausedUntil: 1_060_000 });
  assert.equal(snapshot.agents[0]!.state, "paused");
  await assert.rejects(() => service.check(id), /paused/i);
  advance(60_001);
  assert.equal((await service.snapshot()).agents[0]!.state, "waiting-context");
  await service.configure({ agentId: id, expectedRevision: 2, enabled: false });
  await assert.rejects(() => service.check(id), /disabled/i);
});

test("policies are per entity and an in-flight context result is discarded after disable", async (t) => {
  const { service, store } = await fixture(t);
  let complete!: (refs: string[]) => void;
  service.registerSource({ id: "test", collect: () => new Promise<string[]>((resolve) => { complete = resolve; }) });
  const first = await service.configure({ expectedRevision: 0, enabled: true, sourceIds: ["test"] });
  const id = first.defaultAgentId!;
  await store.createAgent({ id: "second", name: "Second", description: "", createdAt: 1 }, { model: { provider: "deepseek", model: "deepseek-chat" } });
  await service.configure({ agentId: "second", expectedRevision: 0, enabled: true });
  const checking = service.check(id);
  await new Promise((resolve) => setImmediate(resolve));
  await service.configure({ agentId: id, expectedRevision: 1, enabled: false });
  complete(["opaque-context-ref"]);
  await checking;
  const snapshot = await service.snapshot();
  assert.equal(snapshot.agents.find((a) => a.agentId === id)!.state, "disabled");
  assert.equal(snapshot.agents.find((a) => a.agentId === "second")!.state, "waiting-context");
  assert.equal(snapshot.agents.find((a) => a.agentId === id)!.activity.some((a) => a.kind === "context-ready"), false);
});

test("policy and recent activity survive a fresh store reload", async (t) => {
  const { service, store } = await fixture(t);
  const enabled = await service.configure({ expectedRevision: 0, enabled: true });
  const id = enabled.defaultAgentId!;
  await service.configure({ agentId: id, expectedRevision: 1, pausedUntil: 2_000_000 });
  await service.dispose(); await store.dispose();
  const reopenedStore = new AgentStore(store.dataDir);
  const reopened = new ProactiveService(reopenedStore, () => ({ provider: "deepseek", model: "deepseek-chat" }), () => undefined, () => 1_000_000);
  t.after(async () => { await reopened.dispose(); await reopenedStore.dispose(); });
  await reopenedStore.init();
  const restored = await reopened.snapshot();
  assert.equal(restored.defaultAgentId, id);
  assert.equal(restored.agents[0]!.state, "paused");
  assert.equal(restored.agents[0]!.activity[0]!.kind, "paused");
  assert.equal(reopenedStore.listAgents().length, 1);
});

test("the host timer checks only explicitly configured sources and never writes a conversation", async (t) => {
  const { service, store } = await fixture(t);
  let calls = 0;
  service.registerSource({ id: "local-test", async collect() { calls++; return ["context-1"]; } });
  const enabled = await service.configure({ expectedRevision: 0, enabled: true, sourceIds: ["local-test"], intervalMs: 60_000 });
  const id = enabled.defaultAgentId!;
  service.start();
  await new Promise((resolve) => setTimeout(resolve, 1150));
  assert.equal(calls, 1);
  assert.equal((await service.snapshot()).agents[0]!.activity[0]!.kind, "context-ready");
  assert.equal((await store.readTranscript(id)).length, 0);
  await service.check(id);
  assert.equal(calls, 1, "cooldown returns the current snapshot without a second collection");
});


test("rapid checks share one run and cached results without errors or duplicate activity", async (t) => {
  const { service, advance } = await fixture(t);
  let calls = 0;
  let complete!: (refs: string[]) => void;
  service.registerSource({ id: "slow", collect: () => { calls++; return new Promise<string[]>((resolve) => { complete = resolve; }); } });
  const snapshot = await service.configure({ expectedRevision: 0, enabled: true, sourceIds: ["slow"] });
  const id = snapshot.defaultAgentId!;
  const results = Promise.all(Array.from({ length: 8 }, () => service.check(id)));
  complete(["context-ref"]);
  await results;
  await Promise.all(Array.from({ length: 8 }, () => service.check(id)));
  assert.equal(calls, 1);
  assert.equal((await service.snapshot()).agents[0]!.activity.filter((item) => item.kind === "context-ready").length, 1);
  advance(5001);
  const next = service.check(id);
  complete(["next-ref"]);
  await next;
  assert.equal(calls, 2);
});

test("rapid manual checks with no sources remain a normal waiting state", async (t) => {
  const { service } = await fixture(t);
  const snapshot = await service.configure({ expectedRevision: 0, enabled: true });
  const id = snapshot.defaultAgentId!;
  await service.check(id);
  const results = await Promise.all(Array.from({ length: 10 }, () => service.check(id)));
  assert.ok(results.every((result) => result.agents[0]!.state === "waiting-context"));
  assert.equal(results[0]!.agents[0]!.activity.filter((item) => item.kind === "waiting-context").length, 1);
});
