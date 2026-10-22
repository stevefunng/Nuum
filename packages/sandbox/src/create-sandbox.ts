import { dirname } from "node:path";
import { lstat, mkdir, readFile, realpath, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  KernelErrorCode,
  RpcError,
  type LocalToolAction,
  type ToolApproval,
  type ToolPermission
} from "@nuum/protocol";
import type {
  DeleteResult,
  FileMutation,
  PermissionVerdict,
  SandboxAuditor,
  SandboxPort
} from "./port.js";
import {
  disposePersistentShell,
  inspectPersistentShell,
  runPersistentShell,
  type PersistentShellRequest,
  type PersistentShellResult
} from "./persistent-shell.js";

const DENY_COMMANDS = [
  /\brm\s+(?:-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\s+(?:\/|\~|\$HOME)(?:\s|$)/,
  /\bmkfs\b/,
  /\bdd\s+if=/,
  /:\(\)\s*\{\s*:\|\:&\s*\};:/
];

export interface CreateSandboxOptions {
  roots: {
    home: string;
    project: string | null;
    scratch: string;
    terminals?: string;
    denied: string[];
    readOnly?: string[];
  };
  permission: ToolPermission;
  approvals?: ToolApproval[];
  refused?: ToolApproval[];
  auditor?: SandboxAuditor;
}

export function createSandbox(options: CreateSandboxOptions): SandboxPort {
  return new LocalSandbox(options);
}

class LocalSandbox implements SandboxPort {
  readonly cwd: string;
  private permission: ToolPermission;
  private readonly approvals: Set<string>;
  private readonly refused: Set<string>;
  private readonly auditor?: SandboxAuditor;

  constructor(private readonly options: CreateSandboxOptions) {
    this.cwd = options.roots.project ?? options.roots.scratch;
    this.permission = options.permission;
    this.approvals = new Set((options.approvals ?? []).map(approvalKey));
    this.refused = new Set((options.refused ?? []).map(approvalKey));
    this.auditor = options.auditor;
  }

  async authorize(action: LocalToolAction, input: string): Promise<PermissionVerdict> {
    if (action === "run-command") return this.authorizeCommand(input);
    const target = await this.canonicalPath(input);
    const home = await realpathExistingPrefix(path.resolve(this.options.roots.home));
    const denied = await Promise.all(
      this.options.roots.denied.map((item) => realpathExistingPrefix(path.resolve(item)))
    );
    if (denied.some((root) => contains(root, target))) {
      return this.deny(action, target, "Path is inside a protected host-only store.");
    }
    const readOnly = await Promise.all(
      (this.options.roots.readOnly ?? []).map((item) => realpathExistingPrefix(path.resolve(item)))
    );
    if (readOnly.some((root) => contains(root, target))) {
      return action === "read-file" || action === "list-directory"
        ? this.allow(action, target, "Work read-only knowledge root")
        : this.deny(action, target, "Path is a Work read-only knowledge root.");
    }
    const scratchRoot = await realpathExistingPrefix(path.resolve(this.options.roots.scratch));
    if (!contains(home, target) && !contains(scratchRoot, target)) {
      return this.deny(action, target, "Path is outside the allowed local execution root.");
    }

    const scratch = await realpathExistingPrefix(path.resolve(this.options.roots.scratch));
    const project = this.options.roots.project
      ? await realpathExistingPrefix(path.resolve(this.options.roots.project))
      : null;
    if (contains(scratch, target) || (project && contains(project, target))) {
      return this.allow(action, target, "pre-approved root");
    }

    // scratch 是 agents/{id}/scratch，所以两级父目录分别是本 agent 与 agents 根。
    const ownAgent = dirname(scratch);
    const agentsRoot = dirname(ownAgent);
    if (contains(agentsRoot, target)) {
      if (action === "read-file" || action === "list-directory") {
        return this.allow(action, target, "agent stores are read-only to tools");
      }
      return this.deny(action, target, "Agent stores are read-only; use update_state for your own state.");
    }
    return this.standingDecision(action, target);
  }

  grantOnce(action: LocalToolAction, target: string): void {
    this.approvals.add(approvalKey({ action, target }));
  }

  refuse(action: LocalToolAction, target: string): void {
    this.refused.add(approvalKey({ action, target }));
  }

  setPermission(permission: ToolPermission): void {
    this.permission = permission;
  }

  async resolvePath(input: string): Promise<string> {
    const resolved = await this.canonicalPath(input);
    const home = await realpathExistingPrefix(path.resolve(this.options.roots.home));
    const scratchRoot = await realpathExistingPrefix(path.resolve(this.options.roots.scratch));
    if (!contains(home, resolved) && !contains(scratchRoot, resolved)) {
      this.audit("resolve", false, { path: resolved, detail: "outside local execution root" });
      throw new RpcError(KernelErrorCode.SANDBOX, `Path is outside the allowed local execution root: ${input}`);
    }
    this.audit("resolve", true, { path: resolved });
    return resolved;
  }

  async readFile(filePath: string): Promise<string> {
    const resolved = await this.requireAllowed("read-file", filePath);
    const content = await readFile(resolved, "utf8");
    this.audit("read", true, { path: resolved });
    return content;
  }

  async readBinary(filePath: string): Promise<{ path: string; data: Uint8Array }> {
    const resolved = await this.requireAllowed("read-file", filePath);
    const data = await readFile(resolved);
    this.audit("read", true, { path: resolved, detail: "binary" });
    return { path: resolved, data };
  }

  async writeFile(filePath: string, content: string): Promise<FileMutation> {
    const resolved = await this.requireAllowed("write-file", filePath);
    const before = await readFile(resolved, "utf8").catch((error: NodeJS.ErrnoException) => {
      if (error.code === "ENOENT") return null;
      throw error;
    });
    await mkdir(dirname(resolved), { recursive: true });
    await writeFile(resolved, content, "utf8");
    this.audit("write", true, { path: resolved });
    return { path: resolved, before, after: content };
  }

  async mutateFile(filePath: string, transform: (current: string) => string): Promise<FileMutation> {
    const resolved = await this.requireAllowed("write-file", filePath);
    const current = await readFile(resolved, "utf8");
    const next = transform(current);
    await writeFile(resolved, next, "utf8");
    this.audit("edit", true, { path: resolved });
    return { path: resolved, before: current, after: next };
  }

  async deletePath(filePath: string): Promise<DeleteResult> {
    const resolved = await this.requireAllowed("write-file", filePath);
    const info = await lstat(resolved);
    const kind = info.isDirectory() ? "directory" : "file";
    await rm(resolved, { recursive: kind === "directory", force: false });
    this.audit("write", true, { path: resolved, detail: `deleted ${kind}` });
    return { path: resolved, kind };
  }

  async shell(request: PersistentShellRequest): Promise<PersistentShellResult> {
    const terminals = this.options.roots.terminals ?? path.join(dirname(this.options.roots.scratch), "terminals");
    if (request.shellId) {
      await this.requireAllowed("read-file", path.join(terminals, `${request.shellId}.txt`));
      return inspectPersistentShell(terminals, request.shellId);
    }
    if (!request.command) throw new RpcError(KernelErrorCode.INVALID, "A command or shell_id is required.");
    await this.requireAllowed("run-command", request.command);
    const initialCwd = await this.shellInitialCwd();
    let workingDirectory: string | undefined;
    let notice: string | undefined;
    if (request.workingDirectory) {
      try {
        const candidate = await this.resolvePath(request.workingDirectory);
        const info = await stat(candidate);
        if (!info.isDirectory()) throw Object.assign(new Error("not a directory"), { code: "ENOTDIR" });
        workingDirectory = candidate;
      } catch (error) {
        const code = (error as NodeJS.ErrnoException).code;
        if (code !== "ENOENT" && code !== "ENOTDIR") throw error;
        workingDirectory = initialCwd;
        notice = `Working directory ${request.workingDirectory} does not exist; fell back to ${initialCwd}.`;
      }
    }
    return runPersistentShell(terminals, initialCwd, {
      ...request,
      ...(workingDirectory ? { workingDirectory } : {}),
      ...(notice ? { notice } : {})
    });
  }

  async disposeShell(): Promise<void> {
    const terminals = this.options.roots.terminals ?? path.join(dirname(this.options.roots.scratch), "terminals");
    await disposePersistentShell(terminals);
  }

  private audit(
    action: LocalToolAction | "read" | "write" | "edit" | "resolve",
    ok: boolean,
    extra: { path?: string; command?: string; detail?: string }
  ): void {
    this.auditor?.({
      at: Date.now(),
      permission: this.permission,
      action: auditAction(action),
      ok,
      ...extra
    });
  }

  private async canonicalPath(input: string): Promise<string> {
    return realpathExistingPrefix(path.resolve(this.cwd, input));
  }

  private async shellInitialCwd(): Promise<string> {
    const requested = this.options.roots.project ?? this.options.roots.scratch;
    const resolved = await realpathExistingPrefix(path.resolve(requested));
    const info = await stat(resolved).catch(() => null);
    if (info?.isDirectory()) return resolved;
    await mkdir(this.options.roots.scratch, { recursive: true });
    return realpath(this.options.roots.scratch);
  }

  private async requireAllowed(action: LocalToolAction, input: string): Promise<string> {
    const verdict = await this.authorize(action, input);
    if (verdict.decision === "allow") return verdict.target;
    const message = verdict.reason ?? `Approval is required for ${action} ${verdict.target}`;
    throw new RpcError(KernelErrorCode.SANDBOX, message);
  }

  private authorizeCommand(command: string): PermissionVerdict {
    const target = commandToken(command);
    if (!target) return this.deny("run-command", "(empty)", "Command is empty.");
    for (const pattern of DENY_COMMANDS) {
      if (pattern.test(command)) {
        return this.deny("run-command", target, `Command denied by hard safety policy: ${command}`);
      }
    }
    return this.standingDecision("run-command", target);
  }

  private standingDecision(action: LocalToolAction, target: string): PermissionVerdict {
    const key = approvalKey({ action, target });
    if (this.approvals.has(key)) return this.allow(action, target, "approved exact action");
    if (this.refused.has(key)) return this.deny(action, target, "The same action was previously refused.");
    if (this.permission === "always") return this.allow(action, target, "standing permission");
    if (this.permission === "never") return this.deny(action, target, "Local tools are disabled for this agent.");
    this.audit(action, false, { ...(action === "run-command" ? { command: target } : { path: target }), detail: "approval required" });
    return { decision: "ask", target };
  }

  private allow(action: LocalToolAction, target: string, detail: string): PermissionVerdict {
    this.audit(action, true, { ...(action === "run-command" ? { command: target } : { path: target }), detail });
    return { decision: "allow", target };
  }

  private deny(action: LocalToolAction, target: string, reason: string): PermissionVerdict {
    this.audit(action, false, { ...(action === "run-command" ? { command: target } : { path: target }), detail: reason });
    return { decision: "deny", target, reason };
  }
}

async function realpathExistingPrefix(target: string): Promise<string> {
  let cursor = target;
  while (true) {
    try {
      const existing = await realpath(cursor);
      const rest = path.relative(cursor, target);
      return rest && rest !== "" ? path.resolve(existing, rest) : existing;
    } catch {
      const parent = dirname(cursor);
      if (parent === cursor) return target;
      cursor = parent;
    }
  }
}

function contains(root: string, target: string): boolean {
  return target === root || target.startsWith(root.endsWith(path.sep) ? root : `${root}${path.sep}`);
}

function approvalKey(approval: ToolApproval): string {
  return `${approval.action}\0${approval.target}`;
}

function commandToken(command: string): string {
  const tokens = command.trim().match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) ?? [];
  const first = tokens.find((token) => token !== "env" && !/^[A-Za-z_][A-Za-z0-9_]*=/.test(token));
  return first ? path.basename(first.replace(/^["']|["']$/g, "")) : "";
}

function auditAction(action: LocalToolAction | "read" | "write" | "edit" | "resolve") {
  if (action === "read") return "read-file" as const;
  if (action === "write" || action === "edit") return "write-file" as const;
  return action;
}
