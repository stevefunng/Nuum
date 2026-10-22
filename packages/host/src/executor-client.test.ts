import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdir, mkdtemp, readFile, realpath, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { executionRpc } from "@nuum/protocol/node";
import type { ExecutionContext, ExecutionEndpoint, ExecutionResult } from "@nuum/protocol";
import { ExecutorClient } from "./executor-client.js";

const entry = path.resolve(import.meta.dirname, "../../executor/dist/main.js");
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
async function finished(endpoint: ExecutionEndpoint, id: string): Promise<Extract<ExecutionResult, { state: "finished" }>> {
  for (let attempt = 0; attempt < 200; attempt++) {
    const result = await executionRpc<ExecutionResult>(endpoint, "status", { id });
    if (result.state === "finished") return result;
    await delay(50);
  }
  throw new Error("Execution did not settle");
}

test("daemon authenticates contexts, adopts active work after supervisor detaches, and never replays a request", { skip: process.platform !== "darwin", timeout: 30_000 }, async () => {
  const base = await realpath(await mkdtemp(path.join(os.tmpdir(), "nuum-daemon-")));
  const root = path.join(base, "work"); await mkdir(root);
  let client = new ExecutorClient(base, entry);
  try {
    const original = await client.start();
    const context: ExecutionContext = { id: "ctx", agentId: "a", workspaceId: "w", root, commands: "ask", network: [], approvedCommands: [], tools: ["shell", "read", "request_network"], readOnly: [] };
    const endpoint = await client.register(context);
    await rm(path.join(base, "executor", "discovery.json"));
    const duplicate = new ExecutorClient(base, entry);
    await assert.rejects(duplicate.start(), /socket.*active|active.*socket/i);
    // Restore discovery as the daemon normally publishes it, so adoption can be tested next.
    const { writeFile } = await import("node:fs/promises");
    await writeFile(path.join(base, "executor", "discovery.json"), JSON.stringify({ socket: endpoint.socket, instance: original.instance, pid: original.pid }), { mode: 0o600 });
    await assert.rejects(executionRpc(endpoint, "register", context), /Only Host/);
    const request = { id: "command", contextId: context.id, name: "shell", input: { command: "sleep 1; echo once >> count.txt", block_until_ms: 2000 } };
    const pending = await executionRpc<ExecutionResult>(endpoint, "submit", request);
    assert.equal(pending.state, "running");
    await assert.rejects(executionRpc(endpoint, "decide", { id: request.id, allow: true }), /Only Host/);
    client.detach();
    client = new ExecutorClient(base, entry);
    const adopted = await client.start();
    assert.equal(adopted.instance, original.instance);
    assert.equal((await finished(endpoint, request.id)).ok, true);
    assert.equal((await executionRpc<ExecutionResult>(endpoint, "submit", request)).state, "finished");
    assert.equal(await readFile(path.join(root, "count.txt"), "utf8"), "once\n");
    await assert.rejects(executionRpc(endpoint, "submit", { ...request, input: { command: "echo twice" } }), /different/);
    const other = await client.register({ ...context, id: "other", agentId: "b" });
    await assert.rejects(executionRpc(other, "status", { id: request.id }), /not authorized/);
    await client.rpc("revoke", { contextId: context.id });
    await assert.rejects(executionRpc(endpoint, "submit", { ...request, id: "new" }), /not authorized/);
  } finally { await client.stop(); await rm(base, { recursive: true, force: true }); }
});

test("Host persists a workspace-scoped network grant and revocation invalidates old execution authority", { skip: process.platform !== "darwin", timeout: 30_000 }, async () => {
  const { HostRuntime } = await import("./runtime.js");
  const base = await realpath(await mkdtemp(path.join(os.tmpdir(), "nuum-host-exec-")));
  let started: import("@nuum/protocol").TurnStartParams | undefined;
  let emit: (method: string, params: unknown) => void = () => {};
  let pending = false;
  const host = new HostRuntime({ dataDir: base, kernelCommand: "unused", kernelArgs: [], executorEntry: entry,
    spawnKernel: () => ({
      hello: async () => ({ name: "nuum-kernel", version: "0.1.0" }), start: async params => { started = params; },
      cancel: async () => {}, decide: async () => {}, provideToolResult: async () => {}, disposeShell: async () => {},
      summarize: async () => ({ text: "" }), tools: async () => [{ name: "request_network", description: "network", inputSchema: {}, mutating: false, action: "network" }],
      onEvent: handler => { emit = handler; }, dispose: () => {}
    }) });
  try {
    await host.start();
    host.setEmitter(method => { if (method === "agent.tool.pending") pending = true; });
    await host.setSettings({ deepseekApiKey: "test-only" });
    const agent = await host.createAgent({ name: "Network test" });
    await host.send(agent.profile.id, "test network approval");
    assert.ok(started?.execution);
    const endpoint = started.execution;
    const request = { id: `${started.runId}:net`, contextId: endpoint.contextId, name: "request_network", input: { target: "example.com:443" } };
    assert.equal((await executionRpc<ExecutionResult>(endpoint, "submit", request)).state, "approval");
    emit("turn.tool.pending", { runId: started.runId, toolCallId: "net", name: "request_network", arguments: request.input, mutating: false, action: "network", target: "example.com:443" });
    for (let i = 0; i < 100 && !pending; i++) await delay(10);
    assert.ok(pending);
    await host.decide(agent.profile.id, "net", "always");
    assert.equal((await finished(endpoint, request.id)).ok, true);
    const current = (await host.getAgent(agent.profile.id)).view;
    assert.deepEqual(current.settings.execution!.networkGrants, [{ workspaceId: current.settings.execution!.workspaceId, target: "example.com:443" }]);
    await host.updateAgent({ id: agent.profile.id, execution: { ...current.settings.execution!, networkGrants: [] } });
    await assert.rejects(executionRpc(endpoint, "submit", { ...request, id: "new" }), /not authorized/);
    const saved = JSON.parse(await readFile(path.join(base, "agents", agent.profile.id, "settings.json"), "utf8"));
    assert.deepEqual(saved.execution.networkGrants, []);
  } finally { await host.dispose(); await rm(base, { recursive: true, force: true }); }
});

