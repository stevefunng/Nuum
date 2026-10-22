import { isDeepStrictEqual } from "node:util";
import { copyFile, constants, mkdir, open, readFile, readdir, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  EMPTY_WORK_CATALOG,
  HostErrorCode,
  RpcError,
  WorkCatalog,
  WorkEvent,
  WorkProfile,
  type WorkChatMessage,
  type WorkEventDraft,
  type WorkProjection,
  type WorkTask,
  type WorkMembership
} from "@nuum/protocol";

interface WorkRecord {
  profile: WorkProfile;
  lastSeq: number;
  lastActivityAt: number;
}

export class WorkStore {
  private readonly memberships = new Map<string, Map<string, WorkMembership>>();
  private readonly works = new Map<string, WorkRecord>();
  private readonly appendChains = new Map<string, Promise<unknown>>();

  constructor(readonly dataDir: string) {}

  async init(): Promise<void> {
    await mkdir(this.worksRoot(), { recursive: true });
    this.works.clear();
    this.memberships.clear();
    for (const id of await readdir(this.worksRoot())) {
      const profile = await readJson(path.join(this.workDir(id), "profile.json"), WorkProfile);
      if (!profile) continue;
      await repairFinalLine(this.timelineFile(id));
      const events = await this.readTimeline(id);
      for (const event of events) this.projectMembership(event);
      const tail = events.at(-1);
      this.works.set(id, {
        profile,
        lastSeq: tail?.seq ?? 0,
        lastActivityAt: Math.max(profile.createdAt, tail?.createdAt ?? 0)
      });
    }
  }

  /** Preserve the previous log before switching recovery semantics. No old work is replayed blindly. */
  async migrateExecutionHistory(): Promise<void> {
    for (const work of this.listWorks()) {
      const marker = path.join(this.workDir(work.id), "runtime-version.json");
      try {
        const version = JSON.parse(await readFile(marker, "utf8"));
        if (version.version !== 2) throw new Error("Unsupported room runtime version");
        continue;
      } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
      const events = await this.readTimeline(work.id);
      if (events.length && !events.some(event => event.type === "history.imported")) {
        for (const file of [this.timelineFile(work.id), path.join(this.workDir(work.id), "cursors.json")]) {
          try { await copyFile(file, `${file}.pre-simplification.bak`, constants.COPYFILE_EXCL); }
          catch (error) { if (!["ENOENT", "EEXIST"].includes((error as NodeJS.ErrnoException).code ?? "")) throw error; }
        }
        const claimed = new Set(events.flatMap(event => event.type === "dispatch.requested" ? [event.causationId, event.discussion?.rootId] : event.type === "discussion.started" ? event.triggerEventIds : event.type === "execution.started" || event.type === "execution.finished" ? [event.sourceEventId] : []));
        const uncertain = events.filter(event => !claimed.has(event.id) && ((event.type === "chat.posted" && event.actor.kind === "user") || ["task.delegated", "task.handed_off", "task.transitioned"].includes(event.type)));
        await this.appendEvent(work.id, { type: "history.imported", id: crypto.randomUUID(), workId: work.id, createdAt: Date.now(), actor: { kind: "system", id: "migration" }, unconfirmedEventIds: uncertain.map(event => event.id) });
      }
      await writeJsonAtomic(marker, { version: 2 });
    }
  }

  membership(workId: string, agentId: string): WorkMembership {
    return structuredClone(this.memberships.get(workId)?.get(agentId) ?? { revision: 0, binding: null });
  }

  membershipsFor(agentId: string): Record<string, WorkMembership> {
    return Object.fromEntries([...this.memberships].flatMap(([workId, members]) => {
      const member = members.get(agentId);
      return member ? [[workId, structuredClone(member)]] : [];
    }));
  }

  private projectMembership(event: WorkEvent): void {
    if (event.type !== "member.attached" && event.type !== "member.detached") return;
    const members = this.memberships.get(event.workId) ?? new Map<string, WorkMembership>();
    members.set(event.agentId, { revision: event.membershipRevision, binding: event.type === "member.detached" ? null : {
      workId: event.workId, role: event.role, joinedAt: event.createdAt,
      grants: { canPost: event.role !== "observer", canManageOwnTasks: event.role !== "observer", canAssignTasks: event.role !== "observer", canEditCatalog: event.role === "coordinator" }
    } });
    this.memberships.set(event.workId, members);
  }

