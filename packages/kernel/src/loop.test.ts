import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import type { ChatMessage, ToolDefinition, TurnStartParams } from "@nuum/protocol";
import { createSandbox, disposeAllShells } from "@nuum/sandbox";
import { ToolRegistry } from "@nuum/tools";
import { startTurn, type TurnDeps } from "./loop.js";
import type { NormalizedChatRequest, NormalizedChunk } from "./model/types.js";

/** 一个按脚本吐 chunk 的模型：每一轮吐一批，轮数用完就一直吐空文本。 */
function scriptedModel(rounds: NormalizedChunk[][]): {
  deps: TurnDeps;
  requests: NormalizedChatRequest[];
} {
  const requests: NormalizedChatRequest[] = [];
  let round = 0;
  return {
    requests,
    deps: {
      selectModel: () => ({
        apiKey: "k",
        port: {
          streamChat(req: NormalizedChatRequest): AsyncIterable<NormalizedChunk> {
            requests.push({ ...req, messages: [...req.messages] });
            const chunks = rounds[round] ?? [{ type: "text" as const, text: "" }];
            round += 1;
            return (async function* () {
              for (const chunk of chunks) yield chunk;
            })();
          }
        }
      })
    }
  };
}

/** 一个永远吐不完的模型，用来测「流到一半被取消」。 */
function hangingModel(onStream: () => void): TurnDeps {
  return {
    selectModel: () => ({
      apiKey: "k",
      port: {
        streamChat(_req, signal): AsyncIterable<NormalizedChunk> {
          return (async function* () {
            yield { type: "text" as const, text: "partial" };
            onStream();
            await new Promise((resolve, reject) => {
              signal.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
            });
          })();
        }
      }
    })
  };
}

function startParams(overrides: Partial<TurnStartParams> = {}): TurnStartParams {
  const user: ChatMessage = { id: "u1", role: "user", content: "go", seq: 0, createdAt: 1 };
  return {
    runId: "run-1",
    messages: [user],
    model: { provider: "deepseek", model: "deepseek-chat" },
    roots: {
      home: "/tmp",
      project: null,
      scratch: "/tmp/nuum-loop/agents/a1/scratch",
      terminals: "/tmp/nuum-loop/agents/a1/terminals",
      denied: []
    },
    toolPermission: "always",
    approvals: [],
    refused: [],
    localToolNames: [],
    delegatedTools: [],
    voiceToolNames: ["SendMessage"],
    secrets: { deepseekApiKey: "k" },
    ...overrides
  };
}

const sendMessage: ToolDefinition = {
  name: "send_message",
  description: "post a message",
  inputSchema: { type: "object", properties: { text: { type: "string" } } },
  mutating: false
};

function collector(): { events: { method: string; params: any }[]; emit: (m: string, p: unknown) => void } {
  const events: { method: string; params: any }[] = [];
  return { events, emit: (method, params) => events.push({ method, params: params as any }) };
}

function waitFor(predicate: () => boolean, what: string): Promise<void> {
  return (async () => {
    const deadline = Date.now() + 3_000;
    while (Date.now() < deadline) {
      if (predicate()) return;
      await new Promise((resolve) => setTimeout(resolve, 2));
    }
    assert.fail(`timed out waiting for ${what}`);
  })();
}

test("a delegated tool is offered to the model and its result feeds the next round", async () => {
  const { deps, requests } = scriptedModel([
    [{ type: "tool_call", id: "c1", name: "send_message", arguments: { text: "hi" } }],
    [{ type: "text", text: "done" }]
  ]);
  const { events, emit } = collector();
  const handle = startTurn(
    startParams({ delegatedTools: [sendMessage] }),
    emit,
    new ToolRegistry([]),
    deps
  );

  await waitFor(
    () => events.some((event) => event.method === "turn.tool.delegate"),
    "the delegate request"
  );
  // 委派工具必须出现在模型的工具表里，否则模型永远不会调它。
  assert.deepEqual(requests[0]!.tools.map((tool) => tool.name), ["send_message"]);
  const delegate = events.find((event) => event.method === "turn.tool.delegate")!.params;
  assert.deepEqual(delegate, { runId: "run-1", toolCallId: "c1", name: "send_message", arguments: { text: "hi" } });
  // 委派期间不该有本地执行的痕迹。
  assert.equal(events.some((event) => event.method === "turn.tool.started"), false);

  handle.provideToolResult("c1", true, "delivered");
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the turn to end");

  const completed = events.find((event) => event.method === "turn.tool.completed")!.params;
  assert.deepEqual(completed, {
    runId: "run-1",
    toolCallId: "c1",
    name: "send_message",
    ok: true,
    output: "delivered"
  });
  // Host 回的结果得作为 tool 消息进下一轮上下文。
  const second = requests[1]!.messages;
  assert.equal(second.at(-1)!.role, "tool");
  assert.equal(second.at(-1)!.content, "delivered");
  assert.equal(events.at(-1)!.params.status, "idle");
});

