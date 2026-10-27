import { testTempDir } from "../../../scripts/test-temp.mjs";
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test, type TestContext } from "node:test";
import type {
  KernelHello,
  SummarizeRunParams,
  SummarizeRunResult,
  TurnStartParams,
  TurnToolDecision,
  TurnToolResult
} from "@nuum/protocol";
import { assembleContext } from "./context.js";
import type { KernelClient } from "./kernel-client.js";
import { MemoryStore } from "./memory.js";
import { HostRuntime, type DelegatedTool } from "./runtime.js";

/**
 * 一个不跑模型的 Kernel 替身：记下 Host 发来的每次调用，并把事件回路暴露出来，
 * 让用例能精确控制「Kernel 什么时候吐什么事件」。
 */
class FakeKernel implements KernelClient {
  readonly started: TurnStartParams[] = [];
  readonly cancelled: string[] = [];
  readonly decisions: TurnToolDecision[] = [];
  readonly results: TurnToolResult[] = [];
  readonly disposedShells: string[] = [];
  readonly summarized: SummarizeRunParams[] = [];
  private handler: (method: string, params: unknown) => void = () => undefined;

  async hello(): Promise<KernelHello> {
    return { name: "nuum-kernel", version: "0.1.0" };
  }

  async start(params: TurnStartParams): Promise<unknown> {
    this.started.push(params);
    return { ok: true };
  }

  async cancel(runId: string): Promise<unknown> {
    this.cancelled.push(runId);
    return { ok: true };
  }

  async decide(params: TurnToolDecision): Promise<unknown> {
    this.decisions.push(params);
    return { ok: true };
  }

  async provideToolResult(params: TurnToolResult): Promise<unknown> {
    this.results.push(params);
    return { ok: true };
  }

  async disposeShell(terminals: string): Promise<unknown> {
    this.disposedShells.push(terminals);
    return { ok: true };
  }

  /** 单发模型调用（记忆抽取、压缩）。默认什么都不抽，用例按需换掉。 */
  summarizeWith: (params: SummarizeRunParams) => string = () => "";

  async summarize(params: SummarizeRunParams): Promise<SummarizeRunResult> {
    this.summarized.push(params);
    return { text: this.summarizeWith(params) };
  }

  async tools(): Promise<unknown> {
    return [];
  }

  onEvent(handler: (method: string, params: unknown) => void): void {
    this.handler = handler;
  }

  dispose(): void {}

  emit(method: string, params: unknown): void {
    this.handler(method, params);
  }
}

/**
 * Host 处理一条 Kernel 事件要走好几次异步文件读写，拍数不可预测，所以断言前
 * 轮询等条件成立，而不是猜「几个 setImmediate 够了」。
 */
async function waitFor(predicate: () => boolean | Promise<boolean>, what: string): Promise<void> {
  for (const deadline = Date.now() + 3000; Date.now() < deadline;) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 2));
  }
  assert.fail(`timed out waiting for ${what}`);
}

/** 断言「什么都没发生」时用：先放足够的拍数，让本该发生的事有机会发生。 */
async function quiet(): Promise<void> {
  for (let i = 0; i < 20; i += 1) await new Promise((resolve) => setImmediate(resolve));
}

interface Harness {
  runtime: HostRuntime;
  kernel: FakeKernel;
  dataDir: string;
  events: { method: string; params: any }[];
  send(id: string, content: string): Promise<{ runId: string; queued: boolean }>;
  transcript(id: string): Promise<string[]>;
  /** 发一条 Kernel 事件，并等到 Host 把它处理出可观察的结果。 */
  emit(method: string, params: unknown, until: () => boolean, what: string): Promise<void>;
}

interface HarnessOptions {
  delegatedTools?: DelegatedTool[];
  maxConcurrentRuns?: number;
  dataDir?: string;
  contextWindowTokens?: number;
}

/**
 * 在同一个 dataDir 上重开一个 Host，模拟进程重启。前一个必须已经 dispose ——
 * dataDir 锁不允许两个实例同时持有。
 */
async function reopenHarness(t: TestContext, previous: Harness): Promise<Harness> {
  return openHarness(t, { dataDir: previous.dataDir });
}

async function openHarness(t: TestContext, options: HarnessOptions = {}): Promise<Harness> {
  const { dataDir: reuse, ...runtimeOptions } = options;
  const dataDir = reuse ?? (await testTempDir(path.join(tmpdir(), "nuum-run-")));
  const kernel = new FakeKernel();
  const events: { method: string; params: any }[] = [];
  const runtime = new HostRuntime({
    dataDir,
    kernelCommand: "unused",
    kernelArgs: [],
    spawnKernel: () => kernel,
    ...runtimeOptions
  });
  t.after(() => runtime.dispose());
  runtime.setEmitter((method, params) => events.push({ method, params: params as any }));
  await runtime.start();
  await runtime.setSettings({ deepseekApiKey: "test-key" });
  return {
    runtime,
    kernel,
    dataDir,
    events,
    send: (id, content) => runtime.send(id, content),
    async transcript(id) {
      const page = await runtime.getTranscript(id);
      return page.entries.map((event) => event.type);
    },
    async emit(method, params, until, what) {
      kernel.emit(method, params);
      await waitFor(until, what);
    }
  };
}

function emitted(harness: Harness, method: string): any[] {
  return harness.events.filter((event) => event.method === method).map((event) => event.params);
}

test("two agents run at the same time and their events stay apart", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;

  const first = await harness.send(alpha, "alpha asks");
  const second = await harness.send(beta, "beta asks");
  assert.equal(first.queued, false);
  assert.equal(second.queued, false);
  assert.notEqual(first.runId, second.runId);
  assert.equal(harness.kernel.started.length, 2);

  await harness.emit(
    "turn.delta",
    { runId: second.runId, messageId: "m-beta", delta: "beta thinking", part: "text" },
    () => emitted(harness, "agent.message.delta").length === 1,
    "beta's delta"
  );
  await harness.emit(
    "turn.delta",
    { runId: first.runId, messageId: "m-alpha", delta: "alpha thinking", part: "text" },
    () => emitted(harness, "agent.message.delta").length === 2,
    "alpha's delta"
  );

  // 交错到达的 delta 必须各归各的 agent —— Kernel 只给 runId，归属是 Host 查的。
  const deltas = emitted(harness, "agent.message.delta");
  assert.deepEqual(
    deltas.map((event) => [event.agentId, event.delta]),
    [
      [beta, "beta thinking"],
      [alpha, "alpha thinking"]
    ]
  );
  assert.deepEqual(deltas.map((event) => event.runId), [second.runId, first.runId]);

  // alpha 收束后只有 alpha 的时间线多出 assistant，beta 的一动没动。
  await harness.emit(
    "turn.ended",
    { runId: first.runId, status: "idle" },
    () => emitted(harness, "agent.ended").length === 1,
    "alpha's turn to end"
  );
  assert.deepEqual(await harness.transcript(alpha), ["user", "assistant"]);
  assert.deepEqual(await harness.transcript(beta), ["user"]);
});

