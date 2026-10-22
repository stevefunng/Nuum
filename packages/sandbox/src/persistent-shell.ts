import { spawn, type ChildProcess } from "node:child_process";
import { mkdir, open, readFile, stat, writeFile, appendFile } from "node:fs/promises";
import path from "node:path";
import type { Readable, Writable } from "node:stream";

const CONTROL_PREFIX = "\u001eNUUM\tEND\t";
const TAIL_BYTES = 24_000;
const sessions = new Map<string, Promise<PersistentShell>>();

export interface PersistentShellRequest {
  command?: string;
  shellId?: string;
  workingDirectory?: string;
  blockUntilMs?: number;
  abortSignal?: AbortSignal;
  notice?: string;
}

export interface PersistentShellResult {
  shellId: string;
  path: string;
  pid: number;
  cwd: string;
  runningForMs: number;
  exitCode: number | null;
  background: boolean;
  tail: string;
  notice?: string;
}

interface ShellJob {
  id: string;
  path: string;
  pid: number;
  cwd: string;
  startedAt: number;
  exitCode: number | null;
  notice?: string;
  done: Promise<void>;
  finish(): void;
}

export async function runPersistentShell(
  terminalsRoot: string,
  initialCwd: string,
  request: PersistentShellRequest
): Promise<PersistentShellResult> {
  if (request.shellId) return inspectPersistentShell(terminalsRoot, request.shellId);
  const shell = await getShell(terminalsRoot, initialCwd);
  return shell.run(request);
}

export async function inspectPersistentShell(
  terminalsRoot: string,
  shellId: string
): Promise<PersistentShellResult> {
  assertShellId(shellId);
  const key = path.resolve(terminalsRoot);
  const existing = sessions.get(key);
  if (existing) {
    const shell = await existing.catch(() => null);
    const current = shell?.inspect(shellId);
    if (current) return current;
  }
  return inspectFile(key, shellId);
}

export async function disposePersistentShell(terminalsRoot: string): Promise<void> {
  const key = path.resolve(terminalsRoot);
  const pending = sessions.get(key);
  sessions.delete(key);
  if (!pending) return;
  const shell = await pending.catch(() => null);
  await shell?.dispose();
}

export async function hasRunningShellJobs(): Promise<boolean> {
  return (await Promise.all([...sessions.values()].map(async entry => (await entry.catch(() => null))?.busy ?? false))).some(Boolean);
}

export async function disposeAllShells(): Promise<void> {
  const pending = [...sessions.values()];
  sessions.clear();
  await Promise.all(pending.map(async (entry) => {
    const shell = await entry.catch(() => null);
    await shell?.dispose();
  }));
}

async function getShell(terminalsRoot: string, initialCwd: string): Promise<PersistentShell> {
  const key = path.resolve(terminalsRoot);
  const known = sessions.get(key);
  if (known) {
    const shell = await known;
    if (shell.alive) return shell;
    sessions.delete(key);
  }
  let created!: Promise<PersistentShell>;
  created = PersistentShell.create(key, initialCwd, () => {
    // A cancelled shell may close after the next turn has already created its
    // replacement. The old close callback must not unregister that new child.
    if (sessions.get(key) === created) sessions.delete(key);
  });
  sessions.set(key, created);
  try {
    return await created;
  } catch (error) {
    sessions.delete(key);
    throw error;
  }
}

class PersistentShell {
  readonly pid: number;
  alive = true;
  get busy(): boolean { return this.active !== null; }
  private readonly stdin: Writable;
  private readonly control: Readable;
  private readonly jobs = new Map<string, ShellJob>();
  private active: ShellJob | null = null;
  private controlBuffer = "";
  private closeCode: number | null = null;
  private readonly closed: Promise<void>;
  private finishClosed!: () => void;

  private constructor(
    private readonly terminalsRoot: string,
    readonly initialCwd: string,
    private currentCwd: string,
    private readonly child: ChildProcess,
    private readonly onClosed: () => void
  ) {
    this.pid = child.pid!;
    this.stdin = child.stdin!;
    this.control = child.stdio[3] as Readable;
    this.closed = new Promise((resolve) => { this.finishClosed = resolve; });
    this.control.setEncoding("utf8");
    this.control.on("data", (chunk: string) => this.onControl(chunk));
    child.once("close", (code) => void this.onProcessClosed(code));
  }

