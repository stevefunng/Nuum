import { spawn, type ChildProcess } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { chmod, mkdir, open, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { createConnection } from "node:net";
import { executionRpc } from "@nuum/protocol/node";
import type { ExecutionContext, ExecutionEndpoint } from "@nuum/protocol";

interface Hello { instance: string; pid: number; active: number; unacknowledged?: number; contexts: ExecutionContext[]; executions: { id: string; contextId: string; state: string }[] }

/** One Host owns lifecycle decisions. Losing the supervisor does not kill accepted executions. */
export class ExecutorClient {
  private endpoint?: ExecutionEndpoint;
  private child?: ChildProcess;
  private timer?: ReturnType<typeof setInterval>;
  private checking = false;
  private stopped = false;
  private failures = 0;
  private readonly restarts: number[] = [];
  private token = "";
  private socket = "";
  private readonly directory: string;
  constructor(dataDir: string, private readonly entry: string, private readonly command = process.execPath) { this.directory = path.join(dataDir, "executor"); }

  async start(): Promise<Hello> {
    await mkdir(this.directory, { recursive: true, mode: 0o700 });
    await chmod(this.directory, 0o700);
    const ownerFile = path.join(this.directory, "owner.json");
    const owner = await readFile(ownerFile, "utf8").then(JSON.parse).catch(error => { if (error.code === "ENOENT") return null; throw error; });
    this.token = owner?.token ?? randomUUID() + randomUUID();
    const socketDir = path.join(tmpdir(), `nuum-exec-${createHash("sha256").update(this.directory).digest("hex").slice(0, 16)}`);
    await mkdir(socketDir, { recursive: true, mode: 0o700 });
    await chmod(socketDir, 0o700);
    this.socket = owner?.socket ?? path.join(socketDir, "exec.sock");
    await writeFile(ownerFile, JSON.stringify({ token: this.token, socket: this.socket }), { mode: 0o600 });
    let existing = await this.discover();
    if (existing) {
      const hello = await executionRpc<Hello>(existing, "hello");
      if (hello.active > 0 || (hello.unacknowledged ?? 0) > 0) { this.endpoint = existing; this.supervise(); return hello; }
      await executionRpc(existing, "shutdown");
      await this.waitAbsent(existing);
    }
    await this.spawn();
    this.supervise();
    return this.rpc<Hello>("hello");
  }
  async register(context: ExecutionContext): Promise<ExecutionEndpoint & { contextId: string }> { return this.rpc("register", context); }
  async rpc<T = unknown>(method: string, params: unknown = {}): Promise<T> {
    if (!this.endpoint) throw new Error("Execution daemon is unavailable; no unsandboxed fallback");
    return executionRpc<T>(this.endpoint, method, params);
  }
  async stop(): Promise<void> {
    this.stopped = true;
    clearInterval(this.timer);
    if (!this.endpoint) return;
    const owned = this.endpoint;
    await executionRpc(owned, "shutdown");
    await this.waitAbsent(owned);
    this.endpoint = undefined;
  }
  /** Supervision disposal leaves the daemon running so a new Host can adopt it. */
  detach(): void { this.stopped = true; clearInterval(this.timer); this.child?.unref(); }
  private supervise() {
    this.timer = setInterval(() => {
      if (this.stopped || this.checking) return;
      this.checking = true;
      void this.check().catch(error => { process.stderr.write(`Executor supervision: ${String(error)}\n`); }).finally(() => { this.checking = false; });
    }, 1000);
    this.timer.unref();
  }
  private async check() {
    try { await this.rpc("hello"); this.failures = 0; return; } catch {}
    if (this.stopped || this.failures >= 5) return;
    this.failures++;
    // A live/unresponsive owned process must not be replaced with a second executor.
    const discovery = await this.readDiscovery();
    if (discovery && alive(discovery.pid)) return;
    const now = Date.now();
    while (this.restarts.length && this.restarts[0]! < now - 60_000) this.restarts.shift();
    if (this.restarts.length >= 5) return;
    this.restarts.push(now);
    this.endpoint = undefined;
    await this.spawn();
  }
  private async readDiscovery(): Promise<{ socket: string; instance: string; pid: number } | null> {
    return readFile(path.join(this.directory, "discovery.json"), "utf8").then(JSON.parse).catch(error => { if (error.code === "ENOENT") return null; throw error; });
  }
  private async discover(): Promise<ExecutionEndpoint | undefined> {
    const discovery = await this.readDiscovery();
    if (!discovery) return;
    const endpoint = { socket: discovery.socket, instance: discovery.instance, token: this.token };
    try {
      const hello = await executionRpc<Hello>(endpoint, "hello");
      if (hello.pid !== discovery.pid || hello.instance !== discovery.instance) throw new Error("Executor identity mismatch");
      return endpoint;
    } catch (error) {
      if (alive(discovery.pid)) throw new Error(`Existing executor cannot be authenticated; refusing replacement: ${String(error)}`);
    }
  }
  private async spawn() {
    const existing = await this.discover();
    if (existing) { this.endpoint = existing; return; }
    // Missing discovery is not proof of death. Never unlink a socket still served by a process.
    if (await socketActive(this.socket)) throw new Error("Executor socket is still active without verifiable discovery; refusing replacement");
    await rm(this.socket, { force: true });
    const log = await open(path.join(this.directory, "daemon.log"), "a", 0o600);
    try {
      this.child = spawn(this.command, [this.entry, this.directory], {
        detached: true, stdio: ["ignore", log.fd, log.fd],
        env: { PATH: process.env.PATH, HOME: process.env.HOME, TMPDIR: process.env.TMPDIR, LANG: process.env.LANG }
      });
      this.child.on("error", error => process.stderr.write(`Executor startup: ${String(error)}\n`));
      this.child.unref();
    } finally { await log.close(); }
    const deadline = Date.now() + 20_000;
    while (Date.now() < deadline) {
      if (this.child.exitCode !== null || this.child.signalCode !== null) throw new Error("Executor exited before readiness; inspect executor/daemon.log");
      const discovered = await this.discover();
      if (discovered) { this.endpoint = discovered; return; }
      await delay(50);
    }
    throw new Error("Executor did not complete authenticated readiness handshake");
  }
  private async waitAbsent(endpoint: ExecutionEndpoint) {
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      try { await executionRpc(endpoint, "hello"); } catch { return; }
      await delay(50);
    }
    // Only kill the ChildProcess this Host spawned, never an unverified PID from disk.
    if (this.child && this.child.exitCode === null) this.child.kill("SIGKILL");
    throw new Error("Executor did not confirm graceful shutdown; execution cleanup is uncertain");
  }
}
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
function alive(pid: number): boolean { try { process.kill(pid, 0); return true; } catch (error) { return (error as NodeJS.ErrnoException).code === "EPERM"; } }
function socketActive(socket: string): Promise<boolean> {
  return new Promise((resolve, reject) => {
    const connection = createConnection(socket);
    connection.once("connect", () => { connection.destroy(); resolve(true); });
    connection.once("error", (error: NodeJS.ErrnoException) => {
      if (error.code === "ENOENT" || error.code === "ECONNREFUSED") resolve(false);
      else reject(error);
    });
    connection.setTimeout(1000, () => { connection.destroy(); reject(new Error("Executor socket identity could not be established")); });
  });
}
