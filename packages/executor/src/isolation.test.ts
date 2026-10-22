import assert from "node:assert/strict";
import { mkdtemp, mkdir, realpath, rm, writeFile, symlink, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { IsolatedRunner } from "./runner.js";
import type { ExecutionContext } from "@nuum/protocol";

test("OS isolation permits workspace operations and blocks sibling reads, writes and direct network", { skip: process.platform !== "darwin", timeout: 60_000 }, async () => {
  const base = await realpath(await mkdtemp(path.join(os.tmpdir(), "nuum-isolation-")));
  const root = path.join(base, "workspace");
  const outside = path.join(base, "secret.txt");
  await mkdir(root);
  await writeFile(outside, "DO_NOT_EXPOSE");
  await symlink(outside, path.join(root, "escape"));
  const runner = new IsolatedRunner(path.join(base, "private"));
  const context: ExecutionContext = { id: "test", agentId: "a", workspaceId: "w", root, commands: "always", network: [], approvedCommands: [], tools: ["read", "write", "shell"], readOnly: [] };
  const invoke = (name: string, input: Record<string, unknown>) => runner.execute(context, { id: crypto.randomUUID(), contextId: context.id, name, input }, new AbortController().signal);
  try {
    const write = await invoke("write", { path: "ok.txt", content: "hello" });
    assert.equal(write.ok, true, write.output);
    assert.equal(await readFile(path.join(root, "ok.txt"), "utf8"), "hello");
    const escaped = await invoke("read", { path: "escape" });
    assert.equal(escaped.ok, false);
    const command = await invoke("shell", { command: `cat '${outside}'; echo no > '${base}/outside.txt'; /usr/bin/curl --noproxy '*' --connect-timeout 2 --max-time 3 https://example.com`, block_until_ms: 10_000 });
    assert.ok(!command.output.includes("DO_NOT_EXPOSE"), command.output);
    assert.match(command.output, /not permitted|Permission denied|Could not|Failed to connect|Couldn't connect/i);
    await assert.rejects(readFile(path.join(base, "outside.txt")), { code: "ENOENT" });
    const again = await invoke("read", { path: "ok.txt" });
    assert.equal(again.ok, true, again.output);
    const trust = await invoke("shell", { command: "/usr/bin/grep -m 1 'BEGIN CERTIFICATE' /etc/ssl/cert.pem", block_until_ms: 1000 });
    assert.match(trust.output, /BEGIN CERTIFICATE/, "HTTPS clients must be able to read the system public trust bundle");
  } finally { await runner.close(); await rm(base, { recursive: true, force: true }); }
});

test("network grant is confined to its execution context and cancellation terminates a shell", { skip: process.platform !== "darwin", timeout: 60_000 }, async () => {
  const { createServer } = await import("node:http");
  const server = createServer((_request, response) => response.end("AUTHORIZED_FIXTURE"));
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as import("node:net").AddressInfo).port;
  const base = await realpath(await mkdtemp(path.join(os.tmpdir(), "nuum-network-")));
  const root = path.join(base, "work"); await mkdir(root);
  const runner = new IsolatedRunner(path.join(base, "private"));
  const context: ExecutionContext = { id: "allowed", agentId: "a", workspaceId: "w", root, commands: "always", approvedCommands: [], network: [`127.0.0.1:${port}`], tools: ["shell"], readOnly: [] };
  const command = `/usr/bin/curl --noproxy '' --max-time 3 -sS http://127.0.0.1:${port}`;
  const request = { id: "allowed-request", contextId: context.id, name: "shell", input: { command, block_until_ms: 5000 } };
  try {
    const granted = await runner.execute(context, request, new AbortController().signal);
    assert.match(granted.output, /AUTHORIZED_FIXTURE/);
    const denied = await runner.execute({ ...context, id: "denied", agentId: "b", network: [] }, { ...request, id: "denied-request", contextId: "denied" }, new AbortController().signal);
    assert.ok(!denied.output.includes("AUTHORIZED_FIXTURE"), denied.output);
    const abort = new AbortController();
    const running = runner.execute(context, { ...request, id: "cancel", input: { command: "sleep 30 & echo $! > child.pid; wait", block_until_ms: 60_000 } }, abort.signal);
    let pid = 0;
    for (let attempt = 0; attempt < 100 && !pid; attempt++) { pid = Number(await readFile(path.join(root, "child.pid"), "utf8").catch(() => "0")); if (!pid) await new Promise(resolve => setTimeout(resolve, 20)); }
    assert.ok(pid);
    abort.abort();
    await running.catch(() => undefined);
    await new Promise(resolve => setTimeout(resolve, 100));
    assert.throws(() => process.kill(pid, 0), { code: "ESRCH" });
  } finally { await runner.close(); server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); await rm(base, { recursive: true, force: true }); }
});