  /** One-time reconciliation uses V1 settings as truth, then Room events take over. */
  async migrateMemberships(agents: { profile: { id: string }; settings: { workMembership?: WorkMembership } }[]): Promise<void> {
    const marker = path.join(this.dataDir, "room-memberships-v2.json");
    try { await readFile(marker); return; } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
    for (const agent of agents) {
      const legacy = agent.settings.workMembership?.binding;
      for (const work of this.listWorks()) {
        const current = this.membership(work.id, agent.profile.id);
        const desired = legacy?.workId === work.id ? legacy : null;
        if (!!current.binding === !!desired && (!desired || current.binding?.role === desired.role)) continue;
        await this.appendEvent(work.id, {
          id: crypto.randomUUID(), workId: work.id, createdAt: Date.now(), actor: { kind: "system", id: "migration" },
          membershipOperationId: `v2:${agent.profile.id}:${work.id}`, agentId: agent.profile.id,
          membershipRevision: current.revision + 1,
          ...(desired ? { type: "member.attached", role: desired.role } : { type: "member.detached" })
        });
      }
    }
    await writeJsonAtomic(marker, { version: 2 });
  }

  private worksRoot(): string {
    return path.join(this.dataDir, "works");
  }

  workDir(id: string): string {
    return path.join(this.worksRoot(), id);
  }

  timelineFile(id: string): string {
    return path.join(this.workDir(id), "timeline.jsonl");
  }

  async createWork(profile: WorkProfile): Promise<WorkProfile> {
    if (this.works.has(profile.id)) throw new Error(`Work ${profile.id} already exists`);
    const parsed = WorkProfile.parse(profile);
    await mkdir(this.workDir(parsed.id), { recursive: true });
    await writeJsonAtomic(path.join(this.workDir(parsed.id), "profile.json"), parsed);
    await writeJsonAtomic(path.join(this.workDir(parsed.id), "catalog.json"), EMPTY_WORK_CATALOG);
    await writeJsonAtomic(path.join(this.workDir(parsed.id), "runtime-version.json"), { version: 2 });
    this.works.set(parsed.id, {
      profile: parsed,
      lastSeq: 0,
      lastActivityAt: parsed.createdAt
    });
    return parsed;
  }

  listWorks(): WorkProfile[] {
    return [...this.works.values()]
      .sort((a, b) => b.lastActivityAt - a.lastActivityAt)
      .map((record) => record.profile);
  }

  getWork(id: string): WorkProfile {
    return this.requireWork(id).profile;
  }

  async updateWork(id: string, patch: Partial<Pick<WorkProfile, "name" | "description" | "projectRoot" | "workspaceId" | "kind">>): Promise<WorkProfile> {
    return this.chain(id, async () => {
    const current = this.requireWork(id);
    const profile = WorkProfile.parse({ ...current.profile, ...patch, id: current.profile.id });
    await writeJsonAtomic(path.join(this.workDir(id), "profile.json"), profile);
    this.works.set(id, { ...current, profile });
    return profile;
    });
  }

  requireWork(id: string): WorkRecord {
    const record = this.works.get(id);
    if (!record) throw new RpcError(HostErrorCode.WORK_NOT_FOUND, `Work ${id} not found`);
    return record;
  }

  async readCatalog(id: string): Promise<WorkCatalog> {
    this.requireWork(id);
    return (
      (await readJson(path.join(this.workDir(id), "catalog.json"), WorkCatalog)) ??
      structuredClone(EMPTY_WORK_CATALOG)
    );
  }

  updateCatalog(
    id: string,
    expectedRevision: number,
    update: (catalog: WorkCatalog) => WorkCatalog
  ): Promise<WorkCatalog> {
    return this.chain(id, async () => {
      const current = await this.readCatalog(id);
      if (current.revision !== expectedRevision) {
        throw new RpcError(
          HostErrorCode.WORK_CONFLICT,
          `Work catalog revision is ${current.revision}, expected ${expectedRevision}`
        );
      }
      const next = WorkCatalog.parse(update(structuredClone(current)));
      if (next.revision !== current.revision + 1) {
        throw new Error("Catalog update must advance revision by one");
      }
      await writeJsonAtomic(path.join(this.workDir(id), "catalog.json"), next);
      return next;
    });
  }

