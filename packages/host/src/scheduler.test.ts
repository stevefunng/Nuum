import assert from "node:assert/strict";
import { test } from "node:test";
import { AgentScheduler } from "./scheduler.js";
import type { RunContext } from "./run-context.js";

/** 起一个永不自行收束的 run，收束时机完全由用例用 settle() 掐。 */
function held(agentId: string, log: string[]) {
  return {
    agentId,
    context: { kind: "direct" } as const,
    start: async (runId: string) => {
      log.push(`${agentId}:${runId}`);
    }
  };
}

function counted(): () => string {
  let n = 0;
  return () => `r${(n += 1)}`;
}

test("different agents run in parallel up to the global cap", async () => {
  const log: string[] = [];
  const scheduler = new AgentScheduler(2, counted());

  assert.equal(scheduler.submit(held("a", log)).state, "started");
  assert.equal(scheduler.submit(held("b", log)).state, "started");
  // 第三个 agent 自己是空闲的，挡住它的是全局并发上限。
  assert.equal(scheduler.submit(held("c", log)).state, "queued");

  await Promise.resolve();
  assert.deepEqual(log, ["a:r1", "b:r2"]);
  assert.equal(scheduler.queueDepth(), 1);

  scheduler.settle("r1");
  await Promise.resolve();
  assert.deepEqual(log, ["a:r1", "b:r2", "c:r3"]);
  assert.equal(scheduler.queueDepth(), 0);
});

test("one agent never has two runs at once, even below the cap", async () => {
  const log: string[] = [];
  const scheduler = new AgentScheduler(3, counted());

  assert.equal(scheduler.submit(held("a", log)).state, "started");
  assert.equal(scheduler.submit(held("a", log)).state, "queued");
  await Promise.resolve();
  assert.deepEqual(log, ["a:r1"]);

  scheduler.settle("r1");
  await Promise.resolve();
  assert.deepEqual(log, ["a:r1", "a:r2"]);
});

test("a busy agent at the queue head does not block other agents behind it", async () => {
  const log: string[] = [];
  const scheduler = new AgentScheduler(2, counted());

  scheduler.submit(held("a", log)); // r1 活跃
  scheduler.submit(held("b", log)); // r2 活跃，并发占满
  scheduler.submit(held("a", log)); // r3 排队，队首
  scheduler.submit(held("c", log)); // r4 排队，队尾
  await Promise.resolve();
  assert.deepEqual(log, ["a:r1", "b:r2"]);

  // b 腾出一个位置，而队首的 r3 属于仍在跑的 a：得跳过它让给能跑的 c，
  // 否则一个忙 agent 的排队项会把后面所有别的 agent 全堵住。
  scheduler.settle("r2");
  await Promise.resolve();
  assert.deepEqual(log, ["a:r1", "b:r2", "c:r4"]);
  assert.equal(scheduler.queueDepth(), 1);

  scheduler.settle("r1");
  await Promise.resolve();
  assert.deepEqual(log, ["a:r1", "b:r2", "c:r4", "a:r3"]);
});

test("cancel only touches the given agent, and drops its queued runs", async () => {
  const log: string[] = [];
  const scheduler = new AgentScheduler(2, counted());

  scheduler.submit(held("a", log));
  scheduler.submit(held("b", log));
  scheduler.submit(held("a", log)); // a 的排队项，还没进 Kernel
  await Promise.resolve();

  const cancelling = scheduler.cancelAgent("a");
  // 只回活跃的那个 runId：排队中的从没进 Kernel，无从取消也不该去取消。
  assert.deepEqual(cancelling, ["r1"]);
  assert.equal(scheduler.queueDepth(), 0);
  assert.equal(scheduler.isBusy("b"), true);
  assert.deepEqual(scheduler.activeRunIds(), ["r1", "r2"]);

  scheduler.settle("r1");
  await Promise.resolve();
  assert.equal(scheduler.isBusy("a"), false);
  assert.deepEqual(log, ["a:r1", "b:r2"]);
});

test("runId resolves back to its agent while active, and to nothing after", () => {
  const scheduler = new AgentScheduler(2, counted());
  scheduler.submit(held("a", []));
  assert.equal(scheduler.agentIdFor("r1"), "a");
  assert.equal(scheduler.activeRunFor("a"), "r1");
  assert.deepEqual(scheduler.contextFor("r1"), { kind: "direct" });

  scheduler.settle("r1");
  // 收束后必须查不到，否则迟到的 Kernel 事件会被记到这个 agent 账上。
  assert.equal(scheduler.agentIdFor("r1"), undefined);
  assert.equal(scheduler.activeRunFor("a"), undefined);
  assert.equal(scheduler.contextFor("r1"), undefined);
});

test("a work run keeps one frozen context while it is queued and active", async () => {
  const scheduler = new AgentScheduler(1, counted());
  scheduler.submit(held("busy", []));
  const context: RunContext = {
    kind: "work",
    workId: "work-1",
    taskId: "task-1",
    triggerEventId: "event-1",
    catalogRevision: 7,
    catalog: [],
    requestedBy: { kind: "user", id: "user-1" }
  };

  const queued = scheduler.submit({ agentId: "worker", context, start: async () => undefined });
  assert.equal(queued.state, "queued");
  assert.deepEqual(scheduler.contextFor(queued.runId), context);

  scheduler.settle("r1");
  await Promise.resolve();
  assert.deepEqual(scheduler.contextFor(queued.runId), context);
});

test("a run whose start throws still frees its slot", async () => {
  const log: string[] = [];
  const scheduler = new AgentScheduler(1, counted());
  scheduler.submit({
    agentId: "a",
    context: { kind: "direct" },
    start: async () => {
      throw new Error("kernel refused");
    }
  });
  scheduler.submit(held("b", log));

  // 让 launch 里的 catch → settle → pump 这一串跑完。
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(log, ["b:r2"]);
  assert.equal(scheduler.isBusy("a"), false);
});

test("queued runs count as busy so the sidebar does not flicker back to idle", () => {
  const scheduler = new AgentScheduler(1, counted());
  scheduler.submit(held("a", []));
  scheduler.submit(held("b", []));
  assert.equal(scheduler.isBusy("b"), true);
});

test("awaiting completion observes settled runs and queued cancellation, not just kernel start", async () => {
  const scheduler = new AgentScheduler(1, counted());
  const first = scheduler.submit(held("a", []));
  const second = scheduler.submit(held("a", []));
  let completed = false;
  void first.completed.then(() => { completed = true; });
  await first.started;
  assert.equal(completed, false);
  scheduler.cancelAgent("a");
  assert.equal(await second.completed, "cancelled");
  scheduler.settle(first.runId, "failed");
  assert.equal(await first.completed, "failed");
});

test("different agents sharing a writable project do not run concurrently", async () => {
  const scheduler = new AgentScheduler(3, counted());
  const log: string[] = [];
  const a = scheduler.submit({ ...held("a", log), projectRoot: "/project" });
  const b = scheduler.submit({ ...held("b", log), projectRoot: "/project/subdir" });
  const c = scheduler.submit({ ...held("c", log), projectRoot: "/other" });
  assert.equal(b.state, "queued");
  assert.equal(c.state, "started");
  scheduler.settle(a.runId);
  await Promise.resolve();
  assert.ok(log.includes(`b:${b.runId}`));
});
