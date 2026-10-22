import { createServer } from "node:http";
import { chmod, mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { randomUUID, timingSafeEqual } from "node:crypto";
import path from "node:path";
import { ExecutionContext, ExecutionRequest, NetworkTarget, permissionOperationKey, externalGrantCovers, type ExternalGrant, type ExecutionResult } from "@nuum/protocol";
import { prepareExternal } from "./external-access.js";
import { ExecutionLedger } from "./ledger.js";
import { IsolatedRunner } from "./runner.js";

export async function startExecutor(dataDir: string, socket: string, ownerToken: string) {
  const instance = randomUUID();
  const runner = new IsolatedRunner(dataDir);
  const contexts = new Map<string, { context: ExecutionContext; token: string }>();
  const externalRequests = new Map<string, ExternalGrant>();
  const refusals = new Set<string>();
  const refusalKey = (context: ExecutionContext, request: { name: string; input: Record<string, unknown> }) => JSON.stringify([context.agentId, context.origin?.taskKey ?? context.origin?.runId ?? context.id, permissionOperationKey(request.name, request.input)]);
  let stopping = false;
  let lastOwnerContact = Date.now();
  const ledger = new ExecutionLedger(async (request, signal) => {
    const entry = contexts.get(request.contextId);
    if (!entry) throw new Error("Execution context was revoked");
    if (request.name === "request_network") {
      const target = NetworkTarget.parse(request.input.target);
      if (!entry.context.network.includes(target)) {
        await runner.revoke(request.contextId);
        entry.context = { ...entry.context, network: [...entry.context.network, target] };
      }
      return { state: "finished", ok: true, output: `Network access allowed for ${target} in this execution context.` };
    }
    if (request.name === "external_operation") {
      const approved = externalRequests.get(request.id);
      const prepared = await prepareExternal(request.input, entry.context, path.dirname(dataDir));
      if (!approved || !externalGrantCovers(approved, prepared.grant)) throw new Error("External resource changed after authorization; request approval again");
      const grant = prepared.grant;
      const isolated = { ...entry.context, id: `${entry.context.id}:external`, network: [...new Set([...entry.context.network, ...(grant.networkTargets ?? [])])], readOnly: [...entry.context.readOnly, ...grant.readPaths, ...(prepared.operation.source ? [prepared.operation.source] : [])], writePaths: [...grant.writePaths, ...(prepared.operation.destination ? [prepared.operation.destination] : [])] };
      try { return await runner.execute(isolated, { ...request, input: { ...prepared.operation, cwd: grant.cwd, command: prepared.operation.command } }, signal); }
      finally { await runner.revoke(isolated.id); }
    }
    return runner.execute(entry.context, request, signal);
  });
  const requireContext = (id: string, token: string, owner: boolean) => {
    const entry = contexts.get(id);
    if (!entry || (!owner && !equal(entry.token, token))) throw new Error("Execution context is not authorized");
    return entry;
  };
  async function suspend(id: string) {
    const entry = contexts.get(id);
    if (entry) entry.token = randomUUID() + randomUUID();
    const pending = ledger.ids.filter(key => ledger.request(key).contextId === id);
    await Promise.all(pending.map(key => ledger.cancel(key)));
    await runner.revoke(id);
    await runner.revoke(`${id}:external`);
  }
  async function revoke(id: string) {
    await suspend(id);
    contexts.delete(id);
  }
  async function dispatch(method: string, params: any, token: string) {
    const owner = equal(ownerToken, token);
    if (owner) lastOwnerContact = Date.now();
    if (method === "hello") {
      if (!owner) throw new Error("Authentication required");
      return { instance, pid: process.pid, active: ledger.running + (await runner.busy() ? 1 : 0), unacknowledged: ledger.ids.length, contexts: [...contexts.values()].map(entry => entry.context), executions: ledger.ids.map(id => ({ id, contextId: ledger.request(id).contextId, state: ledger.result(id).state })) };
    }
    if (stopping) throw new Error("Execution service is stopping");
    if (method === "contextStatus") {
      const entry = requireContext(String(params.contextId), token, owner);
      const executions = ledger.ids.filter(id => ledger.request(id).contextId === entry.context.id).map(id => ({ id, ...ledger.record(id) }));
      return { busy: await runner.busy(entry.context.id) || executions.some(item => item.result.state === "running"), executions };
    }
    if (method === "register") {
      if (!owner) throw new Error("Only Host can register execution contexts");
      const context = ExecutionContext.parse(params);
      const old = contexts.get(context.id);
      if (old && JSON.stringify({ ...old.context, origin: undefined }) !== JSON.stringify({ ...context, origin: undefined })) await revoke(context.id);
      const entry = { context, token: randomUUID() + randomUUID() };
      contexts.set(context.id, entry);
      return { socket, instance, token: entry.token, contextId: context.id };
    }
    if (method === "shutdown") {
      if (!owner) throw new Error("Only Host can stop the service");
      setImmediate(() => { void close(); }); return { ok: true };
    }
    if (method === "revoke") {
      if (!owner) throw new Error("Only Host can revoke contexts");
      await revoke(String(params.contextId)); return { ok: true };
    }
    if (method === "suspend") {
      if (!owner) throw new Error("Only Host can suspend contexts");
      await suspend(String(params.contextId)); return { ok: true };
    }
    if (method === "submit") {
      const request = ExecutionRequest.parse(params);
      const { context } = requireContext(request.contextId, token, owner);
      if (context.origin && !request.id.startsWith(`${context.origin.runId}:`)) throw new Error("Execution ID does not belong to the authorized run");
      if (!owner && Date.now() - lastOwnerContact > 5000 && !ledger.ids.includes(request.id)) throw new Error("Host supervision is disconnected; query existing executions or wait for reconnection");
      if (!owner && !context.tools.includes(request.name)) throw new Error("Tool is not enabled in this execution context");
      let approval: Extract<ExecutionResult, { state: "approval" }> | undefined;
      if (refusals.has(refusalKey(context, request)) || context.refusedOperations?.includes(permissionOperationKey(request.name, request.input))) return { state: "finished", ok: false, output: "User refused this operation in the current task. Do not ask again; choose another approach." };
      if (request.name === "request_network") {
        const target = NetworkTarget.parse(request.input.target);
        if (!context.network.includes(target)) approval = { state: "approval", action: "network", target, justification: typeof request.input.justification === "string" ? request.input.justification : undefined };
      } else if (request.name === "external_operation") {
        if (context.commands === "never" && request.input.operation === "shell") throw new Error("Command execution is disabled");
        const prepared = await prepareExternal(request.input, context, path.dirname(dataDir));
        externalRequests.set(request.id, prepared.grant);
        if (prepared.grant.rememberable === false || !(context.externalGrants ?? []).some(grant => externalGrantCovers(grant, prepared.grant))) {
          approval = { state: "approval", action: prepared.operation.operation === "read" ? "read-file" : prepared.operation.operation === "shell" ? "run-command" : "write-file", target: prepared.target, justification: prepared.operation.justification, allowAlways: prepared.grant.rememberable !== false, details: JSON.stringify({ operation: prepared.operation.operation, source: prepared.operation.source, destination: prepared.operation.destination, resourceRoot: prepared.operation.resourceRoot, cwd: prepared.grant.cwd, command: prepared.operation.command, rule: prepared.grant.command, readPaths: prepared.grant.readPaths, writePaths: prepared.grant.writePaths, overwrite: prepared.grant.overwrite, networkTargets: prepared.grant.networkTargets }, null, 2), grant: prepared.grant };
        }
      } else if (request.name === "shell" && context.commands === "never") throw new Error("Command execution is disabled");
      return ledger.submit(request, approval, context.origin);
    }
    const id = String(params.id);
    requireContext(ledger.request(id).contextId, token, owner);
    if (method === "status") return ledger.result(id);
    if (method === "cancel") { await ledger.cancel(id); return ledger.result(id); }
    if (method === "acknowledge") { if (!owner) throw new Error("Only Host can acknowledge results"); ledger.acknowledge(id); externalRequests.delete(id); return { ok: true }; }
    if (method === "decide") {
      if (!owner) throw new Error("Only Host can approve execution");
      if (ledger.result(id).state !== "approval") throw new Error("Request is no longer awaiting approval");
      if (params.remember === true && externalRequests.get(id)?.rememberable === false) throw new Error("This dynamic command can only be allowed once");
      if (params.allow === true) {
        const entry = contexts.get(ledger.request(id).contextId)!;
        const request = ledger.request(id);
        if (typeof params.policy === "string") entry.context.policy = params.policy;
        if (params.remember === true && request.name === "shell" && typeof request.input.command === "string") entry.context.approvedCommands.push(request.input.command);
        if (params.remember === true && request.name === "external_operation") entry.context.externalGrants = [...(entry.context.externalGrants ?? []), externalRequests.get(id)!];
        ledger.approve(id);
      } else {
        const request = ledger.request(id);
        refusals.add(refusalKey(contexts.get(request.contextId)!.context, request));
        ledger.refuse(id);
      }
      return ledger.result(id);
    }
    throw new Error("Unknown execution method");
  }
  const server = createServer(async (request, response) => {
    try {
      if (request.method !== "POST" || request.url !== "/rpc") throw new Error("Invalid execution endpoint");
      const chunks: Buffer[] = []; let length = 0;
      for await (const chunk of request) { length += chunk.length; if (length > 4 * 1024 * 1024) throw new Error("Execution request too large"); chunks.push(chunk); }
      const frame = JSON.parse(Buffer.concat(chunks).toString());
      if (frame.instance !== instance) throw new Error("Execution service generation changed; do not replay unknown operations");
      const token = request.headers.authorization?.replace(/^Bearer /, "") ?? "";
      const result = await dispatch(frame.method, frame.params, token);
      response.writeHead(200, { "content-type": "application/json" }); response.end(JSON.stringify({ result }));
    } catch (error) { response.writeHead(400); response.end(JSON.stringify({ error: error instanceof Error ? error.message : String(error) })); }
  });
  server.requestTimeout = 15_000;
  await mkdir(path.dirname(socket), { recursive: true, mode: 0o700 });
  await new Promise<void>((resolve, reject) => { server.once("error", reject); server.listen(socket, resolve); });
  await chmod(socket, 0o600);
  const discovery = path.join(dataDir, "discovery.json");
  const temp = `${discovery}.${instance}.tmp`;
  await writeFile(temp, JSON.stringify({ socket, instance, pid: process.pid, startedAt: Date.now() }), { mode: 0o600 });
  await rename(temp, discovery);
  const idleRetirement = setInterval(() => {
    if (stopping || Date.now() - lastOwnerContact < 30_000 || ledger.ids.length) return;
    void runner.busy().then(busy => { if (!busy && Date.now() - lastOwnerContact >= 30_000) void close(); });
  }, 5000);
  idleRetirement.unref();
  async function close() {
    if (stopping) return;
    stopping = true;
    clearInterval(idleRetirement);
    await Promise.all([...contexts.keys()].map(revoke));
    await runner.close();
    server.closeAllConnections();
    await new Promise<void>(resolve => server.close(() => resolve()));
    const current = await readFile(discovery, "utf8").then(JSON.parse).catch(() => null);
    if (current?.instance === instance) await rm(discovery, { force: true });
    await rm(socket, { force: true });
  }
  return { close, instance };
}
function equal(a: string, b: string): boolean { const left = Buffer.from(a), right = Buffer.from(b); return left.length === right.length && timingSafeEqual(left, right); }