test("daemon crash cleans its shell group, restarts with a new identity and does not replay work", { skip: process.platform !== "darwin", timeout: 30_000 }, async () => {
  const base = await realpath(await mkdtemp(path.join(os.tmpdir(), "nuum-daemon-crash-")));
  const root = path.join(base, "work"); await mkdir(root);
  const client = new ExecutorClient(base, entry);
  try {
    const original = await client.start();
    const endpoint = await client.register({ id: "crash", agentId: "a", workspaceId: "w", root, commands: "always", network: [], approvedCommands: [], tools: ["shell"], readOnly: [] });
    await executionRpc(endpoint, "submit", { id: "crash-command", contextId: "crash", name: "shell",
      input: { command: "echo once >> count.txt; sleep 60 & echo $! > child.pid; wait", block_until_ms: 1000 } });
    let childPid = 0;
    for (let i = 0; i < 200 && !childPid; i++) {
      childPid = Number(await readFile(path.join(root, "child.pid"), "utf8").catch(() => "0"));
      if (!childPid) await delay(50);
    }
    assert.ok(childPid);
    process.kill(original.pid, "SIGKILL");
    let next: { instance: string } | undefined;
    for (let i = 0; i < 200; i++) {
      next = await client.rpc<{ instance: string }>("hello").catch(() => undefined);
      if (next && next.instance !== original.instance) break;
      await delay(50);
    }
    assert.ok(next && next.instance !== original.instance);
    for (let i = 0; i < 100; i++) {
      try { process.kill(childPid, 0); } catch { break; }
      await delay(50);
    }
    assert.throws(() => process.kill(childPid, 0), { code: "ESRCH" });
    await assert.rejects(executionRpc(endpoint, "status", { id: "crash-command" }), /generation changed/);
    assert.equal(await readFile(path.join(root, "count.txt"), "utf8"), "once\n");
  } finally { await client.stop(); await rm(base, { recursive: true, force: true }); }
});