test("cancel kills only the asking agent's run", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  const first = await harness.send(alpha, "long job");
  const second = await harness.send(beta, "other job");

  await harness.runtime.cancel(alpha);
  assert.deepEqual(harness.kernel.cancelled, [first.runId]);

  await harness.emit(
    "turn.ended",
    { runId: first.runId, status: "cancelled" },
    () => emitted(harness, "agent.ended").length === 1,
    "alpha's turn to end"
  );
  const ended = emitted(harness, "agent.ended");
  assert.deepEqual(ended, [{ agentId: alpha, runId: first.runId, status: "cancelled" }]);

  // beta 毫发无损，还在跑。
  const views = await harness.runtime.listAgents();
  const status = new Map(views.map((view) => [view.profile.id, view.runtime.status]));
  assert.equal(status.get(alpha), "idle");
  assert.equal(status.get(beta), "running");
  assert.equal(harness.kernel.cancelled.length, 1);
  void second;
});

test("cancelled comes through as its own status, not as idle", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "go");
  await harness.emit(
    "turn.ended",
    { runId: run.runId, status: "cancelled" },
    () => emitted(harness, "agent.ended").length === 1,
    "the turn to end"
  );
  assert.equal(emitted(harness, "agent.ended")[0]!.status, "cancelled");
  // 但 cancelled 不是一种停留态：agent 收束后就是空闲。
  assert.equal((await harness.runtime.listAgents())[0]!.runtime.status, "idle");
});

test("a delegated tool runs on the host with the frozen run context", async (t) => {
  const seen: { args: Record<string, unknown>; agentId: string; runKind: string }[] = [];
  const tool: DelegatedTool = {
    definition: {
      name: "send_message",
      description: "post a message",
      inputSchema: { type: "object", properties: { text: { type: "string" } } },
      mutating: false
    },
    execute: async (args, context) => {
      seen.push({ args, agentId: context.agentId, runKind: context.runContext.kind });
      return "delivered";
    }
  };
  const harness = await openHarness(t, { delegatedTools: [tool] });
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "say hi");

  // 委派工具的 definition 必须真送到 Kernel，否则模型看不见它。
  assert.ok(harness.kernel.started[0]!.delegatedTools.some((entry) => entry.name === "send_message"));
  assert.equal(harness.kernel.started[0]!.localToolNames.includes("send_message"), false);

  await harness.emit(
    "turn.tool.delegate",
    { runId: run.runId, toolCallId: "call-1", name: "send_message", arguments: { text: "hi" } },
    () => harness.kernel.results.length === 1,
    "the delegated result to come back"
  );

  assert.deepEqual(seen, [{ args: { text: "hi" }, agentId: id, runKind: "direct" }]);
  assert.deepEqual(harness.kernel.results, [
    { runId: run.runId, toolCallId: "call-1", ok: true, output: "delivered" }
  ]);
});

test("a delegated tool that throws still unblocks the run", async (t) => {
  const tool: DelegatedTool = {
    definition: { name: "boom", description: "fails", inputSchema: { type: "object", properties: {} }, mutating: false },
    execute: async () => {
      throw new Error("target agent not found");
    }
  };
  const harness = await openHarness(t, { delegatedTools: [tool] });
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "go");
  await harness.emit(
    "turn.tool.delegate",
    { runId: run.runId, toolCallId: "call-1", name: "boom", arguments: {} },
    () => harness.kernel.results.length === 1,
    "the failure to come back as a result"
  );
  // 失败也必须回一条结果，否则那个 run 会永远卡在等待里。
  assert.deepEqual(harness.kernel.results, [
    { runId: run.runId, toolCallId: "call-1", ok: false, output: "target agent not found" }
  ]);
});

test("an unknown delegated tool answers instead of hanging the run", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "go");
  await harness.emit(
    "turn.tool.delegate",
    { runId: run.runId, toolCallId: "call-1", name: "ghost", arguments: {} },
    () => harness.kernel.results.length === 1,
    "the unknown tool to be answered"
  );
  assert.deepEqual(harness.kernel.results, [
    { runId: run.runId, toolCallId: "call-1", ok: false, output: "Unknown delegated tool: ghost" }
  ]);
});

test("events for a settled run are dropped, not charged to the agent", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "go");
  await harness.emit(
    "turn.ended",
    { runId: run.runId, status: "idle" },
    () => emitted(harness, "agent.ended").length === 1,
    "the turn to end"
  );

  const before = await harness.transcript(id);
  harness.kernel.emit("turn.tool.completed", {
    runId: run.runId,
    toolCallId: "late",
    name: "read",
    ok: true,
    output: "stale"
  });
  await quiet();
  assert.deepEqual(await harness.transcript(id), before);
});

test("tool approval is routed to the agent's active run", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "write a file");
  await harness.emit(
    "turn.tool.pending",
    {
      runId: run.runId,
      toolCallId: "call-1",
      name: "write",
      arguments: { path: "a.txt" },
      mutating: true,
      action: "write-file",
      target: path.join(harness.dataDir, "a.txt")
    },
    () => emitted(harness, "agent.tool.pending").length === 1,
    "the approval card"
  );
  assert.equal(emitted(harness, "agent.tool.pending")[0]!.runId, run.runId);

  await harness.runtime.decide(id, "call-1", "once");
  assert.deepEqual(harness.kernel.decisions, [{ runId: run.runId, toolCallId: "call-1", resolution: "once" }]);
});

test("always approval is persisted as the exact action and target for the next run", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const target = path.join(harness.dataDir, "outside-project.txt");
  const run = await harness.send(id, "read it");
  await harness.emit(
    "turn.tool.pending",
    {
      runId: run.runId,
      toolCallId: "call-approval",
      name: "read",
      arguments: { path: target },
      mutating: false,
      action: "read-file",
      target
    },
    () => emitted(harness, "agent.tool.pending").length === 1,
    "the approval card"
  );
  await harness.runtime.decide(id, "call-approval", "always");
  assert.deepEqual(await harness.runtime.store.readApprovals(id), {
    always: [{ action: "read-file", target }],
    refused: []
  });

  await harness.emit(
    "turn.ended",
    { runId: run.runId, status: "idle" },
    () => emitted(harness, "agent.ended").length === 1,
    "the first turn to end"
  );
  await harness.send(id, "read it again");
  assert.deepEqual(harness.kernel.started[1]!.approvals, [{ action: "read-file", target }]);
});