  static async create(terminalsRoot: string, requestedCwd: string, onClosed: () => void): Promise<PersistentShell> {
    await mkdir(terminalsRoot, { recursive: true });
    const initialCwd = await existingDirectory(requestedCwd);
    const child = spawn("/bin/bash", ["--noprofile", "--norc"], {
      cwd: initialCwd,
      detached: process.env.NUUM_ISOLATED_WORKER !== "1",
      env: {
        PATH: process.env.PATH,
        ...Object.fromEntries(Object.entries(process.env).filter(([key]) => /^(https?_proxy|all_proxy|no_proxy)$/i.test(key))),
        HOME: process.env.HOME,
        TMPDIR: process.env.TMPDIR,
        LANG: process.env.LANG,
        SHELL: "/bin/bash",
        TERM: "dumb"
      },
      stdio: ["pipe", "ignore", "ignore", "pipe"]
    });
    await new Promise<void>((resolve, reject) => {
      child.once("spawn", resolve);
      child.once("error", reject);
    });
    return new PersistentShell(terminalsRoot, initialCwd, initialCwd, child, onClosed);
  }

  async run(request: PersistentShellRequest): Promise<PersistentShellResult> {
    if (!this.alive) throw new Error("The persistent shell is not running.");
    if (!request.command) throw new Error("A command is required to start a shell job.");
    if (this.active) {
      throw new Error(`Shell is busy with ${this.active.id}; inspect it with shell_id before starting another command.`);
    }
    const job = createJob(this.terminalsRoot, this.pid, request.workingDirectory ?? this.currentCwd, request.notice);
    this.jobs.set(job.id, job);
    this.active = job;
    await writeFile(job.path, renderHeader(job), "utf8");

    const restore = request.workingDirectory !== undefined;
    const command = renderCommand(job, request.command, request.workingDirectory, restore);
    const onAbort = () => { void this.dispose(); };
    request.abortSignal?.addEventListener("abort", onAbort, { once: true });
    this.stdin.write(command);

    const blockUntilMs = request.blockUntilMs ?? 30_000;
    const completed = await waitUntil(job.done, blockUntilMs);
    request.abortSignal?.removeEventListener("abort", onAbort);
    return this.snapshot(job, !completed);
  }

  inspect(shellId: string): Promise<PersistentShellResult> | null {
    assertShellId(shellId);
    const job = this.jobs.get(shellId);
    return job ? this.snapshot(job, job.exitCode === null) : null;
  }

  async dispose(): Promise<void> {
    if (!this.alive) {
      await this.closed;
      return;
    }
    this.alive = false;
    this.closeCode = 130;
    killGroup(this.child, "SIGTERM");
    const graceful = await waitUntil(this.closed, 500);
    if (!graceful) {
      killGroup(this.child, "SIGKILL");
      await this.closed;
    }
  }

  private async snapshot(job: ShellJob, background: boolean): Promise<PersistentShellResult> {
    return {
      shellId: job.id,
      path: job.path,
      pid: job.pid,
      cwd: job.cwd,
      runningForMs: Date.now() - job.startedAt,
      exitCode: job.exitCode,
      background,
      tail: await readOutputTail(job.path),
      ...(job.notice ? { notice: job.notice } : {})
    };
  }

  private onControl(chunk: string): void {
    this.controlBuffer += chunk;
    let newline = this.controlBuffer.indexOf("\n");
    while (newline >= 0) {
      const line = this.controlBuffer.slice(0, newline);
      this.controlBuffer = this.controlBuffer.slice(newline + 1);
      this.handleControlLine(line);
      newline = this.controlBuffer.indexOf("\n");
    }
  }

  private handleControlLine(line: string): void {
    if (!line.startsWith(CONTROL_PREFIX)) return;
    const [shellId, rawCode, encodedCwd] = line.slice(CONTROL_PREFIX.length).split("\t");
    const job = this.active;
    if (!job || shellId !== job.id) return;
    const code = Number(rawCode);
    const cwd = decodeBase64(encodedCwd);
    if (cwd) this.currentCwd = cwd;
    void this.complete(job, Number.isInteger(code) ? code : 1);
  }

  private async complete(job: ShellJob, exitCode: number): Promise<void> {
    if (job.exitCode !== null) return;
    job.exitCode = exitCode;
    await appendFile(job.path, `\n---\nexit_code: ${exitCode}\n`, "utf8").catch(() => undefined);
    if (this.active === job) this.active = null;
    job.finish();
  }

  private async onProcessClosed(code: number | null): Promise<void> {
    this.alive = false;
    const active = this.active;
    if (active) await this.complete(active, this.closeCode ?? code ?? 1);
    this.onClosed();
    this.finishClosed();
  }
}