test("Host adoption recovers finished output to its original transcript and stops stale authorization", { skip: process.platform !== "darwin", timeout: 40_000 }, async () => {
  const { HostRuntime } = await import("./runtime.js");
  const { executionPolicy } = await import("./execution-recovery.js");
  const { SessionStore } = await import("./session-store.js");
  const base = await realpath(await mkdtemp(path.join(os.tmpdir(), "nuum-recover-")));
  const spawnKernel = (): any => ({ hello: async () => ({}), tools: async () => [], onEvent: () => {}, dispose: () => {} });
  const seed = new HostRuntime({ dataDir: base, kernelCommand: "unused", kernelArgs: [], spawnKernel });
  await seed.start();
  const agent = await seed.createAgent({ name: "Recovery" });
  await seed.dispose();
  const client = new ExecutorClient(base, entry);
  let host: InstanceType<typeof HostRuntime> | undefined;
  try {
    await client.start();
    const preferences = agent.settings.execution!;
    const context: ExecutionContext = { id: "recovered", agentId: agent.profile.id, workspaceId: preferences.workspaceId, root: agent.settings.workspace!.projectRoot!, commands: "always", approvedCommands: [], network: [], tools: ["shell"], readOnly: [], policy: executionPolicy(preferences), origin: { runId: "lost-run" } };
    const endpoint = await client.register(context);
    await executionRpc(endpoint, "submit", { id: "lost-run:done", contextId: context.id, name: "shell", input: { command: "echo recovered-output", block_until_ms: 1000 } });
    assert.equal((await finished(endpoint, "lost-run:done")).ok, true);
    const sessions = new SessionStore(base);
    const session = await sessions.ensure("former-room", "card", agent.profile.id, 1);
    const cardEndpoint = await client.register({ ...context, id: "card-context",
      origin: { runId: "card-run", workId: session.workId, session } });
    await executionRpc(cardEndpoint, "submit", { id: "card-run:card-tool", contextId: "card-context", name: "shell",
      input: { command: "echo card-only-output", block_until_ms: 1000 } });
    await finished(cardEndpoint, "card-run:card-tool");
    // A completed but unacknowledged result must prevent idle replacement too.
    const stale = await client.register({ ...context, id: "stale", policy: "old-policy", origin: { runId: "stale-run" } });
    await executionRpc(stale, "submit", { id: "stale-run:stop", contextId: "stale", name: "shell", input: { command: "sleep 5; echo forbidden > stale.txt", block_until_ms: 10_000 } });
    client.detach();
    host = new HostRuntime({ dataDir: base, kernelCommand: "unused", kernelArgs: [], executorEntry: entry, spawnKernel });
    await host.start();
    let transcript = "";
    for (let i = 0; i < 200; i++) {
      transcript = await readFile(path.join(base, "agents", agent.profile.id, "transcript.jsonl"), "utf8").catch(() => "");
      if (transcript.includes('"toolCallId":"done"') && transcript.includes('"toolCallId":"stop"')) break;
      await delay(50);
    }
    const events = transcript.trim().split("\n").map(line => JSON.parse(line));
    assert.equal(events.filter(event => event.type === "tool" && event.toolCallId === "done").length, 1);
    assert.match(events.find(event => event.type === "tool" && event.toolCallId === "done").content, /recovered-output/);
    assert.equal(events.find(event => event.type === "tool" && event.toolCallId === "stop")?.ok, false);
    const cardEvents = await sessions.read(session);
    assert.equal(cardEvents.filter(event => event.type === "tool" && event.toolCallId === "card-tool").length, 1);
    assert.ok(!transcript.includes("card-only-output"), "Card result must not leak into the private session");
    await assert.rejects(readFile(path.join(context.root, "stale.txt")), { code: "ENOENT" });
    await assert.rejects(executionRpc(stale, "submit", { id: "stale-run:new", contextId: "stale", name: "shell", input: { command: "echo no" } }), /not authorized/);
  } finally { if (host) await host.dispose(); else await client.stop(); await rm(base, { recursive: true, force: true }); }
});

test("Host persists external permission per Nunu and revokes the live execution authority", { skip: process.platform !== "darwin", timeout: 30_000 }, async () => {
  const { HostRuntime } = await import("./runtime.js");
  const base = await realpath(await mkdtemp(path.join(process.cwd(), ".permission-host-")));
  const { writeFile } = await import("node:fs/promises");
  const externalFile = path.join(base, "external.txt");
  await writeFile(externalFile, "authorized content");
  let started: import("@nuum/protocol").TurnStartParams | undefined;
  let emit: (method: string, params: unknown) => void = () => {};
  let pending = false;
  const host = new HostRuntime({ dataDir: path.join(base, "private"), documentsDir: path.join(base, "Documents"), kernelCommand: "unused", kernelArgs: [], executorEntry: entry,
    spawnKernel: () => ({
      hello: async () => ({ name: "nuum-kernel", version: "0.1.0" }), start: async params => { started = params; },
      cancel: async () => {}, decide: async () => {}, provideToolResult: async () => {}, disposeShell: async () => {},
      summarize: async () => ({ text: "" }), tools: async () => [{ name: "external_operation", description: "external", inputSchema: {}, mutating: false, action: "network" }],
      onEvent: handler => { emit = handler; }, dispose: () => {}
    }) });
  try {
    await host.start();
    host.setEmitter(method => { if (method === "agent.tool.pending") pending = true; });
    await host.setSettings({ deepseekApiKey: "test-only" });
    const agent = await host.createAgent({ name: "Network test" });
    await host.send(agent.profile.id, "test network approval");
    assert.ok(started?.execution);
    const endpoint = started.execution;
    const request = { id: `${started.runId}:net`, contextId: endpoint.contextId, name: "external_operation", input: { operation: "read", source: externalFile, justification: "Read this file for the task" } };
    assert.equal((await executionRpc<ExecutionResult>(endpoint, "submit", request)).state, "approval");
    emit("turn.tool.pending", { runId: started.runId, toolCallId: "net", name: "external_operation", arguments: request.input, mutating: false, action: "read-file", target: externalFile });
    for (let i = 0; i < 100 && !pending; i++) await delay(10);
    assert.ok(pending);
    await host.decide(agent.profile.id, "net", "always");
    assert.equal((await finished(endpoint, request.id)).ok, true);
    const current = (await host.getAgent(agent.profile.id)).view;
    assert.equal(current.settings.execution!.externalGrants?.length, 1);
    assert.equal(current.settings.execution!.externalGrants?.[0]?.source, externalFile);
    await host.updateAgent({ id: agent.profile.id, execution: { ...current.settings.execution!, externalGrants: [] } });
    await assert.rejects(executionRpc(endpoint, "submit", { ...request, id: "new" }), /not authorized/);
    const saved = JSON.parse(await readFile(path.join(base, "private", "agents", agent.profile.id, "settings.json"), "utf8"));
    assert.deepEqual(saved.execution.externalGrants, []);
  } finally { await host.dispose(); await rm(base, { recursive: true, force: true }); }
});