test("deny is remembered for anti-nag, while never lowers only this agent's permission", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  const target = path.join(harness.dataDir, "outside-project.txt");
  const run = await harness.send(alpha, "write it");
  await harness.emit(
    "turn.tool.pending",
    {
      runId: run.runId,
      toolCallId: "call-never",
      name: "write",
      arguments: { path: target },
      mutating: true,
      action: "write-file",
      target
    },
    () => emitted(harness, "agent.tool.pending").length === 1,
    "the approval card"
  );
  await harness.runtime.decide(alpha, "call-never", "never");
  assert.deepEqual((await harness.runtime.getAgent(alpha)).view.settings.workspace, {
    projectRoot: (await harness.runtime.getAgent(alpha)).view.settings.workspace!.projectRoot,
    toolPermission: "never"
  });
  assert.deepEqual((await harness.runtime.getAgent(beta)).view.settings.workspace, {
    projectRoot: (await harness.runtime.getAgent(beta)).view.settings.workspace!.projectRoot,
    toolPermission: null
  });
  assert.deepEqual((await harness.runtime.store.readApprovals(alpha)).refused, [
    { action: "write-file", target }
  ]);
  assert.equal(harness.kernel.decisions[0]!.resolution, "never");
});

test("turn roots and project settings belong to the individual agent", async (t) => {
  const harness = await openHarness(t);
  const project = path.join(harness.dataDir, "project");
  const id = (await harness.runtime.createAgent({
    name: "Alpha",
    workspace: { projectRoot: project, toolPermission: "always" }
  })).profile.id;
  await harness.send(id, "go");
  const started = harness.kernel.started[0]!;
  assert.notEqual(started.roots.project, project);
  assert.equal(started.roots.project, (await harness.runtime.getAgent(id)).view.settings.workspace!.projectRoot);
  assert.equal(started.roots.scratch, path.join(harness.dataDir, "agents", id, "scratch"));
  assert.equal(started.roots.terminals, path.join(harness.dataDir, "agents", id, "terminals"));
  assert.equal(started.roots.denied.some((item) => item.endsWith("secrets.bin")), true);
  assert.equal(started.toolPermission, "ask");
});

test("deleting an idle agent disposes its persistent shell before removing the directory", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  await harness.runtime.deleteAgent(id);
  assert.deepEqual(harness.kernel.disposedShells, [
    path.join(harness.dataDir, "agents", id, "terminals")
  ]);
});

test("the third concurrent agent queues and starts when a slot frees", async (t) => {
  const harness = await openHarness(t, { maxConcurrentRuns: 2 });
  const ids: string[] = [];
  for (const name of ["A", "B", "C"]) {
    ids.push((await harness.runtime.createAgent({ name })).profile.id);
  }
  const runs = [];
  for (const id of ids) runs.push(await harness.send(id, "go"));

  assert.deepEqual(runs.map((run) => run.queued), [false, false, true]);
  assert.equal(harness.kernel.started.length, 2);
  // 排队中也算忙，否则侧栏会先闪回 idle 再变回来。
  const views = await harness.runtime.listAgents();
  assert.deepEqual(
    new Set(views.filter((view) => view.runtime.status === "running").map((view) => view.profile.id)),
    new Set(ids)
  );

  await harness.emit(
    "turn.ended",
    { runId: runs[0]!.runId, status: "idle" },
    () => harness.kernel.started.length === 3,
    "the queued run to take the freed slot"
  );
  assert.equal(harness.kernel.started[2]!.runId, runs[2]!.runId);
});

test("sending to a busy agent is refused, since one agent has one transcript", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  await harness.send(id, "first");
  await assert.rejects(() => harness.send(id, "second"), /already running/);
});

test("the system prompt is byte-identical within an epoch", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const first = await harness.runtime.buildSystemPrompt(id);
  const second = await harness.runtime.buildSystemPrompt(id);
  assert.equal(first.text, second.text);
  assert.deepEqual(first.notices, []);
  // 段落顺序与本机路径都得真的出现在里面。
  assert.ok(first.text.startsWith("You are Nuum"));
  assert.ok(first.text.includes(path.join(harness.runtime.store.agentDir(id), "profile.json")));
});

test("the first turn freezes the derived name, not the placeholder", async (t) => {
  const harness = await openHarness(t);
  // 新 agent 叫 Assistant，第一条消息会把它改成从消息推出来的名字。
  const id = (await harness.runtime.createAgent({})).profile.id;
  const run = await harness.send(id, "trace the flaky login test");

  const sent = harness.kernel.started[0]!.messages[0]!;
  assert.equal(sent.role, "system");
  assert.ok(sent.content.includes("Title: trace the flaky login test"));
  // 冻结发生在改名之后，所以第一轮就不该有飘移说明。
  assert.equal(sent.content.includes("Title: Assistant"), false);
  assert.ok(harness.kernel.started[0]!.messages.at(-1)!.content.startsWith("trace the flaky login test"));
  void run;
});

test("renaming keeps the frozen prefix and tells the model at the tail instead", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const before = await harness.runtime.buildSystemPrompt(id);
  await harness.runtime.updateAgent({ id, name: "Ranger" });

  const after = await harness.runtime.buildSystemPrompt(id);
  // 一次改名不值得作废整个前缀缓存，所以系统段逐字节不动……
  assert.equal(after.text, before.text);
  assert.ok(after.text.includes("Title: Alpha"));
  // ……新身份走尾部说明，模型当轮就知道。
  assert.equal(after.notices.length, 1);
  assert.ok(after.notices[0]!.includes("Current name: Ranger"));

  const assembled = assembleContext({
    transcript: [{ type: "user", id: "u1", seq: 1, createdAt: 1, text: "who are you" }],
    systemPrompt: after.text,
    notices: after.notices
  });
  // 说明并进最后一条 user 消息，而不是自己起一条 —— 连续两条 user 有 provider 不收。
  assert.deepEqual(assembled.map((message) => message.role), ["system", "user"]);
  assert.ok(assembled[1]!.content.startsWith("who are you"));
  assert.ok(assembled[1]!.content.includes("Current name: Ranger"));
});