test("a failed delegation reaches the model as a failed tool result, not as a turn error", async () => {
  const { deps, requests } = scriptedModel([
    [{ type: "tool_call", id: "c1", name: "send_message", arguments: {} }],
    [{ type: "text", text: "ok, noted" }]
  ]);
  const { events, emit } = collector();
  const handle = startTurn(startParams({ delegatedTools: [sendMessage] }), emit, new ToolRegistry([]), deps);

  await waitFor(() => events.some((event) => event.method === "turn.tool.delegate"), "the delegate request");
  handle.provideToolResult("c1", false, "target agent not found");
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the turn to end");

  assert.equal(events.some((event) => event.method === "turn.error"), false);
  assert.equal(events.find((event) => event.method === "turn.tool.completed")!.params.ok, false);
  assert.equal(requests[1]!.messages.at(-1)!.content, "target agent not found");
});

test("a local image result reaches the next model round without entering the persisted tool output", async () => {
  const registry = new ToolRegistry([{
    definition: {
      name: "read",
      description: "read an image",
      inputSchema: { type: "object", properties: { path: { type: "string" } } },
      mutating: false,
      action: "read-file"
    },
    execute: async () => ({
      text: "Read image file: /tmp/pixel.png",
      images: [{ mimeType: "image/png", data: "aGVsbG8=" }]
    })
  }]);
  const { deps, requests } = scriptedModel([
    [{ type: "tool_call", id: "c-image", name: "read", arguments: { path: "/tmp/pixel.png" } }],
    [{ type: "text", text: "I can see it" }]
  ]);
  const { events, emit } = collector();
  startTurn(startParams({ localToolNames: ["read"] }), emit, registry, deps);
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the image turn to end");

  const second = requests[1]!.messages;
  assert.equal(second.at(-2)!.role, "tool");
  assert.equal(second.at(-2)!.content, "Read image file: /tmp/pixel.png");
  assert.equal(second.at(-1)!.role, "user");
  assert.deepEqual(second.at(-1)!.images, [{ mimeType: "image/png", data: "aGVsbG8=" }]);
  assert.equal(events.find((event) => event.method === "turn.tool.completed")!.params.output,
    "Read image file: /tmp/pixel.png");
});

test("shell_id inspection is a pre-approved read of this agent's terminal file", async () => {
  const shellId = "00000000-0000-4000-8000-000000000001";
  const executed: string[] = [];
  const registry = new ToolRegistry([{
    definition: {
      name: "shell",
      description: "inspect a shell",
      inputSchema: { type: "object", properties: { shell_id: { type: "string" } } },
      mutating: true,
      action: "run-command"
    },
    execute: async () => {
      executed.push(shellId);
      return "inspected";
    }
  }]);
  const { deps } = scriptedModel([
    [{ type: "tool_call", id: "c-shell", name: "shell", arguments: { shell_id: shellId } }],
    [{ type: "text", text: "done" }]
  ]);
  const { events, emit } = collector();
  startTurn(startParams({ localToolNames: ["shell"], toolPermission: "never" }), emit, registry, deps);
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "shell inspection to end");
  assert.deepEqual(executed, [shellId]);
  assert.equal(events.some((event) => event.method === "turn.tool.pending"), false);
  assert.equal(events.find((event) => event.method === "turn.tool.started")!.params.name, "shell");
});

