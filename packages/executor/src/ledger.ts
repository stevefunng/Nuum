import { createHash } from "node:crypto";
import type { ExecutionRequest, ExecutionResult, ExecutionOrigin, ExecutionRecord, LocalToolAction } from "@nuum/protocol";

type Finished = Extract<ExecutionResult, { state: "finished" }>;
interface Entry { request: ExecutionRequest; origin?: ExecutionOrigin; signature: string; result: ExecutionResult; abort: AbortController; done?: Promise<void> }

/** Volatile execution records. A new daemon instance never claims an old ID was not executed. */
export class ExecutionLedger {
  private readonly entries = new Map<string, Entry>();
  private readonly acknowledged = new Map<string, { signature: string; contextId: string }>();
  constructor(private readonly execute: (request: ExecutionRequest, signal: AbortSignal) => Promise<Finished>) {}
  get running(): number { return [...this.entries.values()].filter(entry => entry.result.state === "running").length; }
  get ids(): string[] { return [...this.entries.keys()]; }
  request(id: string): ExecutionRequest { return this.require(id).request; }
  result(id: string): ExecutionResult { return this.require(id).result; }
  record(id: string): ExecutionRecord { const entry = this.require(id); return { request: entry.request, origin: entry.origin, result: entry.result }; }

  submit(request: ExecutionRequest, approval?: Omit<Extract<ExecutionResult, { state: "approval" }>, "state">, origin?: ExecutionOrigin): ExecutionResult {
    const encoded = JSON.stringify(request);
    if (encoded.length > 1024 * 1024) throw new Error("Execution input exceeds 1 MiB limit");
    const signature = createHash("sha256").update(encoded).digest("hex");
    const acknowledged = this.acknowledged.get(request.id);
    if (acknowledged) {
      if (acknowledged.signature !== signature) throw new Error("Execution ID reused with different input");
      return { state: "finished", ok: false, output: "Execution result already acknowledged; do not replay." };
    }
    const existing = this.entries.get(request.id);
    if (existing) {
      if (signature !== existing.signature) throw new Error("Execution ID reused with different input");
      return existing.result;
    }
    if (this.acknowledged.size >= 100_000) throw new Error("Executor generation capacity reached; restart when idle");
    if (this.entries.size >= 128) throw new Error("Execution result capacity reached; Host must acknowledge completed results");
    const entry: Entry = { request, origin: origin ? structuredClone(origin) : undefined, signature, abort: new AbortController(), result: approval ? { state: "approval", ...approval } : { state: "running" } };
    this.entries.set(request.id, entry);
    if (!approval) this.start(entry);
    return entry.result;
  }
  approve(id: string): void { const entry = this.require(id); if (entry.result.state === "approval") this.start(entry); }
  refuse(id: string): void {
    const entry = this.require(id);
    if (entry.result.state !== "approval") throw new Error("Execution is not awaiting approval");
    entry.result = { state: "finished", ok: false, output: "User denied this operation." };
  }
  async cancel(id: string): Promise<void> {
    const entry = this.require(id);
    if (entry.result.state === "finished") return;
    entry.abort.abort();
    if (entry.done) await entry.done;
    else entry.result = { state: "finished", ok: false, output: "Execution cancelled before starting." };
  }
  acknowledge(id: string): void {
    if (this.require(id).result.state !== "finished") throw new Error("Cannot acknowledge an unfinished execution");
    const entry = this.require(id);
    this.acknowledged.set(id, { signature: entry.signature, contextId: entry.request.contextId });
    this.entries.delete(id);
  }
  private start(entry: Entry): void {
    entry.result = { state: "running" };
    entry.done = Promise.resolve().then(() => this.execute(entry.request, entry.abort.signal)).then(result => {
      const bounded = { ...result, output: result.output.slice(0, 100_000) };
      entry.result = JSON.stringify(bounded).length > 2 * 1024 * 1024
        ? { state: "finished", ok: false, output: "Execution finished but result exceeds the 2 MiB delivery limit. Read a smaller range; do not repeat mutating operations." }
        : bounded;
    }, error => { entry.result = { state: "finished", ok: false, output: error instanceof Error ? error.message : String(error) }; });
  }
  private require(id: string): Entry { const entry = this.entries.get(id); if (!entry) throw new Error("Unknown execution; outcome is not established. Do not replay automatically."); return entry; }
}