test("bumping the epoch re-renders the frozen segment and drops the notice", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  await harness.runtime.buildSystemPrompt(id);
  await harness.runtime.updateAgent({ id, name: "Ranger" });
  assert.equal((await harness.runtime.buildSystemPrompt(id)).notices.length, 1);

  // 压缩（第 7 步）与显式记忆写入（第 5 步）走的就是这个入口。
  const epoch = await harness.runtime.store.bumpPromptEpoch(id);
  assert.equal(epoch, 1);
  const fresh = await harness.runtime.buildSystemPrompt(id);
  assert.ok(fresh.text.includes("Title: Ranger"));
  assert.deepEqual(fresh.notices, []);
  assert.equal((await harness.runtime.store.readPromptCache(id)).epoch, 1);
});

test("a corrupt prompt cache falls back to a live render instead of throwing", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  await writeFile(path.join(harness.runtime.store.agentDir(id), "prompt-cache.json"), "{ not json");
  const render = await harness.runtime.buildSystemPrompt(id);
  assert.ok(render.text.includes("Title: Alpha"));
  assert.deepEqual(render.notices, []);
});

test("SendMessage is offered without being asked for, and lands as its own event", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "say hi");
  // 模型必须看得见它 —— 看不见就等于哑巴。
  assert.ok(harness.kernel.started[0]!.delegatedTools.some((tool) => tool.name === "SendMessage"));

  await harness.emit(
    "turn.tool.delegate",
    {
      runId: run.runId,
      toolCallId: "call-1",
      name: "SendMessage",
      arguments: { type: "text", content: "hi there" }
    },
    () => harness.kernel.results.length === 1,
    "SendMessage to be answered"
  );
  const receipt = harness.kernel.results[0]!;
  assert.equal(receipt.ok, true);
  // 回执带消息 id，模型后面能引用自己的气泡。
  assert.match(receipt.output, /^Delivered\. \(id: [0-9a-f-]+\)$/);

  // 工作痕迹（assistant，带 tool_call）先落盘，气泡（message）紧随其后。
  assert.deepEqual(await harness.transcript(id), ["user", "assistant", "message"]);
  const blocks = (await harness.runtime.getAgent(id)).blocks;
  const bubble = blocks.find((block) => block.type === "message");
  assert.ok(bubble && bubble.type === "message" && bubble.payload.type === "text");
  assert.equal((bubble as any).payload.content, "hi there");

  const events = (await harness.runtime.getTranscript(id)).entries;
  const assistant = events.find((event) => event.type === "assistant")!;
  const delivered = events.find((event) => event.type === "message")!;
  assert.equal(delivered.type === "message" && delivered.assistantId, assistant.id);
  assert.equal(delivered.type === "message" && delivered.toolCallId, "call-1");
});

test("a completed SendMessage stays valid on the next user turn", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const first = await harness.send(id, "hi");

  await harness.emit(
    "turn.tool.delegate",
    {
      runId: first.runId,
      toolCallId: "call-1",
      name: "SendMessage",
      arguments: { type: "text", content: "hello" }
    },
    () => harness.kernel.results.length === 1,
    "SendMessage to be delivered"
  );
  await harness.emit(
    "turn.tool.completed",
    { runId: first.runId, toolCallId: "call-1", name: "SendMessage", ok: true, output: "Delivered." },
    () => emitted(harness, "agent.tool.completed").length === 1,
    "SendMessage tool result to be stored"
  );
  await harness.emit(
    "turn.delta",
    { runId: first.runId, messageId: "a2", delta: "private follow-up", part: "text" },
    () => emitted(harness, "agent.message.delta").length === 1,
    "private assistant text"
  );
  await harness.emit(
    "turn.ended",
    { runId: first.runId, status: "idle" },
    () => emitted(harness, "agent.ended").length === 1,
    "first turn to end"
  );

  await harness.send(id, "who are you");
  const messages = harness.kernel.started[1]!.messages;
  assert.deepEqual(messages.map((message) => message.role), [
    "system",
    "user",
    "assistant",
    "tool",
    "assistant",
    "user"
  ]);
  assert.equal(messages.filter((message) => message.role === "tool").length, 1);
  assert.equal(messages.some((message) => message.id.startsWith("missing-tool-")), false);
});

test("a bad SendMessage payload tells the model what to fix", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "go");
  await harness.emit(
    "turn.tool.delegate",
    { runId: run.runId, toolCallId: "call-1", name: "SendMessage", arguments: { type: "text" } },
    () => harness.kernel.results.length === 1,
    "the schema failure to come back"
  );
  const result = harness.kernel.results[0]!;
  assert.equal(result.ok, false);
  // 「参数错了」不够用 —— 得说清哪个字段错了，模型才改得动。
  assert.ok(result.output.includes("SendMessage"));
  assert.ok(result.output.includes("text"));
  // 没落成气泡。
  assert.deepEqual(await harness.transcript(id), ["user", "assistant"]);
});

test("every tool call is recorded, not just the ones that ask for approval", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "read a file");

  // 免审批的 read 直接 started；它的 tool_call 一样必须记进 assistant 事件。
  await harness.emit(
    "turn.tool.started",
    { runId: run.runId, toolCallId: "call-1", name: "read", arguments: { path: "a.txt" } },
    () => emitted(harness, "agent.tool.started").length === 1,
    "the tool to start"
  );
  await harness.emit(
    "turn.tool.completed",
    { runId: run.runId, toolCallId: "call-1", name: "read", ok: true, output: "file body" },
    () => emitted(harness, "agent.tool.completed").length === 1,
    "the tool to finish"
  );
  await harness.emit(
    "turn.ended",
    { runId: run.runId, status: "idle" },
    () => emitted(harness, "agent.ended").length === 1,
    "the turn to end"
  );

  // 顺序也得对：assistant 在它自己的 tool 结果之前。
  assert.deepEqual(await harness.transcript(id), ["user", "assistant", "tool"]);
  const events = (await harness.runtime.getTranscript(id)).entries;
  const assistant = events.find((event) => event.type === "assistant")!;
  assert.deepEqual(
    (assistant as any).parts.map((part: any) => [part.type, part.id]),
    [["tool_call", "call-1"]]
  );

  // 下一轮送给 provider 的每条 tool 消息都有对应的 tool_call。
  const prompt = await harness.runtime.buildSystemPrompt(id);
  const assembled = assembleContext({ transcript: events, systemPrompt: prompt.text });
  const declared = new Set(
    assembled.flatMap((message) => (message.toolCalls ?? []).map((call) => call.id))
  );
  for (const message of assembled) {
    if (message.role === "tool") assert.ok(declared.has(message.toolCallId!), "orphan tool result");
  }
});