  appendEvent(id: string, draft: WorkEventDraft, expected?: { taskId: string; revision: number }): Promise<WorkEvent> {
    return this.chain(id, async () => {
      const record = this.requireWork(id);
      const events = await this.readTimelineFile(id);
      if ((events.at(-1)?.seq ?? 0) !== record.lastSeq) throw new Error("Invalid room commit boundary; reopen the store before writing");
      if (draft.clientEventId || expected) {
        const duplicate = draft.clientEventId ? events.find((event) => event.clientEventId === draft.clientEventId) : undefined;
        if (duplicate) {
          const content = (event: WorkEventDraft | WorkEvent) => {
            const { id: _id, createdAt: _at, ...rest } = event;
            const body = { ...rest } as Record<string, unknown>;
            delete body.seq; delete body.messageId;
            return JSON.parse(JSON.stringify(body));
          };
          if (!isDeepStrictEqual(content(duplicate), content(draft))) throw new RpcError(HostErrorCode.WORK_CONFLICT, "Request identity conflicts with previously committed content");
          return duplicate;
        }
        if (expected && projectWork(events).tasks.find((task) => task.id === expected.taskId)?.revision !== expected.revision) {
          throw new RpcError(HostErrorCode.WORK_CONFLICT, "Task revision changed; read the task and retry");
        }
      }
      if ((draft.type === "member.attached" || draft.type === "member.detached") && draft.membershipRevision !== this.membership(id, draft.agentId).revision + 1) {
        throw new RpcError(HostErrorCode.WORK_CONFLICT, "Membership revision changed; refresh and retry");
      }
      if (draft.workId !== id) throw new Error(`Work event ${draft.id} belongs to ${draft.workId}, not ${id}`);
      const event = WorkEvent.parse({ ...draft, seq: record.lastSeq + 1 });
      await mkdir(this.workDir(id), { recursive: true });
      const handle = await open(this.timelineFile(id), "a");
      try {
        await handle.writeFile(`${JSON.stringify(event)}\n`);
        await handle.sync();
      } finally {
        await handle.close();
      }
      this.projectMembership(event);
      this.works.set(id, {
        ...record,
        lastSeq: event.seq,
        lastActivityAt: Math.max(record.lastActivityAt, event.createdAt)
      });
      return event;
    });
  }

  readTimeline(id: string): Promise<WorkEvent[]> {
    // A reader must not observe a partially written append or a not-yet-synced head.
    return this.chain(id, () => this.readTimelineFile(id));
  }

  private async readTimelineFile(id: string): Promise<WorkEvent[]> {
    let raw: string;
    try { raw = await readFile(this.timelineFile(id), "utf8"); }
    catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return []; throw error; }
    if (raw && !raw.endsWith("\n")) throw new Error(`Corrupt room ${id}: unterminated log record; restart for tail recovery`);
    const events: WorkEvent[] = [];
    for (const line of raw.split("\n").slice(0, -1)) {
      const event = parseWorkEvent(line);
      if (!event || event.workId !== id || event.seq !== events.length + 1) throw new Error(`Corrupt room ${id}: invalid record at sequence ${events.length + 1}`);
      events.push(event);
    }
    return events;
  }

  /** 侧栏摘要：work 的最近动态时间与最近一条群聊消息。work 数量少，整读即可。 */
  async readActivity(id: string): Promise<{ lastActivityAt: number; preview?: string }> {
    let lastActivityAt = 0;
    let preview: string | undefined;
    for (const event of await this.readTimeline(id)) {
      lastActivityAt = Math.max(lastActivityAt, event.createdAt);
      if (event.type === "chat.posted" || (event.type === "task.handed_off" && event.messageId)) {
        const text = (event.type === "chat.posted" ? event.body : event.summary).replace(/\s+/g, " ").trim().slice(0, 160);
        if (text) preview = text;
      }
    }
    return { lastActivityAt, ...(preview ? { preview } : {}) };
  }

  private chain<T>(id: string, work: () => Promise<T>): Promise<T> {
    const previous = this.appendChains.get(id) ?? Promise.resolve();
    const current = previous.catch(() => undefined).then(work);
    this.appendChains.set(id, current.then(() => undefined, () => undefined));
    return current;
  }
}