function createJob(terminalsRoot: string, pid: number, cwd: string, notice?: string): ShellJob {
  const id = crypto.randomUUID();
  let finish!: () => void;
  const done = new Promise<void>((resolve) => { finish = resolve; });
  return {
    id,
    path: path.join(terminalsRoot, `${id}.txt`),
    pid,
    cwd,
    startedAt: Date.now(),
    exitCode: null,
    ...(notice ? { notice } : {}),
    done,
    finish
  };
}

function renderHeader(job: ShellJob): string {
  return [
    `pid: ${job.pid}`,
    `cwd: ${job.cwd}`,
    "running_for_ms: 0",
    `started_at_ms: ${job.startedAt}`,
    "---",
    ""
  ].join("\n");
}

function renderCommand(job: ShellJob, command: string, workingDirectory: string | undefined, restore: boolean): string {
  const lines = [
    `__nuum_command=${shellQuote(command)}`,
    `__nuum_output=${shellQuote(job.path)}`,
    "__nuum_previous_pwd=$PWD"
  ];
  if (workingDirectory) lines.push(`cd -- ${shellQuote(workingDirectory)}`);
  lines.push(
    // This MVP has no send-input channel. Keep commands away from the bash
    // control stream or a bare `read`/`cat` could consume the wrapper itself.
    "eval -- \"$__nuum_command\" >> \"$__nuum_output\" 2>&1 </dev/null",
    "__nuum_exit_code=$?"
  );
  if (restore) lines.push("cd -- \"$__nuum_previous_pwd\" 2>/dev/null || true");
  lines.push(
    "__nuum_cwd_b64=$(printf '%s' \"$PWD\" | /usr/bin/base64 | /usr/bin/tr -d '\\n')",
    `printf '\\036NUUM\\tEND\\t%s\\t%s\\t%s\\n' ${shellQuote(job.id)} \"$__nuum_exit_code\" \"$__nuum_cwd_b64\" >&3`,
    "unset __nuum_command __nuum_output __nuum_previous_pwd __nuum_exit_code __nuum_cwd_b64",
    ""
  );
  return lines.join("\n");
}

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

async function existingDirectory(requested: string): Promise<string> {
  const resolved = path.resolve(requested);
  const info = await stat(resolved);
  if (!info.isDirectory()) throw new Error(`Shell working directory is not a directory: ${resolved}`);
  return resolved;
}

async function inspectFile(terminalsRoot: string, shellId: string): Promise<PersistentShellResult> {
  const filePath = path.join(terminalsRoot, `${shellId}.txt`);
  const content = await readFile(filePath, "utf8");
  const pid = Number(content.match(/^pid: (\d+)$/m)?.[1]);
  const cwd = content.match(/^cwd: (.*)$/m)?.[1] ?? "";
  const startedAt = Number(content.match(/^started_at_ms: (\d+)$/m)?.[1]);
  const exit = content.match(/\n---\nexit_code: (-?\d+)\n?$/);
  return {
    shellId,
    path: filePath,
    pid,
    cwd,
    runningForMs: Number.isFinite(startedAt) ? Date.now() - startedAt : 0,
    exitCode: exit ? Number(exit[1]) : null,
    background: !exit,
    tail: await readOutputTail(filePath)
  };
}

async function readOutputTail(filePath: string): Promise<string> {
  const info = await stat(filePath);
  const start = Math.max(0, info.size - TAIL_BYTES);
  const length = info.size - start;
  const handle = await open(filePath, "r");
  try {
    const buffer = Buffer.alloc(length);
    await handle.read(buffer, 0, length, start);
    let text = buffer.toString("utf8");
    const header = text.indexOf("---\n");
    if (start === 0 && header >= 0) text = text.slice(header + 4);
    const footer = text.lastIndexOf("\n---\nexit_code:");
    if (footer >= 0) text = text.slice(0, footer);
    return text.trimEnd();
  } finally {
    await handle.close();
  }
}

function decodeBase64(value: string | undefined): string | null {
  if (!value) return null;
  try {
    return Buffer.from(value, "base64").toString("utf8");
  } catch {
    return null;
  }
}

function assertShellId(shellId: string): void {
  if (!/^[0-9a-f-]{36}$/.test(shellId)) throw new Error("shell_id must be a UUID returned by shell.");
}

function waitUntil(promise: Promise<unknown>, timeoutMs: number): Promise<boolean> {
  if (timeoutMs <= 0) return Promise.resolve(false);
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(false), timeoutMs);
    void promise.then(() => {
      clearTimeout(timer);
      resolve(true);
    });
  });
}

function killGroup(child: ChildProcess, signal: NodeJS.Signals): void {
  const pid = child.pid;
  if (!pid) return;
  try {
    process.kill(-pid, signal);
  } catch {
    child.kill(signal);
  }
}