test("an approved tool is recorded once, not twice", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "write a file");
  // 需要审批的工具先 pending 再 started，同一个 toolCallId 只该记一次。
  await harness.emit(
    "turn.tool.pending",
    {
      runId: run.runId,
      toolCallId: "call-1",
      name: "write",
      arguments: { path: "a.txt" },
      mutating: true,
      action: "write-file",
      target: path.join(harness.dataDir, "a.txt")
    },
    () => emitted(harness, "agent.tool.pending").length === 1,
    "the approval card"
  );
  await harness.emit(
    "turn.tool.started",
    { runId: run.runId, toolCallId: "call-1", name: "write", arguments: { path: "a.txt" } },
    () => emitted(harness, "agent.tool.started").length === 1,
    "the tool to start"
  );
  const events = (await harness.runtime.getTranscript(id)).entries;
  const calls = events
    .filter((event) => event.type === "assistant")
    .flatMap((event) => (event as any).parts.filter((part: any) => part.type === "tool_call"));
  assert.equal(calls.length, 1);
});

test("an explicit memory write takes effect on the very next turn", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const before = await harness.runtime.buildSystemPrompt(id);
  assert.ok(before.text.includes("not recorded anything"));

  const run = await harness.send(id, "从现在起测试都用 pnpm，记住");
  await harness.emit(
    "turn.tool.delegate",
    {
      runId: run.runId,
      toolCallId: "call-1",
      name: "update_state",
      arguments: { target: "memory", action: "write", fact: "The user runs tests with pnpm", tier: "profile" }
    },
    () => harness.kernel.results.length === 1,
    "the memory write to be answered"
  );
  assert.equal(harness.kernel.results[0]!.ok, true);

  // 显式写入要 bump epoch：用户说「记住」，期待的是下一句就生效，不是等某次压缩。
  assert.equal((await harness.runtime.store.readPromptCache(id)).epoch, 1);
  const after = await harness.runtime.buildSystemPrompt(id);
  assert.ok(after.text.includes("The user runs tests with pnpm"));
});

test("writing the same memory twice does not burn another epoch", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  assert.equal(await harness.runtime.updateState(id, {
    target: "memory",
    action: "write",
    fact: "The user prefers pnpm",
    tier: "profile"
  }), "Recorded to your standing facts.");
  const first = (await harness.runtime.store.readPromptCache(id)).epoch;

  const again = await harness.runtime.updateState(id, {
    target: "memory",
    action: "write",
    fact: "the user prefers pnpm.",
    tier: "profile"
  });
  assert.equal(again, "Already recorded — nothing to do.");
  // 没写成任何东西就不该作废前缀缓存。
  assert.equal((await harness.runtime.store.readPromptCache(id)).epoch, first);
});

test("model cannot change execution settings and personal workspaces are distinct", async (t) => {
  const harness = await openHarness(t);
  const alpha = await harness.runtime.createAgent({ name: "Alpha" });
  const beta = await harness.runtime.createAgent({ name: "Beta" });
  assert.ok(alpha.settings.workspace?.projectRoot);
  assert.notEqual(alpha.settings.workspace?.projectRoot, beta.settings.workspace?.projectRoot);
  // Runtime rejects stale tool payloads as well as the schema rejecting new calls.
  await assert.rejects(harness.runtime.updateState(alpha.profile.id, { target: "settings", action: "set", project_root: "/" } as never), /only.*user/);
});

test("an agent renaming itself announces it and keeps the frozen prefix", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const before = await harness.runtime.buildSystemPrompt(id);

  const said = await harness.runtime.updateState(id, {
    target: "profile",
    action: "set",
    name: "Ranger"
  });
  assert.ok(said.includes("Ranger"));
  // 侧栏立刻改名，时间线上留下公告。
  assert.equal((await harness.runtime.getAgent(id)).view.profile.name, "Ranger");
  const blocks = (await harness.runtime.getAgent(id)).blocks;
  assert.ok(blocks.some((block) => block.type === "notice" && block.text.includes("Ranger")));

  // 自改人格不 bump epoch：系统段不动，当轮靠尾部说明告知。
  const after = await harness.runtime.buildSystemPrompt(id);
  assert.equal(after.text, before.text);
  assert.equal(after.notices.length, 1);
  assert.equal((await harness.runtime.store.readPromptCache(id)).epoch, 0);
});

test("memory extracted in the background does not bump the epoch", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  await harness.runtime.buildSystemPrompt(id);
  harness.kernel.summarizeWith = () => "profile: The user deploys on Fridays";

  const run = await harness.send(id, "we always deploy on Fridays, after the standup meeting");
  await harness.emit(
    "turn.ended",
    { runId: run.runId, status: "idle" },
    () => harness.kernel.summarized.length === 1,
    "the extraction to run"
  );
  await waitFor(
    async () => (await new MemoryStore(harness.runtime.store.memoryDir(id)).all()).length === 1,
    "the fact to land on disk"
  );

  // 抽取到的事实确实落盘了……
  const facts = await new MemoryStore(harness.runtime.store.memoryDir(id)).all();
  assert.deepEqual(facts.map((entry) => entry.fact), ["The user deploys on Fridays"]);
  // ……但这条路径高频且用户无感，不该每轮把前缀缓存打碎。
  assert.equal((await harness.runtime.store.readPromptCache(id)).epoch, 0);
  assert.ok((await harness.runtime.buildSystemPrompt(id)).text.includes("not recorded anything"));
  // 抽取用的是无工具的单发调用，不是又起一个 run。
  assert.equal(harness.kernel.summarized[0]!.systemPrompt.startsWith("You extract durable facts"), true);
  assert.equal(harness.kernel.started.length, 1);
});

test("small talk does not spend a model call on extraction", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "thanks");
  await harness.emit(
    "turn.ended",
    { runId: run.runId, status: "idle" },
    () => emitted(harness, "agent.ended").length === 1,
    "the turn to end"
  );
  await quiet();
  assert.equal(harness.kernel.summarized.length, 0);
});

test("a cancelled turn is not mined for memory", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(id, "we always deploy on Fridays, after the standup meeting");
  await harness.emit(
    "turn.ended",
    { runId: run.runId, status: "cancelled" },
    () => emitted(harness, "agent.ended").length === 1,
    "the turn to end"
  );
  await quiet();
  // 半截的对话抽出来的「事实」不可靠，别记。
  assert.equal(harness.kernel.summarized.length, 0);
});

