import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { mkdir, realpath } from "node:fs/promises";
import { createInterface } from "node:readline";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { ExecutionResult, type ExecutionContext, type ExecutionRequest } from "@nuum/protocol";

type Finished = Extract<ExecutionResult, { state: "finished" }>;
const here = path.dirname(fileURLToPath(import.meta.url));
const quote = (value: string) => `'${value.replaceAll("'", "'\\''")}'`;

export class IsolatedRunner {
  private readonly workers = new Map<string, { signature: string; worker: Promise<Worker> }>();
  constructor(private readonly dataDir: string) {}
  async busy(id?: string): Promise<boolean> { return (await Promise.all([...this.workers].filter(([key]) => id === undefined || key === id).map(async ([, entry]) => (await entry.worker.catch(() => null))?.busy ?? false))).some(Boolean); }
  async execute(context: ExecutionContext, request: ExecutionRequest, signal: AbortSignal): Promise<Finished> {
    const signature = JSON.stringify({ ...context, origin: undefined });
    let entry = this.workers.get(context.id);
    if (entry && entry.signature !== signature) { await this.revoke(context.id); entry = undefined; }
    if (!entry) {
      entry = { signature, worker: this.create(context) };
      this.workers.set(context.id, entry);
    }
    try { return await (await entry.worker).execute(request, signal); }
    catch (error) { await this.revoke(context.id); throw error; }
  }
  async revoke(id: string): Promise<void> {
    const entry = this.workers.get(id);
    if (!entry) return;
    this.workers.delete(id);
    const worker = await entry.worker.catch(() => null);
    await worker?.close();
  }
  async close(): Promise<void> { await Promise.all([...this.workers.keys()].map(id => this.revoke(id))); }

  private async create(context: ExecutionContext): Promise<Worker> {
    const scratch = path.join(this.dataDir, "scratch", createHash("sha256").update(context.id).digest("hex"));
    await mkdir(path.join(scratch, "tmp"), { recursive: true, mode: 0o700 });
    const canonicalScratch = await realpath(scratch);
    const root = await realpath(context.root);
    if (root !== context.root) throw new Error("Workspace path changed after Host authorization");
    // Only shipped implementation/dependencies are readable, never the repository or user data as a whole.
    const packagesRoot = path.resolve(here, "../..");
    const runtime = await realpath(process.execPath);
    const runtimeRoot = path.dirname(path.dirname(runtime));
    const workerEntry = path.resolve(here, "../dist/worker-bundle.mjs");
    const read = [root, canonicalScratch, ...context.readOnly, ...(context.writePaths ?? []), workerEntry,
      "/System", "/usr", "/bin", "/sbin", "/Library/Apple", "/private/etc", "/etc", "/dev", runtimeRoot];
    if (process.platform !== "darwin") throw new Error("This release has only validated macOS isolation; execution is disabled on this platform.");
    const launcher = path.join(packagesRoot, "sandbox/dist/isolated-launcher.js");
    const env = {
      PATH: process.env.PATH ?? "/usr/bin:/bin:/usr/sbin:/sbin",
      HOME: root, TMPDIR: path.join(canonicalScratch, "tmp"), LANG: "en_US.UTF-8", NUUM_ISOLATED_WORKER: "1"
    };
    const child = spawn(process.execPath, [launcher], { stdio: ["pipe", "pipe", "pipe"], detached: true,
      env: { PATH: env.PATH, HOME: root, TMPDIR: env.TMPDIR, LANG: env.LANG } });
    const worker = new Worker(child);
    child.stdin.write(JSON.stringify({
      policy: { filesystem: { denyRead: ["/"], allowRead: read, allowWrite: [root, canonicalScratch, ...(context.writePaths ?? [])], denyWrite: [] },
        network: { allowedDomains: context.network, deniedDomains: [], allowLocalBinding: false, allowUnixSockets: [] } },
      command: `${quote(runtime)} ${quote(workerEntry)}`, cwd: root, env,
      payload: JSON.stringify({ context: { ...context, root }, scratch: canonicalScratch })
    }) + "\n");
    try { await worker.ready; return worker; } catch (error) { await worker.close(); throw error; }
  }
}

class Worker {
  private background = false;
  get busy(): boolean { return Boolean(this.pending) || this.background; }
  readonly ready: Promise<void>;
  private resolveReady!: () => void;
  private rejectReady!: (error: Error) => void;
  private pending?: { id: string; name: string; resolve(value: Finished): void; reject(error: Error): void };
  private errors = "";
  private readonly exited: Promise<void>;
  private stopped = false;
  constructor(private readonly child: ChildProcessWithoutNullStreams) {
    this.ready = new Promise((resolve, reject) => { this.resolveReady = resolve; this.rejectReady = reject; });
    const timer = setTimeout(() => this.rejectReady(new Error(`Sandbox startup timed out: ${this.errors}`)), 20_000);
    void this.ready.then(() => clearTimeout(timer), () => clearTimeout(timer));
    this.exited = new Promise(resolve => child.once("close", () => {
      this.stopped = true;
      const error = new Error(`Isolated tool process stopped. Result may be incomplete. ${this.errors}`);
      this.rejectReady(error); this.pending?.reject(error); resolve();
    }));
    child.on("error", error => { this.rejectReady(error); this.pending?.reject(error); });
    child.stdin.on("error", error => { this.rejectReady(error); this.pending?.reject(error); });
    child.stderr.on("data", chunk => { this.errors = (this.errors + String(chunk)).slice(-8000); });
    let bytes = 0;
    child.stdout.on("data", (chunk: Buffer) => { bytes += chunk.length; if (bytes > 16 * 1024 * 1024) void this.close(); });
    createInterface({ input: child.stdout }).on("line", line => {
      bytes = 0;
      try {
        const frame = JSON.parse(line) as { ready?: boolean; busy?: boolean; id?: string; result?: unknown };
        if (frame.ready) this.resolveReady();
        if (frame.busy !== undefined) this.background = frame.busy;
        if (frame.id === this.pending?.id) {
          const result = ExecutionResult.parse(frame.result) as Finished;
          if (this.pending?.name === "shell") this.background = result.output.includes("is still running in the background.");
          this.pending?.resolve(result);
        }
      } catch { this.pending?.reject(new Error("Invalid isolated worker response")); }
    });
  }
  async execute(request: ExecutionRequest, signal: AbortSignal): Promise<Finished> {
    if (this.stopped) throw new Error("Execution worker stopped");
    if (this.pending) throw new Error("Execution context already has an active operation");
    if (signal.aborted) throw new Error("Execution cancelled");
    const stop = () => { void this.close(); };
    signal.addEventListener("abort", stop, { once: true });
    const timeout = setTimeout(stop, 120_000);
    try {
      return await new Promise<Finished>((resolve, reject) => {
        this.pending = { id: request.id, name: request.name, resolve, reject };
        this.child.stdin.write(JSON.stringify(request) + "\n");
      });
    } finally { clearTimeout(timeout); signal.removeEventListener("abort", stop); this.pending = undefined; }
  }
  async close(): Promise<void> {
    if (!this.stopped) this.child.kill("SIGTERM");
    const kill = setTimeout(() => { if (this.child.pid) { try { process.kill(-this.child.pid, "SIGKILL"); } catch {} } }, 2000);
    await this.exited;
    clearTimeout(kill);
  }
}
