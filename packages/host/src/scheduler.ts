/**
 * Run 的调度。`runId` 标识一次进程内执行；持久记录可以引用它作为执行证据，
 * 但重启后不能用旧 runId 恢复程序位置。
 *
 * 两条约束：全局同时最多 `maxConcurrent` 个 run；同一个 agent 同时只有一个 run，
 * 多个 session 共享同一持久身份与执行资源，必须串行调度。
 */

import path from "node:path";
import { realpathSync } from "node:fs";
import { freezeRunContext, type RunContext } from "./run-context.js";

export interface RunRequest {
  agentId: string;
  context: RunContext;
  projectRoot?: string | null;
  /** 真正拉起 Kernel 的动作。抛错视为该 run 立即收束。 */
  start(runId: string): Promise<void>;
}

interface ScheduledRun extends RunRequest {
  runId: string;
  complete(status: RunOutcome): void;
}

export type RunOutcome = "completed" | "failed" | "cancelled";
export interface SubmittedRun { runId: string; state: "started" | "queued"; started?: Promise<void>; completed: Promise<RunOutcome> }

export const DEFAULT_MAX_CONCURRENT_RUNS = 3;

export class AgentScheduler {
  private readonly active = new Map<string, ScheduledRun>();
  private readonly pending: ScheduledRun[] = [];

  constructor(
    private readonly maxConcurrent = DEFAULT_MAX_CONCURRENT_RUNS,
    private readonly newRunId: () => string = () => crypto.randomUUID()
  ) {}

  /**
   * 能起就起，起不动就排队。立刻起的会把启动 promise 一并交回 —— 调用方 await 它
   * 才能把「Kernel 根本没拉起来」这种失败当场回给用户，而不是静悄悄地挂着。
   * 排队的没有这个 promise：它什么时候起还不知道。
   */
  submit(request: RunRequest): SubmittedRun {
    let complete!: (status: RunOutcome) => void;
    const completed = new Promise<RunOutcome>(resolve => { complete = resolve; });
    const run: ScheduledRun = {
      ...request,
      complete,
      projectRoot: request.projectRoot ? canonicalRoot(request.projectRoot) : null,
      context: freezeRunContext(request.context),
      runId: this.newRunId()
    };
    if (this.canStart(run)) {
      return { runId: run.runId, state: "started", completed, started: this.launch(run) };
    }
    this.pending.push(run);
    return { runId: run.runId, state: "queued", completed };
  }

  /** run 收束（正常、出错、被取消都算）。腾出的位置立刻让给排队的。 */
  settle(runId: string, status: RunOutcome = "completed"): void {
    const run = this.active.get(runId);
    this.active.delete(runId);
    run?.complete(status);
    this.pump();
  }

  /**
   * 取消一个 agent 的活跃 run，并丢掉它排队中的 run。返回需要通知 Kernel 取消的
   * runId —— 排队中的还没进 Kernel，不用也不能去取消。
   */
  cancelAgent(agentId: string): string[] {
    for (let i = this.pending.length - 1; i >= 0; i -= 1) {
      if (this.pending[i]!.agentId === agentId) this.pending.splice(i, 1)[0]!.complete("cancelled");
    }
    const cancelling: string[] = [];
    for (const run of this.active.values()) {
      if (run.agentId === agentId) cancelling.push(run.runId);
    }
    return cancelling;
  }

  /** Dropping queued work must also release anyone awaiting its completion. */
  cancelQueued(runId: string): boolean {
    const index = this.pending.findIndex(run => run.runId === runId);
    if (index < 0) return false;
    this.pending.splice(index, 1)[0]!.complete("cancelled");
    return true;
  }

  close(): void {
    for (const run of [...this.pending, ...this.active.values()]) run.complete("cancelled");
    this.pending.length = 0;
    this.active.clear();
  }

  agentIdFor(runId: string): string | undefined {
    return this.active.get(runId)?.agentId;
  }

  /** 排队和活跃 run 都能取到；收束/取消后立即消失。 */
  contextFor(runId: string): RunContext | undefined {
    return this.active.get(runId)?.context ?? this.pending.find((run) => run.runId === runId)?.context;
  }

  /** 一个 agent 同时只有一个活跃 run，所以审批 / 取消能从 agentId 反查回去。 */
  activeRunFor(agentId: string): string | undefined {
    for (const run of this.active.values()) {
      if (run.agentId === agentId) return run.runId;
    }
    return undefined;
  }

  isBusy(agentId: string): boolean {
    for (const run of this.active.values()) {
      if (run.agentId === agentId) return true;
    }
    return this.pending.some((run) => run.agentId === agentId);
  }

  queuedForAgent(agentId: string): RunContext[] {
    return this.pending.filter((run) => run.agentId === agentId).map((run) => run.context);
  }

  activeRunIds(): string[] {
    return [...this.active.keys()];
  }

  queueDepth(): number {
    return this.pending.length;
  }

  private canStart(candidate: RunRequest): boolean {
    if (this.active.size >= this.maxConcurrent) return false;
    for (const run of this.active.values()) {
      if (run.agentId === candidate.agentId) return false;
      if (run.projectRoot && candidate.projectRoot && (containsRoot(run.projectRoot, candidate.projectRoot) || containsRoot(candidate.projectRoot, run.projectRoot))) return false;
    }
    return true;
  }

  private launch(run: ScheduledRun): Promise<void> {
    this.active.set(run.runId, run);
    const started = run.start(run.runId);
    // 自己收尾，这样没人 await 时槽位也不会永久漏掉。
    started.catch(() => this.settle(run.runId, "failed"));
    return started;
  }

  /**
   * 挑第一个「其 agent 当下空闲」的排队项，而不是死板的队首 —— 否则一个忙 agent
   * 的排队项会把后面所有别的 agent 全堵住。
   */
  private pump(): void {
    while (this.active.size < this.maxConcurrent) {
      const index = this.pending.findIndex((run) => this.canStart(run));
      if (index < 0) return;
      void this.launch(this.pending.splice(index, 1)[0]!);
    }
  }
}

function canonicalRoot(root: string): string {
  try { return realpathSync.native(root); } catch { return path.resolve(root); }
}
function containsRoot(parent: string, child: string): boolean {
  const relative = path.relative(parent, child);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}