test("SendToAgent wakes the other agent on its own timeline, not on the sender's", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  const run = await harness.send(alpha, "ask beta to check the logs");

  await harness.emit(
    "turn.tool.delegate",
    {
      runId: run.runId,
      toolCallId: "call-1",
      name: "SendToAgent",
      arguments: { agent_id: beta, message: "check the logs" }
    },
    () => harness.kernel.results.length === 1,
    "the send to be confirmed"
  );
  // fire-and-forget：立刻回投递确认，不等对方跑完。
  assert.deepEqual(harness.kernel.results, [
    { runId: run.runId, toolCallId: "call-1", ok: true, output: "Sent to Beta." }
  ]);

  // wake 写的是**对方的**文件，发送方那边只留 assistant + tool。
  assert.deepEqual(await harness.transcript(beta), ["wake"]);
  assert.equal(harness.kernel.started.length, 2);
  const woken = harness.kernel.started[1]!;
  assert.notEqual(woken.runId, run.runId);
  // 唤醒文本带 [agent …] cue，模型才知道这不是用户说的。
  assert.ok(woken.messages.at(-1)!.content.includes("[agent Alpha"));
  assert.ok(woken.messages.at(-1)!.content.includes("check the logs"));
});

test("a wake for a busy agent queues, and runs when that agent finishes", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  const betaRun = await harness.send(beta, "beta is busy");

  const said = await harness.runtime.sendToAgent(alpha, { agent_id: beta, message: "queued work" });
  assert.ok(said.includes("queued"));
  // wake 事件已经在对方转录里了，队列只负责「什么时候起 run」。
  assert.deepEqual(await harness.transcript(beta), ["user", "wake"]);
  assert.equal(harness.kernel.started.length, 1);

  await harness.emit(
    "turn.ended",
    { runId: betaRun.runId, status: "idle" },
    () => harness.kernel.started.length === 2,
    "the queued wake to start"
  );
  assert.ok(harness.kernel.started[1]!.messages.at(-1)!.content.includes("queued work"));
});

test("a priority wake cancels what the target is doing and takes over", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  const betaRun = await harness.send(beta, "slow job");

  const said = await harness.runtime.sendToAgent(alpha, {
    agent_id: beta,
    message: "drop that",
    priority: true
  });
  assert.ok(said.includes("dropping what it was doing"), said);
  assert.deepEqual(harness.kernel.cancelled, [betaRun.runId]);
  // 槽位要等 Kernel 确认收束才腾出来 —— 抢在那之前起第二个 run，同一个 agent
  // 就有两个 run 同时写同一条转录。
  assert.equal(harness.kernel.started.length, 1);

  await harness.emit(
    "turn.ended",
    { runId: betaRun.runId, status: "cancelled" },
    () => harness.kernel.started.length === 2,
    "the priority wake to take over"
  );
  // 取消后重起一个 run，模型重新看到完整上下文（含这条新指令）。
  assert.ok(harness.kernel.started[1]!.messages.at(-1)!.content.includes("drop that"));
});

test("stopping an agent drops what was queued for it too", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  const betaRun = await harness.send(beta, "busy");
  await harness.runtime.sendToAgent(alpha, { agent_id: beta, message: "queued" });

  const said = await harness.runtime.stopAgent(alpha, { agent_id: beta });
  assert.ok(said.includes("dropped 1"));
  assert.deepEqual(harness.kernel.cancelled, [betaRun.runId]);

  await harness.emit(
    "turn.ended",
    { runId: betaRun.runId, status: "cancelled" },
    () => emitted(harness, "agent.ended").length === 1,
    "the turn to end"
  );
  await quiet();
  // 「停下」不该是「先停这个再接着跑排着的下一个」。
  assert.equal(harness.kernel.started.length, 1);
});

test("stopping an idle agent says so instead of pretending to act", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  assert.ok((await harness.runtime.stopAgent(alpha, { agent_id: beta })).includes("not doing anything"));
  assert.ok((await harness.runtime.stopAgent(alpha, { agent_id: "ghost" })).includes("No agent"));
  assert.ok((await harness.runtime.stopAgent(alpha, { agent_id: alpha })).includes("stop you"));
});

test("hops accumulate down a chain of wakes and the chain is cut off", async (t) => {
  // 并发上限抬高，否则链条第 4 环会先撞上并发排队，测不到 hops。
  const harness = await openHarness(t, { maxConcurrentRuns: 10 });
  const ids: string[] = [];
  for (const name of ["A", "B", "C", "D", "E"]) {
    ids.push((await harness.runtime.createAgent({ name })).profile.id);
  }
  const [a, b, c, d, e] = ids as [string, string, string, string, string];

  // 用户唤醒 A 是 0 手，A → B 是 1、B → C 是 2、C → D 是 3。
  await harness.send(a, "start the chain");
  for (const [from, to, text] of [
    [a, b, "one"],
    [b, c, "two"],
    [c, d, "three"]
  ] as const) {
    const said = await harness.runtime.sendToAgent(from, { agent_id: to, message: text });
    assert.ok(said.startsWith("Sent"), said);
  }

  // D → E 是 4 手，超限。
  const refused = await harness.runtime.sendToAgent(d, { agent_id: e, message: "four" });
  assert.equal(refused.startsWith("Sent"), false, refused);
  assert.ok(/already \d+ agents away/.test(refused), refused);
  // 被拦下的那条不该在对方转录里留痕，也不该起 run。
  assert.deepEqual(await harness.transcript(e), []);
  assert.equal(harness.kernel.started.length, 4);
});

test("a user message resets the hop chain", async (t) => {
  const harness = await openHarness(t, { maxConcurrentRuns: 10 });
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  // 手写一条 3 手深的唤醒，然后用户自己插一句话。
  await harness.runtime.store.appendEvent(alpha, {
    type: "wake",
    id: crypto.randomUUID(),
    source: { kind: "agent", fromId: beta, fromName: "Beta" },
    text: "deep in a chain",
    hops: 3,
    createdAt: Date.now()
  });
  await harness.send(alpha, "never mind, do this instead");
  // 用户直接说话就是 0 手，链子重新开始 —— 否则一条老唤醒会永久废掉这个 agent
  // 的转发能力。
  const said = await harness.runtime.sendToAgent(alpha, { agent_id: beta, message: "fresh" });
  assert.ok(said.startsWith("Sent"), said);
});

test("CreateAgent makes a real teammate and can hand it work at once", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(alpha, "spin up a log watcher");

  await harness.emit(
    "turn.tool.delegate",
    {
      runId: run.runId,
      toolCallId: "call-1",
      name: "CreateAgent",
      arguments: { name: "Watcher", description: "watches logs", first_message: "start watching" }
    },
    () => harness.kernel.results.length === 1,
    "the agent to be created"
  );
  const output = harness.kernel.results[0]!.output;
  assert.ok(output.includes('Created "Watcher"'));
  assert.ok(output.includes("Sent to Watcher"));

  const watcher = (await harness.runtime.listAgents()).find((view) => view.profile.name === "Watcher")!;
  assert.ok(watcher);
  // 建出来就是个真 agent：自己的转录、自己的 run。
  assert.deepEqual(await harness.transcript(watcher.profile.id), ["wake"]);
  assert.equal(harness.kernel.started.length, 2);
});