/** Work timeline 是唯一事实；任务轨道和公共聊天室都只是它的 fold。 */
export function projectWork(events: WorkEvent[]): WorkProjection {
  const tasks = new Map<string, WorkTask>();
  const chat: WorkChatMessage[] = [];

  for (const event of [...events].sort((a, b) => a.seq - b.seq)) {
    if (event.type === "chat.posted") {
      chat.push(event);
      continue;
    }
    if (event.type === "task.created") {
      if (!tasks.has(event.task.id)) tasks.set(event.task.id, { ...structuredClone(event.task), ...(event.actor.kind === "agent" ? { ownerAgentId: event.actor.id } : {}) });
      continue;
    }
    if (event.type === "task.claimed") {
      const task = tasks.get(event.taskId);
      if (!task || event.revision <= task.revision) continue;
      const { blocker: _blocker, ...rest } = task;
      tasks.set(event.taskId, { ...rest, assigneeIds: event.assigneeIds, state: "in_progress", revision: event.revision, updatedAt: event.createdAt });
      chat.push({ ...event, type: "chat.posted", mentionedAgentIds: [] });
      continue;
    }
    if (event.type === "task.assigned") {
      const task = tasks.get(event.taskId);
      if (!task || event.revision <= task.revision) continue;
      tasks.set(event.taskId, {
        ...task,
        assigneeIds: [...event.assigneeIds],
        revision: event.revision,
        updatedAt: event.createdAt
      });
      continue;
    }
    if (event.type === "task.delegated") {
      const task = tasks.get(event.taskId);
      if (!task || event.revision <= task.revision) continue;
      tasks.set(event.taskId, { ...task, state: "in_progress", assigneeIds: [...new Set([...task.assigneeIds, event.agentId])], revision: event.revision, updatedAt: event.createdAt });
      chat.push({ ...event, type: "chat.posted", body: `Worker assigned: ${event.agentId}\n${event.instruction}`, mentionedAgentIds: [] });
      continue;
    }
    if (event.type === "task.transitioned") {
      const task = tasks.get(event.taskId);
      if (!task || task.state !== event.from || event.revision <= task.revision) continue;
      chat.push({ ...event, type: "chat.posted", messageId: event.id, body: `Card ${task.title}: ${event.from} → ${event.to}${event.blocker ? `\n${event.blocker.reason}` : ""}`, mentionedAgentIds: [] });
      const { blocker: _previousBlocker, ...withoutBlocker } = task;
      tasks.set(event.taskId, {
        ...withoutBlocker,
        state: event.to,
        revision: event.revision,
        updatedAt: event.createdAt,
        ...(event.to === "blocked" && event.blocker
          ? { blocker: { ...event.blocker, createdAt: event.createdAt } }
          : {})
      });
      continue;
    }
    if (event.type === "task.handed_off") {
      if (event.messageId) chat.push({
        ...event, type: "chat.posted", messageId: event.messageId,
        body: event.blockerReason ? `${event.summary}\n\nBlocked: ${event.blockerReason}` : event.summary,
        mentionedAgentIds: [], taskId: event.taskId
      });
      const task = tasks.get(event.taskId);
      if (!task || event.revision <= task.revision) continue;
      const { blocker: _previousBlocker, ...withoutBlocker } = task;
      tasks.set(event.taskId, {
        ...withoutBlocker,
        state: event.nextStatus,
        revision: event.revision,
        deliverables: [...task.deliverables, ...event.deliverables],
        updatedAt: event.createdAt,
        ...(event.nextStatus === "blocked" && event.blockerReason
          ? { blocker: { reason: event.blockerReason, ownerId: event.actor.kind === "agent" ? event.actor.id : undefined, createdAt: event.createdAt } }
          : {})
      });
    }
  }

  return { tasks: [...tasks.values()], chat };
}

function parseWorkEvent(line: string): WorkEvent | null {
  try {
    return WorkEvent.parse(JSON.parse(line));
  } catch {
    return null;
  }
}

async function repairFinalLine(file: string): Promise<void> {
  let raw: string;
  try {
    raw = await readFile(file, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
    throw error;
  }
  if (!raw || raw.endsWith("\n")) return;
  const lastBreak = raw.lastIndexOf("\n");
  const tail = raw.slice(lastBreak + 1);
  const repaired = parseWorkEvent(tail) ? `${raw}\n` : raw.slice(0, lastBreak + 1);
  await writeFile(`${file}.recovery-${crypto.randomUUID()}.bak`, raw);
  const handle = await open(file, "w");
  try { await handle.writeFile(repaired); await handle.sync(); } finally { await handle.close(); }
}

async function readJson<T>(
  file: string,
  schema: { parse(value: unknown): T }
): Promise<T | null> {
  try {
    return schema.parse(JSON.parse(await readFile(file, "utf8")));
  } catch {
    return null;
  }
}

async function writeJsonAtomic(file: string, value: unknown): Promise<void> {
  await mkdir(path.dirname(file), { recursive: true });
  const temporary = `${file}.${crypto.randomUUID()}.tmp`;
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`);
  await rename(temporary, file);
}