test("turn cancellation disposes the agent's persistent shell", async (t) => {
  const home = await mkdtemp(path.join(tmpdir(), "nuum-kernel-shell-"));
  const project = path.join(home, "project");
  const agent = path.join(home, "agents", "a1");
  const scratch = path.join(agent, "scratch");
  const terminals = path.join(agent, "terminals");
  await Promise.all([mkdir(project, { recursive: true }), mkdir(scratch, { recursive: true })]);
  const roots = { home, project, scratch, terminals, denied: [] };
  const sandbox = createSandbox({ roots, permission: "always" });
  t.after(() => disposeAllShells());
  const job = await sandbox.shell({ command: "sleep 30", blockUntilMs: 0 });
  assert.equal(job.background, true);

  const { events, emit } = collector();
  let streaming = false;
  const handle = startTurn(startParams({ roots }), emit, new ToolRegistry([]), hangingModel(() => {
    streaming = true;
  }));
  await waitFor(() => streaming, "the model stream to open");
  handle.cancel();
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the cancelled turn to end");
  for (let i = 0; i < 100; i += 1) {
    const content = await readFile(job.path, "utf8");
    if (/exit_code: 130/.test(content)) return;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.fail("persistent shell output was not sealed after turn cancellation");
});

test("cancelling while a tool waits for approval ends as cancelled, not as an error", async () => {
  const executed: string[] = [];
  const registry = new ToolRegistry([
    {
      definition: {
        name: "write",
        description: "w",
        inputSchema: { type: "object", properties: { path: { type: "string" } } },
        mutating: true,
        action: "write-file"
      },
      execute: async () => {
        executed.push("write");
        return "written";
      }
    }
  ]);
  const { deps } = scriptedModel([[
    { type: "tool_call", id: "c1", name: "write", arguments: { path: "/tmp/needs-approval.txt" } }
  ]]);
  const { events, emit } = collector();
  const handle = startTurn(startParams({ localToolNames: ["write"], toolPermission: "ask" }), emit, registry, deps);

  await waitFor(() => events.some((event) => event.method === "turn.tool.pending"), "the approval request");
  handle.cancel();
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the turn to end");

  // 之前这里会走成 turn.error(CANCELLED) + turn.ended(error)，UI 分不清被掐和出错。
  assert.equal(events.some((event) => event.method === "turn.error"), false);
  assert.equal(events.at(-1)!.params.status, "cancelled");
  assert.deepEqual(executed, []);
});

test("cancelling while a delegated tool is out ends as cancelled", async () => {
  const { deps } = scriptedModel([[{ type: "tool_call", id: "c1", name: "send_message", arguments: {} }]]);
  const { events, emit } = collector();
  const handle = startTurn(startParams({ delegatedTools: [sendMessage] }), emit, new ToolRegistry([]), deps);

  await waitFor(() => events.some((event) => event.method === "turn.tool.delegate"), "the delegate request");
  handle.cancel();
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the turn to end");
  assert.equal(events.at(-1)!.params.status, "cancelled");
  assert.equal(events.some((event) => event.method === "turn.error"), false);
});

test("cancelling mid-stream ends as cancelled", async () => {
  const { events, emit } = collector();
  let streaming = false;
  const handle = startTurn(startParams(), emit, new ToolRegistry([]), hangingModel(() => {
    streaming = true;
  }));

  await waitFor(() => streaming, "the stream to open");
  handle.cancel();
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the turn to end");
  assert.equal(events.at(-1)!.params.status, "cancelled");
  assert.equal(events.some((event) => event.method === "turn.error"), false);
});

test("every event of a turn is keyed by its runId", async () => {
  const { deps } = scriptedModel([[{ type: "thinking", text: "hm" }, { type: "text", text: "hi" }]]);
  const { events, emit } = collector();
  startTurn(startParams({ runId: "run-xyz" }), emit, new ToolRegistry([]), deps);
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the turn to end");
  for (const event of events) {
    assert.equal(event.params.runId, "run-xyz", `${event.method} must carry runId`);
    assert.equal("sessionId" in event.params, false, `${event.method} must not carry sessionId`);
  }
});

test("running out of tool rounds says so instead of ending silently", async () => {
  // 每一轮都只吐工具调用，永远不给最终文本。
  const rounds = Array.from({ length: 20 }, (_, i) => [
    { type: "tool_call" as const, id: `c${i}`, name: "send_message", arguments: {} }
  ]);
  const { deps } = scriptedModel(rounds);
  const { events, emit } = collector();
  const handle = startTurn(startParams({ delegatedTools: [sendMessage] }), emit, new ToolRegistry([]), deps);

  // 每次有新的委派请求就立刻放行，直到 loop 自己撞上轮次上限收束。
  let answered = 0;
  while (!events.some((event) => event.method === "turn.ended")) {
    const delegated = events.filter((event) => event.method === "turn.tool.delegate");
    if (delegated.length > answered) {
      handle.provideToolResult(delegated[answered]!.params.toolCallId, true, "ok");
      answered += 1;
    }
    await new Promise((resolve) => setImmediate(resolve));
    assert.ok(answered <= 16, "the round limit must stop the loop");
  }
  const notice = events.filter((event) => event.method === "turn.delta").at(-1)!.params;
  assert.match(notice.delta, /Stopped after 16 tool rounds/);
  assert.equal(events.at(-1)!.params.status, "idle");
});

test("an unknown tool fails the turn with an error, not a silent stall", async () => {
  const { deps } = scriptedModel([[{ type: "tool_call", id: "c1", name: "ghost", arguments: {} }]]);
  const { events, emit } = collector();
  startTurn(startParams(), emit, new ToolRegistry([]), deps);
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the turn to end");
  assert.match(events.find((event) => event.method === "turn.error")!.params.message, /Unknown tool: ghost/);
  assert.equal(events.at(-1)!.params.status, "error");
});

// ── turn 循环的节奏提醒（ack / result / silence）─────────────────────────────

function stepRegistry(): ToolRegistry {
  return new ToolRegistry([{
    definition: {
      name: "step",
      description: "one unit of silent work",
      inputSchema: { type: "object", properties: {} },
      mutating: false,
      action: "read-file"
    },
    execute: async () => "ok"
  }]);
}

function reminders(request: NormalizedChatRequest | undefined): { kind: string }[] {
  return (request?.messages ?? [])
    .filter((message) => typeof message.id === "string" && message.id.startsWith("reminder-"))
    .map((message) => ({ kind: (message.id as string).split("-")[1]! }));
}

test("turns that open with tools get one ack reminder, and silence gets one after the long streak", async () => {
  const rounds: NormalizedChunk[][] = Array.from({ length: 7 }, (_, i) => [
    { type: "tool_call" as const, id: `c${i}`, name: "step", arguments: {} }
  ]);
  rounds.push([{ type: "text" as const, text: "done" }]);
  const { deps, requests } = scriptedModel(rounds);
  const { events, emit } = collector();
  startTurn(startParams({ localToolNames: ["step"] }), emit, stepRegistry(), deps);
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the turn to end");

  // 提醒一旦注入就留在后续每轮的上下文里，所以按「首次出现」断言。
  const firstOf = (kind: string): number =>
    requests.findIndex((request) => reminders(request).some((r) => r.kind === kind));
  assert.equal(firstOf("ack"), 2, "ack fires once the silent count passes 2");
  assert.equal(firstOf("silence"), 7, "silence fires once the silent count passes 6");
  // 每种整段只发一次。
  const last = reminders(requests.at(-1));
  assert.deepEqual(last.filter((r) => r.kind === "ack").length, 1);
  assert.deepEqual(last.filter((r) => r.kind === "silence").length, 1);
  assert.equal(requests.length, 8);
});

test("a voice call resets the streak: result reminder replaces further acks", async () => {
  const { deps, requests } = scriptedModel([
    [
      { type: "tool_call", id: "c1", name: "step", arguments: {} },
      { type: "tool_call", id: "c2", name: "step", arguments: {} }
    ],
    [{ type: "tool_call", id: "c3", name: "send_message", arguments: {} }],
    [
      { type: "tool_call", id: "c4", name: "step", arguments: {} },
      { type: "tool_call", id: "c5", name: "step", arguments: {} }
    ],
    [{ type: "text", text: "done" }]
  ]);
  const { events, emit } = collector();
  const handle = startTurn(
    startParams({ localToolNames: ["step"], delegatedTools: [sendMessage], voiceToolNames: ["send_message"] }),
    emit,
    stepRegistry(),
    deps
  );
  await waitFor(() => events.some((event) => event.method === "turn.tool.delegate"), "the delegate request");
  handle.provideToolResult("c3", true, "delivered");
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the turn to end");

  const firstOf = (kind: string): number =>
    requests.findIndex((request) => reminders(request).some((r) => r.kind === kind));
  assert.equal(firstOf("ack"), 1);
  // 发声重置了计数与段标记：第三轮请求里没有新提醒出现。
  assert.deepEqual(reminders(requests[2]), reminders(requests[1]));
  // 再次埋头后，result 提醒接棒（用户看不见工具输出）。
  assert.equal(firstOf("result"), 3);
  const last = reminders(requests.at(-1));
  assert.deepEqual(last.filter((r) => r.kind === "ack").length, 1);
  assert.deepEqual(last.filter((r) => r.kind === "result").length, 1);
  assert.equal(requests.length, 4);
});

test("voiceToolNames follows the run: work-run voice tools suppress the ack reminder", async () => {
  const { deps, requests } = scriptedModel([
    [
      { type: "tool_call", id: "c1", name: "send_message", arguments: {} },
      { type: "tool_call", id: "c2", name: "send_message", arguments: {} }
    ],
    [{ type: "text", text: "done" }]
  ]);
  const { events, emit } = collector();
  const handle = startTurn(
    startParams({ delegatedTools: [sendMessage], voiceToolNames: ["send_message"] }),
    emit,
    new ToolRegistry([]),
    deps
  );
  for (const id of ["c1", "c2"]) {
    await waitFor(() => events.filter((event) => event.method === "turn.tool.delegate").length >= (id === "c1" ? 1 : 2), `delegate ${id}`);
    handle.provideToolResult(id, true, "delivered");
  }
  await waitFor(() => events.some((event) => event.method === "turn.ended"), "the turn to end");
  for (const request of requests) assert.deepEqual(reminders(request), []);
});

test("a successful handoff can end the turn before another tool or model call", async () => {
  const { deps, requests } = scriptedModel([[{ type: "tool_call", id: "handoff", name: "send_message", arguments: {} }, { type: "tool_call", id: "later", name: "send_message", arguments: {} }]]);
  const { events, emit } = collector();
  const handle = startTurn(startParams({ delegatedTools: [sendMessage] }), emit, new ToolRegistry([]), deps);
  await waitFor(() => events.some(event => event.method === "turn.tool.delegate"), "handoff");
  handle.provideToolResult("handoff", true, "returned to owner", true);
  await waitFor(() => events.some(event => event.method === "turn.ended"), "turn end");
  assert.equal(requests.length, 1);
  assert.equal(events.filter(event => event.method === "turn.tool.delegate").length, 1);
  assert.equal(events.at(-1)!.params.status, "idle");
});

test("every model round waits for Host context and accepts a compacted replacement", async () => {
  const model = scriptedModel([[{ type: "tool_call", id: "c", name: "send_message", arguments: {} }], [{ type: "text", text: "done" }]]);
  const log = collector();
  const handle = startTurn(startParams({ contextWindow: 10000, delegatedTools: [sendMessage], messages: [{ id: "uploaded-image", role: "user", content: "Look at this", images: [{ mimeType: "image/png", data: "aGVsbG8=" }], seq: 1, createdAt: 0 }] }), log.emit, new ToolRegistry(), model.deps);
  await waitFor(() => log.events.some(e => e.method === "turn.context"), "first context check");
  assert.equal(model.requests.length, 0);
  handle.provideContext(log.events.find(e => e.method === "turn.context")!.params.requestId);
  await waitFor(() => log.events.some(e => e.method === "turn.tool.delegate"), "tool");
  handle.provideToolResult("c", true, "delivered");
  await waitFor(() => log.events.filter(e => e.method === "turn.context").length === 2, "next context check");
  handle.provideContext(log.events.filter(e => e.method === "turn.context")[1]!.params.requestId, [{ id: "summary", role: "user", seq: 1, createdAt: 0, content: "compacted history" }]);
  await waitFor(() => log.events.some(e => e.method === "turn.ended"), "completion");
  assert.equal(model.requests.length, 2);
  assert.ok(model.requests[1]!.messages.some(m => m.id === "summary"));
  assert.equal(model.requests[1]!.messages.some(m => m.id === "uploaded-image"), false, "Host-owned image history must not return after compaction");
  assert.equal(model.requests[1]!.messages.some(m => m.toolCalls?.length), false);
});

test("context failure and cancellation never start another model request", async () => {
  for (const cancel of [false, true]) {
    const model = scriptedModel([]);
    const log = collector();
    const handle = startTurn(startParams({ contextWindow: 10000 }), log.emit, new ToolRegistry(), model.deps);
    await waitFor(() => log.events.some(e => e.method === "turn.context"), "context wait");
    if (cancel) handle.cancel();
    else handle.provideContext(log.events[0]!.params.requestId, undefined, "Compaction failed");
    await waitFor(() => log.events.some(e => e.method === "turn.ended"), "ended");
    assert.equal(model.requests.length, 0);
  }
});