test("an agent may create one teammate per turn, and is told why not more", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const run = await harness.send(alpha, "build me a team");

  for (const [i, name] of ["First", "Second"].entries()) {
    await harness.emit(
      "turn.tool.delegate",
      {
        runId: run.runId,
        toolCallId: `call-${i}`,
        name: "CreateAgent",
        arguments: { name, description: "x" }
      },
      () => harness.kernel.results.length === i + 1,
      `create ${name}`
    );
  }
  assert.ok(harness.kernel.results[0]!.output.includes('Created "First"'));
  // 免审批是刻意的，所以护栏得硬 —— 而且拒绝要说清原因。
  assert.ok(harness.kernel.results[1]!.output.includes("already created an agent this turn"));
  assert.equal((await harness.runtime.listAgents()).length, 2);
});

test("ReadAgentTranscript shows what the other agent said and did, not its thinking", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  const run = await harness.send(beta, "look into it");
  await harness.emit(
    "turn.delta",
    { runId: run.runId, messageId: "m1", delta: "secret reasoning", part: "thinking" },
    () => emitted(harness, "agent.message.delta").length === 1,
    "the thinking delta"
  );
  await harness.emit(
    "turn.tool.delegate",
    {
      runId: run.runId,
      toolCallId: "call-1",
      name: "SendMessage",
      arguments: { type: "text", text: "found the bug in auth.ts" }
    },
    () => harness.kernel.results.length === 1,
    "the message to be delivered"
  );

  const read = await harness.runtime.readAgentTranscript(alpha, { agent_id: beta });
  assert.ok(read.includes("user: look into it"));
  assert.ok(read.includes("Beta: found the bug in auth.ts"));
  assert.ok(read.includes("still working"));
  // 队友要知道那边说了什么，不需要它的 thinking。
  assert.equal(read.includes("secret reasoning"), false);
});

test("ReadAgentTranscript ignores synthetic repair rows and counts meaningful updates", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  await harness.runtime.store.appendEvent(beta, {
    type: "user",
    id: "u1",
    text: "hello",
    createdAt: 1
  });
  await harness.runtime.store.appendEvent(beta, {
    type: "tool",
    id: "missing-tool-old-call",
    toolCallId: "old-call",
    name: "bash",
    content: "Tool call was interrupted and did not return a result.",
    ok: false,
    createdAt: 2
  });

  const read = await harness.runtime.readAgentTranscript(alpha, { agent_id: beta, limit: 3 });
  assert.match(read, /Last 1 update from "Beta"/);
  assert.match(read, /user: hello/);
  assert.doesNotMatch(read, /interrupted/);
});

test("an unanswered wake is replayed after a restart", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  // 手写一条 wake 但不跑它，模拟「投递后进程就死了」。
  await harness.runtime.store.appendEvent(beta, {
    type: "wake",
    id: crypto.randomUUID(),
    source: { kind: "agent", fromId: alpha, fromName: "Alpha" },
    text: "picked up after the crash",
    hops: 1,
    createdAt: Date.now()
  });
  await harness.runtime.dispose();

  const revived = await reopenHarness(t, harness);
  await waitFor(() => revived.kernel.started.length === 1, "the wake to be replayed");
  assert.ok(revived.kernel.started[0]!.messages.at(-1)!.content.includes("picked up after the crash"));
  // 队列不落盘 —— 恢复的依据只是转录尾部，没有 inbox 文件。
  assert.deepEqual(await revived.transcript(beta), ["wake"]);
});

test("a wake that was already answered is not replayed after a restart", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  await harness.runtime.store.appendEvent(beta, {
    type: "wake",
    id: crypto.randomUUID(),
    source: { kind: "agent", fromId: alpha, fromName: "Alpha" },
    text: "already handled",
    hops: 1,
    createdAt: Date.now()
  });
  await harness.runtime.store.appendEvent(beta, {
    type: "message",
    id: crypto.randomUUID(),
    payload: { type: "text", content: "done" },
    createdAt: Date.now()
  });
  await harness.runtime.dispose();

  const revived = await reopenHarness(t, harness);
  await quiet();
  assert.equal(revived.kernel.started.length, 0);
});

test("the teammate directory reaches the prompt and is stable while the roster is", async (t) => {
  const harness = await openHarness(t);
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta", description: "reads logs" })).profile.id;

  const prompt = await harness.runtime.buildSystemPrompt(alpha);
  assert.ok(prompt.text.includes(`- Beta (id ${beta}) — reads logs`));
  // 自己不在名录里。
  assert.equal(prompt.text.includes(`id ${alpha})`), false);
  assert.ok(prompt.text.includes(`Your own id is ${alpha}`));
  // 名单不变时逐字节相同 —— 它不像时钟那样每轮都变。
  assert.equal((await harness.runtime.buildSystemPrompt(alpha)).text, prompt.text);

  await harness.runtime.createAgent({ name: "Gamma" });
  assert.notEqual((await harness.runtime.buildSystemPrompt(alpha)).text, prompt.text);
});

test("a lone agent is told how to get teammates instead of seeing an empty list", async (t) => {
  const harness = await openHarness(t);
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const prompt = await harness.runtime.buildSystemPrompt(id);
  assert.ok(prompt.text.includes("You are the only agent right now"));
});

test("the user message lands on disk before the run is even scheduled", async (t) => {
  const harness = await openHarness(t, { maxConcurrentRuns: 1 });
  const alpha = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  const beta = (await harness.runtime.createAgent({ name: "Beta" })).profile.id;
  await harness.send(alpha, "first");

  const queued = await harness.send(beta, "second");
  assert.equal(queued.queued, true);
  // 并发满了要等，但消息得立刻出现在时间线上，不能等到轮到它才显示。
  assert.deepEqual(await harness.transcript(beta), ["user"]);
  assert.equal(harness.kernel.started.length, 1);
});

test("an oversized active context is compacted without rewriting transcript history", async (t) => {
  const harness = await openHarness(t, { contextWindowTokens: 12000 });
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  await harness.runtime.store.appendEvent(id, {
    type: "user", id: "old-user", text: "x".repeat(40_000), createdAt: 1
  });
  await harness.runtime.store.appendEvent(id, {
    type: "assistant", id: "old-answer", parts: [{ type: "text", text: "y".repeat(40_000) }], createdAt: 2
  });
  const file = path.join(harness.dataDir, "agents", id, "transcript.jsonl");
  const before = await readFile(file, "utf8");
  harness.kernel.summarizeWith = (params) =>
    params.systemPrompt.startsWith("Summarize the conversation") ? "Goal: keep testing" : "";

  await harness.send(id, "current request");

  const after = await readFile(file, "utf8");
  assert.equal(after.startsWith(before), true);
  const persisted = await harness.runtime.store.readTranscript(id);
  const compact = persisted.find((event) => event.type === "compact");
  assert.ok(compact && compact.tailFromSeq === 3 && compact.throughSeq === 2);
  assert.equal((await harness.runtime.store.readPromptCache(id)).epoch, 1);
  assert.equal(harness.kernel.summarized[0]!.messages.some((message) => message.role === "system"), false);
  const started = harness.kernel.started[0]!.messages;
  assert.equal(started.filter((message) => message.content.startsWith("[previous conversation summary]")).length, 1);
  assert.equal(started.some((message) => message.content.includes("current request")), true);
  assert.equal(started[0]!.content.includes("Earlier conversation was summarized"), true);
});

test("a compaction failure pauses without sending an oversized model request", async (t) => {
  const harness = await openHarness(t, { contextWindowTokens: 100 });
  const id = (await harness.runtime.createAgent({ name: "Alpha" })).profile.id;
  await harness.runtime.store.appendEvent(id, {
    type: "user", id: "old-user", text: "x".repeat(800), createdAt: 1
  });
  await harness.runtime.store.appendEvent(id, {
    type: "assistant", id: "old-answer", parts: [{ type: "text", text: "y".repeat(800) }], createdAt: 2
  });
  harness.kernel.summarizeWith = () => {
    throw new Error("summary unavailable");
  };

  await assert.rejects(harness.send(id, "still run this"), /compaction failed/i);
  assert.equal(harness.kernel.started.length, 0);
  assert.equal(harness.kernel.summarized.length, 2);
  assert.equal((await harness.runtime.store.readTranscript(id)).some((event) => event.type === "compact"), false);
});

test("background compaction preserves events appended while the summary is pending", async (t) => {
  const harness = await openHarness(t, { contextWindowTokens: 20000 });
  const id = (await harness.runtime.createAgent({ name: "Background" })).profile.id;
  await harness.runtime.store.appendEvent(id, { type: "user", id: "old", text: "old task", createdAt: 1 });
  await harness.runtime.store.appendEvent(id, { type: "assistant", id: "old-result", parts: [{ type: "text", text: "old result" }], createdAt: 2 });
  const run = await harness.send(id, "current request must survive");
  const replies: import("@nuum/protocol").TurnContextResult[] = [];
  (harness.kernel as KernelClient).provideContext = async result => { replies.push(result); };
  let release!: (value: SummarizeRunResult) => void;
  harness.kernel.summarize = async () => new Promise(resolve => { release = resolve; });
  harness.kernel.emit("turn.context", { runId: run.runId, requestId: "prepare", usedTokens: 16200 });
  await waitFor(() => replies.length === 1 && !!release, "background started without blocking");
  assert.equal(replies[0]!.messages, undefined);
  await harness.runtime.store.appendEvent(id, { type: "assistant", id: "new-result", parts: [{ type: "text", text: "result produced during summary" }], createdAt: 3 });
  release({ text: "old task summary" });
  harness.kernel.emit("turn.context", { runId: run.runId, requestId: "apply", usedTokens: 17500 });
  await waitFor(() => replies.length === 2, "summary applied");
  assert.ok(replies[1]!.messages?.some(message => message.content.includes("result produced during summary")));
  assert.ok(replies[1]!.messages?.some(message => message.content.includes("current request must survive")));
  assert.equal((await harness.runtime.store.readTranscript(id)).filter(event => event.type === "compact").length, 1);
});

test("a cancelled run cannot commit its late background summary", async (t) => {
  const harness = await openHarness(t, { contextWindowTokens: 20000 });
  const id = (await harness.runtime.createAgent({ name: "Cancel" })).profile.id;
  await harness.runtime.store.appendEvent(id, { type: "user", id: "old", text: "old task", createdAt: 1 });
  await harness.runtime.store.appendEvent(id, { type: "assistant", id: "old-result", parts: [{ type: "text", text: "old result" }], createdAt: 2 });
  const run = await harness.send(id, "current");
  const replies: import("@nuum/protocol").TurnContextResult[] = [];
  (harness.kernel as KernelClient).provideContext = async result => { replies.push(result); };
  let release!: (value: SummarizeRunResult) => void;
  harness.kernel.summarize = async () => new Promise(resolve => { release = resolve; });
  harness.kernel.emit("turn.context", { runId: run.runId, requestId: "prepare", usedTokens: 16200 });
  await waitFor(() => replies.length === 1 && !!release, "summary pending");
  await harness.runtime.cancel(id);
  release({ text: "late summary" });
  await quiet();
  assert.equal((await harness.runtime.store.readTranscript(id)).some(event => event.type === "compact"), false);
});

test("attachment-only sends persist UI metadata and replay image input after restart", async (t) => {
  const h = await openHarness(t);
  await h.runtime.setSettings({ openaiApiKey: "test-key" });
  const agent = await h.runtime.createAgent({ name: "Attachment reader", model: { provider: "openai", model: "gpt-4o" } });
  const id = agent.profile.id;
  const data = "aGVsbG8=";
  await h.runtime.send(id, "", { attachments: [{ name: "sample.png", mimeType: "image/png", data }, { name: "note.txt", mimeType: "text/plain", data: Buffer.from("attachment test content").toString("base64") }] });
  const input = h.kernel.started[0]!.messages.find(message => message.role === "user")!;
  assert.equal(input.images?.[0]?.data, data);
  assert.match(input.content, /attachment test content/);
  const snapshot = await h.runtime.getAgent(id);
  const user = snapshot.blocks.find(block => block.type === "user")!;
  assert.equal(user.type === "user" && user.attachments?.length, 2);
  const transcript = await readFile(h.runtime.store.transcriptFile(id), "utf8");
  assert.equal(transcript.includes(data), false, "base64 must not be persisted in JSONL");
  await h.runtime.dispose();
  const reopened = await openHarness(t, { dataDir: h.dataDir });
  await reopened.runtime.setSettings({ openaiApiKey: "test-key" });
  await reopened.runtime.send(id, "Look again");
  assert.equal(reopened.kernel.started[0]!.messages.find(message => message.id === input.id)?.images?.[0]?.data, data);
});
