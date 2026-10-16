import { summarizePrefix } from "./compaction.js";
import { discussionResponders, runDiscussion, isPass, discussionLimits } from "./room-discussion.js";
import { workIntent, currentCardSource, pendingCardDelegation } from "./work-execution.js";
import { selectRoomInput } from "./room-context.js";
import { SessionStore } from "./session-store.js";
import type { TranscriptDraft, WorkSendMessageParams, CreateTaskParams, ClaimTaskParams, ReadTaskParams, WorkActor } from "@nuum/protocol";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { homedir, platform, release } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import {
  DEFAULT_AGENT_NAME,
  DelegatedToolNames,
  type DelegateWorkParams,
  HostErrorCode,
  HostEvents,
  RpcError,
  appendAssistantDelta,
  appendAssistantToolCall,
  describeWake,
  projectAgent,
  resolveAvailableModel,
  type AgentCreateParams,
  type AgentRuntime as AgentRuntimeView,
  type AgentSettings,
  type AgentUpdateParams,
  type AgentView,
  type AssistantPart,
  type CheckAgentParams,
  type CreateAgentParams,
  type LocalToolAction,
  type ReadAgentTranscriptParams,
  type ReadWorkTimelineParams,
  type RunWorkCliParams,
  type SendMessageParams,
  type SendToAgentParams,
  type Settings,
  type StopAgentParams,
  type HandoffTaskParams,
  type PostToWorkParams,
  type UpdateAgentParams,
  type SettingsSetParams,
  type ToolDefinition,
  type ToolApproval,
  type ToolPermission,
  type ToolResolution,
  type UpdateStateParams,
  type TranscriptEvent,
  type WorkCatalog,
  type WorkCatalogAddParams,
  type WorkCatalogEntry,
  type WorkCatalogRemoveParams,
  type WorkCreateParams,
  type WorkDispatchParams,
  type WorkEvent,
  type WorkMemberAttachParams,
  type WorkMemberDetachParams,
  type WorkMemberMoveParams,
  type WorkPostMessageParams,
  type WorkProfile,
  type WorkListItem,
  type WorkRole,
  type WorkSnapshot,
  type WorkTask,
  type WorkTaskAssignParams,
  type WorkTaskCreateParams,
  type WorkTaskTransitionParams,
  type WorkTaskView,
  type WorkUpdateParams
} from "@nuum/protocol";
import { ProactiveService } from "./proactive.js";
import { AgentStore, type AgentRecord } from "./agent-store.js";
import {
  COMPACTION_PROMPT,
  assembleContext,
  describeOutbound,
  deriveName,
  estimateContextTokens,
  partitionForCompaction
} from "./context.js";
import {
  createDelegatedTools,
  delegatedToolsForRunContext,
  isDelegatedToolAvailable,
  type DelegateHost,
  type DelegatedTool,
  type DelegatedToolContext
} from "./delegated-tools.js";
import { spawnKernelClient, type KernelClient } from "./kernel-client.js";
import {
  EXTRACTION_PROMPT,
  MemoryStore,
  isMemorableExchange,
  parseExtraction,
  renderMemory
} from "./memory.js";
import { resolveSessionModel } from "./model.js";
import type { ExpertPort } from "./ports.js";
import { precheck } from "./precheck.js";
import {
  profileDriftNotice,
  renderAgentDirectory,
  renderCompactNotice,
  renderSystemPrompt,
  type AgentIdentity
} from "./prompt.js";
import { DIRECT_RUN_CONTEXT, type RunContext } from "./run-context.js";
import { AgentScheduler, DEFAULT_MAX_CONCURRENT_RUNS, type SubmittedRun } from "./scheduler.js";
import { MAX_AGENTS, WakeQueue, currentHops, pendingWake } from "./wake.js";
import { WorkStore, projectWork } from "./work-store.js";
import { allowedTaskTransitions, assertTaskTransition } from "./work-task-policy.js";

/**
 * 往回扫多少条找上一条 user / wake。一个 turn 里工具事件可以很多，但不会多到
 * 这个量级；真扫不到说明这条转录里根本没有唤醒链，当 0 手是对的。
 */
const HOPS_SCAN_LIMIT = 200;
const execFileAsync = promisify(execFile);

export type { DelegatedTool };

export interface HostRuntimeOptions {
  dataDir: string;
  kernelCommand: string;
  kernelArgs: string[];
  expert?: ExpertPort | null;
  delegatedTools?: DelegatedTool[];
  maxConcurrentRuns?: number;
  /** 测试接缝；产品按模型表取窗口。 */
  contextWindowTokens?: number;
  /** 测试用的接缝：换掉真 Kernel 进程，才能在单测里驱动事件回路。 */
  spawnKernel?: (command: string, args: string[]) => KernelClient;
}

export class HostRuntime implements Partial<DelegateHost> {
  readonly store: AgentStore;
  readonly workStore: WorkStore;
  readonly sessions: SessionStore;
  readonly scheduler: AgentScheduler;
  readonly proactive: ProactiveService;
  private settings!: Settings;
  private kernel: KernelClient | null = null;
  /** 运行态只活在内存里 —— 进程重启后一律回到 idle，磁盘上不存在假 running。 */
  private readonly errored = new Set<string>();
  private readonly buffers = new Map<string, {
    messageId: string;
    parts: AssistantPart[];
    flushed?: boolean;
  }>();
  private readonly pendingTools = new Map<string, ToolApproval>();
  private readonly pendingByAgent = new Map<string, Set<string>>();
  /** 本轮已记进 assistant 事件的 toolCallId，防止 pending → started 重复记。 */
  private readonly recordedCalls = new Map<string, Set<string>>();
  /** toolCallId 只是调用号；落盘时再带上 assistantId，投影不需靠相邻顺序猜归属。 */
  private readonly callOrigins = new Map<string, Map<string, string>>();
  /** Kernel 通知是 fire-and-forget；同一 run 必须串行投影，不同 agent 仍可并行。 */
  private readonly kernelEventChains = new Map<string, Promise<void>>();
  private readonly delegated = new Map<string, DelegatedTool>();
  /** 在跑的后台任务（记忆抽取、压缩、唤醒重放），dispose 时要等它们收尾。 */
  private readonly pending = new Set<Promise<unknown>>();
  private readonly wakes = new WakeQueue();
  private emit: (method: string, params: unknown) => void = () => undefined;
  private readonly toolCache: ToolDefinition[] = [];

  constructor(private readonly options: HostRuntimeOptions) {
    this.store = new AgentStore(options.dataDir);
    this.workStore = new WorkStore(options.dataDir);
    this.sessions = new SessionStore(options.dataDir);
    this.proactive = new ProactiveService(this.store, () => this.settings.defaultModel, (agentId) => {
      if (agentId && this.store.getAgent(agentId)) this.background(this.viewFor(this.store.requireAgent(agentId)).then((agent) => this.emit(HostEvents.agentUpdated, { agent })));
      this.emit(HostEvents.proactiveUpdated, {});
    });
    this.scheduler = new AgentScheduler(options.maxConcurrentRuns ?? DEFAULT_MAX_CONCURRENT_RUNS);
    // 产品工具（§5.2）由 runtime 自己装：它们的副作用全在 runtime 上，没有
    // 别处能提供。options.delegatedTools 留给测试往里塞额外的桩。
    for (const tool of [...createDelegatedTools(this), ...(options.delegatedTools ?? [])]) {
      this.delegated.set(tool.definition.name, tool);
    }
  }

  setEmitter(emit: (method: string, params: unknown) => void): void {
    this.emit = emit;
  }

  async start(): Promise<void> {
    await this.store.init();
    await this.workStore.init();
    await this.workStore.migrateMemberships(this.store.listAgents());
    await this.workStore.migrateExecutionHistory();
    this.settings = await this.store.readSettings();
    this.attachKernel();
    this.proactive.start();
    // 重放放最后：它要 kernel 在位，而且不该拖慢 RPC 上线。
    this.background(this.replayPendingWakes());
    this.background(this.replayWorkDispatches());
  }

  async dispose(): Promise<void> {
    this.disposing = true;
    this.scheduler.close();
    const summaryRuns = [...this.compactJobs.keys()];
    this.compactJobs.clear();
    await Promise.allSettled(summaryRuns.map(runId => this.kernel?.cancelSummary?.(`${runId}:compact`)));
    await this.proactive.dispose();
    await Promise.allSettled([...this.pending, ...this.kernelEventChains.values()]);
    this.kernel?.dispose();
    this.kernel = null;
    await this.store.dispose();
  }

  private attachKernel(): void {
    this.kernel?.dispose();
    const spawn = this.options.spawnKernel ?? spawnKernelClient;
    const client = spawn(this.options.kernelCommand, this.options.kernelArgs);
    this.kernel = client;
    client.onEvent((method, params) => this.enqueueKernelEvent(method, params));
    client.onExit?.(() => {
      if (this.disposing || this.kernel !== client) return;
      this.kernel = null;
      this.scheduler.close();
      this.emit(HostEvents.kernelDown, { at: Date.now() });
    });
    void client.hello().catch(() => {
      if (this.kernel !== client || this.disposing) return;
      this.kernel = null;
      this.emit(HostEvents.kernelDown, { at: Date.now() });
    });
    void client.tools().then((list) => {
      if (Array.isArray(list)) {
        this.toolCache.splice(0, this.toolCache.length, ...(list as ToolDefinition[]));
      }
    }).catch(() => { /* Kernel exit is reported by the lifecycle handler. */ });
  }

  getPublicSettings() {
    return this.store.publicSettings(this.settings);
  }

  async setSettings(patch: SettingsSetParams): Promise<ReturnType<AgentStore["publicSettings"]>> {
    if (patch.openaiApiKey !== undefined) {
      this.store.secrets.openaiApiKey = patch.openaiApiKey ?? undefined;
    }
    if (patch.anthropicApiKey !== undefined) {
      this.store.secrets.anthropicApiKey = patch.anthropicApiKey ?? undefined;
    }
    if (patch.deepseekApiKey !== undefined) {
      this.store.secrets.deepseekApiKey = patch.deepseekApiKey ?? undefined;
    }
    const requestedModel = patch.defaultModel ?? this.settings.defaultModel;
    this.settings = {
      ...this.settings,
      defaultToolPermission: patch.defaultToolPermission ?? this.settings.defaultToolPermission,
      defaultModel: resolveAvailableModel(this.store.secrets, requestedModel) ?? requestedModel,
      theme: patch.theme ?? this.settings.theme,
      language: patch.language ?? this.settings.language ?? "zh-CN",
      ...(patch.sidebar !== undefined ? { sidebar: patch.sidebar } : {})
    };
    await this.store.writeSettings(this.settings);
    this.emit(HostEvents.settingsUpdated, this.getPublicSettings());
    return this.getPublicSettings();
  }

  // ── agent 生命周期 ──────────────────────────────────────────────────────

  async createAgent(params: AgentCreateParams = {}): Promise<AgentView> {
    const now = Date.now();
    const settings: AgentSettings = {
      model:
        params.model ??
        resolveAvailableModel(this.store.secrets, this.settings.defaultModel) ??
        this.settings.defaultModel,
      workspace: params.workspace ?? { projectRoot: null, toolPermission: null }
    };
    const record = await this.store.createAgent(
      {
        id: crypto.randomUUID(),
        name: params.name?.trim() || DEFAULT_AGENT_NAME,
        description: params.description?.trim() ?? "",
        ...(params.tags !== undefined ? { tags: params.tags } : {}),
        ...(params.avatarColor ? { avatarColor: params.avatarColor } : {}),
        ...(params.avatarShape ? { avatarShape: params.avatarShape } : {}),
        ...(params.avatarMaterial ? { avatarMaterial: params.avatarMaterial } : {}),
        createdAt: now
      },
      settings
    );
    const view = await this.viewFor(record);
    this.emit(HostEvents.agentUpdated, { agent: view });
    return view;
  }

  async listAgents(): Promise<AgentView[]> {
    return Promise.all(this.store.listAgents().map((record) => this.viewFor(record)));
  }

  async getAgent(id: string) {
    const record = this.store.requireAgent(id);
    // UI 明确要完整时间线；模型热路径走 readForAssemble，不再全量读。
    const events = await this.store.readTranscript(id);
    const live = this.liveFor(id);
    await this.store.markRead(id);
    return {
      view: await this.viewFor(record),
      events,
      blocks: projectAgent(events, live).blocks,
      live
    };
  }

  async updateAgent(params: AgentUpdateParams): Promise<AgentView> {
    const profile: Record<string, unknown> = {};
    if (params.name !== undefined) profile.name = params.name;
    if (params.description !== undefined) profile.description = params.description;
    if (params.tags !== undefined) profile.tags = params.tags;
    if (params.avatarColor !== undefined) profile.avatarColor = params.avatarColor;
    if (params.avatarShape !== undefined) profile.avatarShape = params.avatarShape;
    if (params.avatarMaterial !== undefined) profile.avatarMaterial = params.avatarMaterial;
    const settings: Record<string, unknown> = {};
    if (params.model !== undefined) settings.model = params.model;
    if (params.workspace !== undefined) settings.workspace = params.workspace;
    if (params.hiddenFromSidebar !== undefined) settings.hiddenFromSidebar = params.hiddenFromSidebar;
    const record = await this.store.updateAgent(params.id, {
      ...(Object.keys(profile).length ? { profile } : {}),
      ...(Object.keys(settings).length ? { settings } : {})
    });
    const view = await this.viewFor(record);
    this.emit(HostEvents.agentUpdated, { agent: view });
    return view;
  }

  async deleteAgent(id: string): Promise<{ ok: true }> {
    await this.cancel(id);
    const cleanup = this.kernel
      ?.disposeShell(path.join(this.store.agentDir(id), "terminals"))
      .then(() => undefined, () => undefined);
    if (cleanup) await settleWithin(cleanup, 500);
    this.wakes.drop(id);
    this.errored.delete(id);
    this.buffers.delete(id);
    this.recordedCalls.delete(id);
    this.callOrigins.delete(id);
    this.clearAgentPending(id);
    await this.proactive.forget(id);
    await this.store.deleteAgent(id);
    this.emit(HostEvents.proactiveUpdated, {});
    return { ok: true };
  }

  async getTranscript(id: string, beforeSeq?: number, limit?: number) {
    this.store.requireAgent(id);
    const page = await this.store.readTranscriptPage(id, beforeSeq, limit);
    return { id, ...page };
  }

  // ── Work 生命周期与投影 ─────────────────────────────────────────────────

  async createWork(params: WorkCreateParams): Promise<WorkProfile> {
    const profile = await this.workStore.createWork({
      id: crypto.randomUUID(),
      kind: params.kind ?? "work",
      name: params.name.trim(),
      description: params.description.trim(),
      projectRoot: params.projectRoot ? path.resolve(params.projectRoot) : null,
      createdAt: Date.now()
    });
    this.emit(HostEvents.workUpdated, { work: profile });
    return profile;
  }

  async listWorks(): Promise<WorkListItem[]> {
    // 成员不在 list 里：UI 依据 agents 的 workMembership 现场归组，避免两份真源。
    return Promise.all(this.workStore.listWorks().map(async (profile) => {
      const activity = await this.workStore.readActivity(profile.id);
      return {
        ...profile,
        lastActivityAt: Math.max(activity.lastActivityAt, profile.createdAt),
        ...(activity.preview ? { preview: activity.preview } : {})
      };
    }));
  }

  async updateWork(params: WorkUpdateParams): Promise<WorkProfile> {
    const profile = await this.workStore.updateWork(params.id, {
      ...(params.kind ? { kind: params.kind } : {}),
      ...(params.name !== undefined ? { name: params.name.trim() } : {}),
      ...(params.description !== undefined ? { description: params.description.trim() } : {}),
      ...(params.projectRoot !== undefined
        ? { projectRoot: params.projectRoot ? path.resolve(params.projectRoot) : null }
        : {})
    });
    this.emit(HostEvents.workUpdated, { work: profile });
    return profile;
  }

  async getWork(id: string): Promise<WorkSnapshot> {
    const profile = this.workStore.getWork(id);
    const [catalog, events] = await Promise.all([
      this.workStore.readCatalog(id),
      this.workStore.readTimeline(id)
    ]);
    const projection = projectWork(events);
    const members = await Promise.all(
      this.store
        .listAgents()
        .filter((record) => Boolean(this.workStore.membership(id, record.profile.id).binding))
        .map((record) => this.viewFor(record, id))
    );
    return {
      profile,
      members,
      catalog,
      events,
      throughSeq: events.at(-1)?.seq ?? 0,
      discussionRunning: !!this.discussions.get(id) && !this.discussions.get(id)!.stopped,
      interruptions: this.workInterruptions(events),
      tasks: projection.tasks.map((task) => this.workTaskView(task)),
      chat: projection.chat
    };
  }

  async postWorkMessage(params: WorkPostMessageParams) {
    return this.inRoom(params.workId, async () => {
    this.workStore.requireWork(params.workId);
    if (params.inputAfterSeq !== undefined && params.inputAfterSeq > ((await this.workStore.readTimeline(params.workId)).at(-1)?.seq ?? 0)) throw new Error("Invalid room history start sequence");
    if (params.clientEventId) {
      const previous = (await this.workStore.readTimeline(params.workId)).find(event => event.clientEventId === params.clientEventId);
      if (previous) {
        if (previous.type !== "chat.posted" || previous.body !== params.body.trim() || JSON.stringify(previous.mentionedAgentIds) !== JSON.stringify(params.mentionedAgentIds) || previous.inputAfterSeq !== params.inputAfterSeq) throw new Error("Message retry conflicts with the original request");
        return previous;
      }
    }
    const event = await this.workStore.appendEvent(params.workId, {
      type: "chat.posted",
      id: crypto.randomUUID(),
      workId: params.workId,
      createdAt: Date.now(),
      actor: { kind: "user", id: "local-user" },
      messageId: crypto.randomUUID(),
      body: params.body.trim(),
      clientEventId: params.clientEventId,
      inputAfterSeq: params.inputAfterSeq,
      mentionedAgentIds: params.mentionedAgentIds
    });
    this.emit(HostEvents.workEventAppended, { workId: params.workId, event });
    this.enqueueDiscussion(event);
    return event;
    });
  }

  private readonly discussionQueues = new Map<string, WorkEvent[]>();
  private readonly discussionDrivers = new Map<string, Promise<void>>();
  private readonly discussions = new Map<string, {
    id: string; stopped: boolean; superseded: boolean; total: number; hasStarted: boolean; triggers: WorkEvent[];
    perExecution: Map<string, number>; replies: { body: string; mentionedAgentIds: string[] }[];
    runId?: string;
  }>();
  private readonly submittedWork = new Map<string, SubmittedRun>();
  private readonly cancelledExecutions = new Set<string>();

  private enqueueDiscussion(event: WorkEvent): void {
    if (this.disposing || event.type !== "chat.posted" || event.actor.kind !== "user") return;
    const queue = this.discussionQueues.get(event.workId) ?? [];
    if (!queue.some(item => item.id === event.id)) queue.push(event);
    this.discussionQueues.set(event.workId, queue);
    const current = this.discussions.get(event.workId);
    if (current) {
      if (!current.hasStarted) {
        for (const trigger of [...current.triggers].reverse()) if (!queue.some(item => item.id === trigger.id)) queue.unshift(trigger);
      }
      current.superseded = true;
      if (current.runId) this.scheduler.cancelQueued(current.runId);
    }
    if (this.discussionDrivers.has(event.workId)) return;
    const driver = this.runRoomDiscussions(event.workId).finally(() => {
      this.discussionDrivers.delete(event.workId);
      const next = this.discussionQueues.get(event.workId)?.[0];
      if (next && !this.disposing) this.enqueueDiscussion(next);
    });
    this.discussionDrivers.set(event.workId, driver);
    this.background(driver);
  }

  private async runRoomDiscussions(workId: string): Promise<void> {
    while (!this.disposing && this.discussionQueues.get(workId)?.length) {
      const triggers = this.discussionQueues.get(workId)!.splice(0);
      const id = crypto.randomUUID();
      const inputAfterSeq = triggers.reduce<number | undefined>((value, event) => event.type === "chat.posted" && event.inputAfterSeq !== undefined ? Math.max(value ?? 0, event.inputAfterSeq) : value, undefined);
      const live = { id, stopped: false, superseded: false, total: 0, hasStarted: false, triggers, perExecution: new Map<string, number>(), replies: [] as { body: string; mentionedAgentIds: string[] }[], runId: undefined as string | undefined };
      let hadFailure = false;
      let discussionError: string | undefined;
      this.discussions.set(workId, live);
      const start = await this.appendWorkEvent(workId, {
        type: "discussion.started", id, workId, createdAt: Date.now(), actor: { kind: "system", id: "host" }, triggerEventIds: triggers.map(event => event.id)
      });
      const membershipEvents = await this.workStore.readTimeline(workId);
      const memberIds = [...new Set(membershipEvents.filter(event => event.type === "member.attached").map(event => event.agentId))];
      const members = memberIds.flatMap(agentId => {
        const agent = this.store.getAgent(agentId);
        return agent && this.workStore.membership(workId, agentId).binding?.grants.canPost ? [{ id: agentId, name: agent.profile.name }] : [];
      });
      try {
        await runDiscussion({
          current: () => !this.disposing && !live.stopped && !live.superseded,
          responders: async () => discussionResponders(members, [
            ...triggers.filter((event): event is Extract<WorkEvent, { type: "chat.posted" }> => event.type === "chat.posted"), ...live.replies
          ]).map(member => member.id),
          runMember: async agentId => {
            if (!this.workStore.membership(workId, agentId).binding?.grants.canPost) return { messages: 0 };
            const before = live.total;
            try {
              const submitted = await this.scheduleWork({ workId, agentId, instruction: `Discuss the user's messages ${triggers.map(event => event.id).join(", ")}. Use SendMessage for at most two short replies; remain silent or send (pass) if you have nothing useful to add.` },
                { kind: "user", id: "local-user" }, start.id, crypto.randomUUID(), id, inputAfterSeq);
              live.runId = submitted.runId;
              if (live.superseded || live.stopped) this.scheduler.cancelQueued(submitted.runId);
              const status = await submitted.completed;
              live.runId = undefined;
              hadFailure ||= status !== "completed" && !live.stopped && !live.superseded;
              return { messages: live.total - before, failed: status === "failed" };
            } catch (error) {
              hadFailure = true;
              this.emit(HostEvents.agentError, { agentId, message: String(error) });
              return { messages: live.total - before, failed: true };
            }
          }
        });
      } catch (error) {
        hadFailure = true;
        discussionError = error instanceof Error ? error.message : String(error);
      } finally {
        this.discussions.delete(workId);
        if (!this.disposing) await this.endDiscussion(workId, id, live.stopped ? "cancelled" : hadFailure && !live.superseded ? "interrupted" : "completed", discussionError);
      }
    }
  }

  private async endDiscussion(workId: string, discussionId: string, status: "completed" | "cancelled" | "interrupted", error?: string) {
    await this.inRoom(workId, async () => {
      const events = await this.workStore.readTimeline(workId);
      if (events.some(event => event.type === "discussion.finished" && event.discussionId === discussionId)) return;
      await this.appendWorkEvent(workId, { type: "discussion.finished", id: `end:${discussionId}`, clientEventId: `end:${discussionId}`,
        workId, createdAt: Date.now(), actor: { kind: "system", id: "host" }, discussionId, status, error });
    });
  }

  async stopWorkDiscussion(workId: string): Promise<{ ok: true }> {
    this.workStore.requireWork(workId);
    const live = this.discussions.get(workId);
    if (live) live.stopped = true;
    const queued = this.discussionQueues.get(workId)?.splice(0) ?? [];
    if (queued.length) {
      const start = await this.appendWorkEvent(workId, { type: "discussion.started", id: crypto.randomUUID(), workId, createdAt: Date.now(), actor: { kind: "user", id: "local-user" }, triggerEventIds: queued.map(event => event.id) });
      await this.endDiscussion(workId, start.id, "cancelled");
    }
    if (!live) return { ok: true };
    await this.endDiscussion(workId, live.id, "cancelled");
    if (live.runId) {
      const context = this.scheduler.contextFor(live.runId);
      if (context?.kind === "work" && context.bridgeId) this.cancelledExecutions.add(context.bridgeId);
      if (!this.scheduler.cancelQueued(live.runId)) await this.kernel?.cancel(live.runId);
    }
    return { ok: true };
  }

  private async appendWorkEvent(workId: string, draft: import("@nuum/protocol").WorkEventDraft) {
    const event = await this.workStore.appendEvent(workId, draft);
    this.emit(HostEvents.workEventAppended, { workId, event });
    return event;
  }

  async attachWorkMember(params: WorkMemberAttachParams): Promise<AgentView> {
    this.workStore.requireWork(params.workId);
    const record = this.store.requireAgent(params.agentId);
    const membership = this.workStore.membership(params.workId, params.agentId);
    this.assertMembershipRevision(membership.revision, params.expectedRevision);
    if (membership.binding) throw new RpcError(HostErrorCode.WORK_CONFLICT, "Already a member of this room");
    const event = await this.workStore.appendEvent(params.workId, {
      type: "member.attached", id: crypto.randomUUID(), workId: params.workId, createdAt: Date.now(),
      actor: { kind: "user", id: "local-user" }, membershipOperationId: crypto.randomUUID(),
      agentId: params.agentId, role: params.role, membershipRevision: membership.revision + 1
    });
    const view = await this.viewFor(record);
    this.emit(HostEvents.agentUpdated, { agent: view });
    this.emit(HostEvents.workEventAppended, { workId: params.workId, event });
    this.emit(HostEvents.workUpdated, { work: this.workStore.getWork(params.workId) });
    return view;
  }

  async detachWorkMember(params: WorkMemberDetachParams): Promise<AgentView> {
    const record = this.store.requireAgent(params.agentId);
    const membership = this.workStore.membership(params.workId, params.agentId);
    this.assertMembershipRevision(membership.revision, params.expectedRevision);
    if (!membership.binding) throw new RpcError(HostErrorCode.WORK_CONFLICT, "Not a member of this room");
    this.assertNotRunningWork(params.agentId, params.workId);
    const event = await this.workStore.appendEvent(params.workId, {
      type: "member.detached", id: crypto.randomUUID(), workId: params.workId, createdAt: Date.now(),
      actor: { kind: "user", id: "local-user" }, membershipOperationId: crypto.randomUUID(),
      agentId: params.agentId, membershipRevision: membership.revision + 1
    });
    const view = await this.viewFor(record);
    this.emit(HostEvents.agentUpdated, { agent: view });
    this.emit(HostEvents.workEventAppended, { workId: params.workId, event });
    this.emit(HostEvents.workUpdated, { work: this.workStore.getWork(params.workId) });
    return view;
  }

  async moveWorkMember(_params: WorkMemberMoveParams): Promise<AgentView> {
    throw new RpcError(HostErrorCode.WORK_CONFLICT, "Rooms now have independent membership. Attach to the new room, then explicitly remove from the old room.");
  }

  async getWorkTaskTranscript(params: { workId: string; taskId: string; sessionId?: string; beforeSeq?: number }) {
    await this.requireWorkTask(params.workId, params.taskId);
    const sessions = await this.sessions.list(params.workId, params.taskId);
    const session = params.sessionId ? sessions.find((entry) => entry.id === params.sessionId) : sessions[0];
    if (params.sessionId && !session) throw new RpcError(HostErrorCode.WORK_NOT_FOUND, "Card session not found");
    const all = session ? await this.sessions.read(session) : [];
    const filtered = all.filter((event) => params.beforeSeq === undefined || event.seq < params.beforeSeq);
    const entries = filtered.slice(-100);
    return { sessions, sessionId: session?.id, entries, beforeSeq: filtered.length > entries.length ? entries[0]?.seq : undefined };
  }

  async createWorkTask(params: WorkTaskCreateParams, actor: WorkActor = { kind: "user", id: "local-user" }, commandId?: string): Promise<WorkTaskView> {
    if (this.workStore.getWork(params.workId).kind === "room") throw new RpcError(HostErrorCode.WORK_CONFLICT, "Enable the task board before creating cards");
    await this.assertWorkAssignees(params.workId, params.assigneeIds);
    const now = Date.now();
    const task: WorkTask = {
      id: crypto.randomUUID(),
      title: params.title.trim(),
      description: params.description.trim(),
      acceptanceCriteria: params.acceptanceCriteria,
      state: "ready",
      ...(actor.kind === "agent" ? { ownerAgentId: actor.id } : {}),
      assigneeIds: params.assigneeIds,
      dependencyIds: params.dependencyIds,
      priority: params.priority,
      revision: 1,
      deliverables: [],
      createdAt: now,
      updatedAt: now
    };
    const event = await this.workStore.appendEvent(params.workId, {
      type: "task.created",
      id: crypto.randomUUID(),
      workId: params.workId,
      createdAt: now,
      actor,
      clientEventId: commandId,
      task
    });
    this.emit(HostEvents.workEventAppended, { workId: params.workId, event });
    return this.workTaskView(event.type === "task.created" ? event.task : task);
  }

  async assignWorkTask(params: WorkTaskAssignParams): Promise<WorkTaskView> {
    await this.assertWorkAssignees(params.workId, params.assigneeIds);
    const task = await this.requireWorkTask(params.workId, params.taskId);
    this.assertTaskRevision(task, params.expectedRevision);
    const event = await this.workStore.appendEvent(params.workId, {
      type: "task.assigned",
      id: crypto.randomUUID(),
      workId: params.workId,
      createdAt: Date.now(),
      actor: { kind: "user", id: "local-user" },
      taskId: params.taskId,
      assigneeIds: params.assigneeIds,
      revision: task.revision + 1
    }, { taskId: task.id, revision: task.revision });
    this.emit(HostEvents.workEventAppended, { workId: params.workId, event });
    return this.workTaskView(await this.requireWorkTask(params.workId, params.taskId));
  }

  async transitionWorkTask(params: WorkTaskTransitionParams): Promise<WorkTaskView> {
    const task = await this.requireWorkTask(params.workId, params.taskId);
    this.assertTaskRevision(task, params.expectedRevision);
    assertTaskTransition(task.state, params.to, "user");
    if (params.to === "blocked" && !params.blocker) {
      throw new RpcError(HostErrorCode.WORK_CONFLICT, "A blocker reason is required");
    }
    const event = await this.workStore.appendEvent(params.workId, {
      type: "task.transitioned",
      id: crypto.randomUUID(),
      workId: params.workId,
      createdAt: Date.now(),
      actor: { kind: "user", id: "local-user" },
      taskId: params.taskId,
      from: task.state,
      to: params.to,
      revision: task.revision + 1,
      ...(params.blocker ? { blocker: params.blocker } : {})
    }, { taskId: task.id, revision: task.revision });
    this.emit(HostEvents.workEventAppended, { workId: params.workId, event });
    this.background(this.deliverCardEvent(event));
    return this.workTaskView(await this.requireWorkTask(params.workId, params.taskId));
  }

  private disposing = false;
  private readonly roomChains = new Map<string, Promise<unknown>>();

  private async inRoom<T>(workId: string, action: () => Promise<T>): Promise<T> {
    const prior = this.roomChains.get(workId) ?? Promise.resolve();
    const next = prior.catch(() => undefined).then(action);
    this.roomChains.set(workId, next);
    try { return await next; }
    finally { if (this.roomChains.get(workId) === next) this.roomChains.delete(workId); }
  }

  private async delegateCard(params: WorkDispatchParams, actor: { kind: "agent" | "user"; id: string }, commandId?: string): Promise<{ ok: true; runId: string; queued: boolean }> {
    return this.inRoom(params.workId, async () => {
      const prior = commandId ? (await this.workStore.readTimeline(params.workId)).find(event => event.clientEventId === commandId && event.type === "task.delegated") : undefined;
      if (prior?.type === "task.delegated") return (await this.deliverCardEventNow(prior)) ?? { ok: true, runId: prior.id, queued: true };
      const task = await this.requireWorkTask(params.workId, params.taskId!);
      if (["blocked", "review", "done", "cancelled"].includes(task.state)) throw new RpcError(HostErrorCode.WORK_CONFLICT, "Card is blocked or awaiting human review; a human must resume it before dispatch");
      const pending = pendingCardDelegation(await this.workStore.readTimeline(params.workId), task.id);
      if (pending) throw new RpcError(HostErrorCode.WORK_CONFLICT, "This card already has a worker awaiting a result. Continue that execution or cancel the card first.");
      const member = this.workStore.membership(params.workId, params.agentId);
      if (!member.binding || !member.binding.grants.canManageOwnTasks) throw new RpcError(HostErrorCode.WORK_FORBIDDEN, "Target is not an executable room member");
      const event = await this.workStore.appendEvent(params.workId, {
        type: "task.delegated", id: crypto.randomUUID(), workId: params.workId, actor, createdAt: Date.now(),
        clientEventId: commandId, taskId: task.id, agentId: params.agentId, instruction: params.instruction,
        membershipRevision: member.revision, revision: task.revision + 1, messageId: crypto.randomUUID()
      }, { taskId: task.id, revision: task.revision });
      this.emit(HostEvents.workEventAppended, { workId: params.workId, event });
      return (await this.deliverCardEventNow(event))!;
    });
  }

  private async deliverCardEvent(event: import("@nuum/protocol").WorkEvent): Promise<void> {
    if (this.disposing) return;
    await this.inRoom(event.workId, async () => { await this.deliverCardEventNow(event); });
  }

  private async deliverCardEventNow(event: WorkEvent): Promise<{ ok: true; runId: string; queued: boolean } | undefined> {
    const events = await this.workStore.readTimeline(event.workId);
    if (events.some(item => item.type === "history.imported" && item.unconfirmedEventIds.includes(event.id))) return;
    const task = "taskId" in event && event.taskId ? projectWork(events).tasks.find(task => task.id === event.taskId) : undefined;
    const intent = workIntent(event, task);
    if (!intent) return;
    const executionId = `execute:${event.id}:${intent.agentId}`;
    const submitted = this.submittedWork.get(executionId);
    if (submitted) return { ok: true, runId: submitted.runId, queued: submitted.state === "queued" };
    if (events.some(item => (item.type === "execution.started" || item.type === "execution.finished") && item.executionId === executionId)) return;
    // Legacy deliveries are uncertain. They are exposed for explicit continuation, never replayed.
    if (events.some(item => item.type === "dispatch.requested" && item.causationId === event.id)) return;
    if (intent.taskId && (!task || task.state !== "in_progress" || !currentCardSource(events, event, intent.taskId))) return;
    const membership = this.workStore.membership(event.workId, intent.agentId);
    if (!membership.binding || !this.store.getAgent(intent.agentId) || ("membershipRevision" in event && event.membershipRevision !== undefined && membership.revision !== event.membershipRevision)) {
      await this.appendWorkEvent(event.workId, {
        type: "execution.finished", id: `finish:${executionId}`, workId: event.workId, createdAt: Date.now(), actor: { kind: "system", id: "host" },
        executionId, sourceEventId: event.id, agentId: intent.agentId, taskId: intent.taskId, status: "failed",
        error: "The assigned member is no longer available with the original room membership. Restore membership or assign another worker."
      });
      return;
    }
    const run = await this.scheduleWork({ workId: event.workId, ...intent }, event.actor.kind === "agent" ? event.actor : { kind: "user", id: event.actor.id }, event.id, executionId, undefined, event.type === "work.requested" ? event.inputAfterSeq : undefined);
    return { ok: true, runId: run.runId, queued: run.state === "queued" };
  }

  async dispatchWork(params: WorkDispatchParams): Promise<{ ok: true; runId: string; queued: boolean }> {
    if (params.taskId) {
      const result = await this.delegateCard(params, { kind: "user", id: "local-user" });
      await [...this.submittedWork.values()].find(run => run.runId === result.runId)?.started;
      return result;
    }
    const event = await this.appendWorkEvent(params.workId, {
      type: "work.requested", id: crypto.randomUUID(), workId: params.workId, createdAt: Date.now(), actor: { kind: "user", id: "local-user" },
      agentId: params.agentId, instruction: params.instruction.trim(), membershipRevision: this.workStore.membership(params.workId, params.agentId).revision
    });
    const result = await this.inRoom(params.workId, () => this.deliverCardEventNow(event));
    if (!result) throw new Error("Work target is no longer available");
    await this.submittedWork.get(`execute:${event.id}:${params.agentId}`)?.started;
    return result;
  }

  private async scheduleWork(params: WorkDispatchParams, requestedBy: { kind: "user" | "agent"; id: string }, sourceEventId: string, executionId: string, discussionId?: string, inputAfterSeq?: number): Promise<SubmittedRun> {
    if (this.disposing) throw new Error("Host is stopping");
    this.store.requireAgent(params.agentId);
    const membership = this.workStore.membership(params.workId, params.agentId);
    if (!membership.binding?.grants.canPost) throw new RpcError(HostErrorCode.WORK_FORBIDDEN, "Agent cannot execute in this room");
    const catalog = await this.workStore.readCatalog(params.workId);
    const session = params.taskId ? await this.sessions.ensure(params.workId, params.taskId, params.agentId, membership.revision) : undefined;
    const submitted = this.launch(params.agentId, {
      kind: "work", workId: params.workId, taskId: params.taskId, session, bridgeId: executionId, discussionId, inputAfterSeq,
      instruction: params.instruction.trim(), membershipRevision: membership.revision, triggerEventId: sourceEventId,
      catalogRevision: catalog.revision, catalog: catalog.entries, requestedBy
    });
    this.submittedWork.set(executionId, submitted);
    // start failures are observed by completed; callers may still await started for an RPC error.
    void submitted.started?.catch(() => undefined);
    void submitted.completed.then(() => { this.submittedWork.delete(executionId); });
    this.emit(HostEvents.agentUpdated, { agent: await this.viewFor(this.store.requireAgent(params.agentId)) });
    return submitted;
  }

  async addWorkCatalogEntry(params: WorkCatalogAddParams): Promise<WorkCatalog> {
    const entry = {
      ...params.entry,
      id: crypto.randomUUID(),
      enabled: true,
      ...(params.entry.kind === "skill" ? { manifestPath: path.resolve(params.entry.manifestPath) } : {}),
      ...(params.entry.kind === "cli" ? { executable: path.resolve(params.entry.executable) } : {}),
      ...(params.entry.kind === "knowledge" ? { roots: params.entry.roots.map((root) => path.resolve(root)) } : {})
    } as WorkCatalogEntry;
    const catalog = await this.workStore.updateCatalog(params.workId, params.expectedRevision, (current) => ({
      revision: current.revision + 1,
      entries: [...current.entries, entry]
    }));
    this.emit(HostEvents.workCatalogUpdated, { workId: params.workId, catalog });
    return catalog;
  }

  async removeWorkCatalogEntry(params: WorkCatalogRemoveParams): Promise<WorkCatalog> {
    const catalog = await this.workStore.updateCatalog(params.workId, params.expectedRevision, (current) => ({
      revision: current.revision + 1,
      entries: current.entries.filter((entry) => entry.id !== params.entryId)
    }));
    this.emit(HostEvents.workCatalogUpdated, { workId: params.workId, catalog });
    return catalog;
  }

  // ── 回合 ────────────────────────────────────────────────────────────────

  async send(
    id: string,
    content: string,
    options: { widgetAnswerTo?: string } = {}
  ): Promise<{ ok: true; runId: string; queued: boolean }> {
    const record = this.store.requireAgent(id);
    const model = resolveSessionModel({
      sessionModel: record.settings.model,
      defaultModel: this.settings.defaultModel,
      secrets: this.store.secrets
    });
    if (this.agentHasPending(id)) {
      throw new RpcError(HostErrorCode.AGENT_BUSY, "Approve or deny the pending tool before sending another message");
    }
    precheck({
      exists: true,
      // 同一 agent 只有一条 transcript，并行跑会把上下文写乱，所以用户路径仍然拒绝。
      // 排队留给第 6 步的 agent 间唤醒（那里 wake 事件定义了顺序语义）。
      busy: this.scheduler.isBusy(id),
      model,
      secrets: this.store.secrets
    });
    if (!this.kernel) throw new RpcError(HostErrorCode.KERNEL_DOWN, "Kernel is not available");
    this.errored.delete(id);

    const { events } = await this.readModelTranscript(id);
    // 用户消息先落盘再排队：即使全局并发已满、这个 run 要等，消息也立刻出现在时间线上。
    const user = await this.store.appendEvent(id, {
      type: "user",
      id: crypto.randomUUID(),
      text: content,
      ...(options.widgetAnswerTo ? { widgetAnswerTo: options.widgetAnswerTo } : {}),
      createdAt: Date.now()
    });
    if (record.profile.name === DEFAULT_AGENT_NAME && events.length === 0) {
      await this.store.updateAgent(id, { profile: { name: deriveName(content) } });
    }
    if (record.settings.model !== model) {
      await this.store.updateAgent(id, { settings: { model } });
    }
    this.emit(HostEvents.agentMessageCompleted, { agentId: id, event: user });

    const { runId, state, started } = this.launch(id, DIRECT_RUN_CONTEXT);
    this.emit(HostEvents.agentUpdated, { agent: await this.viewFor(this.store.requireAgent(id)) });
    // 立刻起的 run 等它真的进了 Kernel 再回 —— 否则拉起失败会被吞掉，用户以为发出去了。
    await started;
    return { ok: true, runId, queued: state === "queued" };
  }

  /**
   * 回答提问卡片：选项值原样成为一条用户消息（Grok 同款语义 —— value 写得像
   * 用户会回的话），并用 widgetAnswerTo 指回那张卡片，投影据此标出选中项。
   */
  async answerWidget(id: string, messageId: string, value: string): Promise<{ ok: true; runId: string; queued: boolean }> {
    this.store.requireAgent(id);
    return this.send(id, value, { widgetAnswerTo: messageId });
  }

  /**
   * 把一个 agent 交给调度器。用户消息（`send`）与 agent 唤醒（`wake`）共用
   * 这一条路：区别只在追什么事件，起 run 的动作是同一个。上下文每次从转录
   * 重新拼，所以起因是谁不影响这里。
   */
  private launch(
    id: string,
    context: RunContext
  ): SubmittedRun {
    const roots = this.toolRoots(this.store.requireAgent(id), context);
    const submitted = this.scheduler.submit({
      projectRoot: roots.project,
      agentId: id,
      context,
      start: async (activeRunId) => {
        const activeContext = this.scheduler.contextFor(activeRunId);
        if (!activeContext) throw new Error(`Run ${activeRunId} lost its context before start`);
        try {
        const record = this.store.requireAgent(id);
        const model = resolveSessionModel({
          sessionModel: record.settings.model,
          defaultModel: this.settings.defaultModel,
          secrets: this.store.secrets
        });
        precheck({ exists: true, busy: false, model, secrets: this.store.secrets });
        if (!this.kernel) throw new RpcError(HostErrorCode.KERNEL_DOWN, "Kernel is not available");
        if (activeContext.kind === "work") await this.prepareWorkInput(id, activeContext, activeRunId);
        let { events: replayed, compact } = await this.readModelTranscript(id, activeContext);
        let prompt = await this.buildSystemPrompt(id, Boolean(compact), activeContext);
        let assembled = assembleContext({
          transcript: replayed,
          systemPrompt: prompt.text,
          notices: prompt.notices
        });
        if (estimateContextTokens(assembled) > this.contextWindow(model) * 0.75) {
          try {
            const compacted = await this.compact(id, activeRunId, replayed, model);
            if (compacted) {
              ({ events: replayed, compact } = await this.readModelTranscript(id, activeContext));
              prompt = await this.buildSystemPrompt(id, Boolean(compact), activeContext);
              assembled = assembleContext({
                transcript: replayed,
                systemPrompt: prompt.text,
                notices: prompt.notices
              });
            }
          } catch (error) {
            throw new Error(`Context compaction failed: ${String(error)}`);
          }
          if (estimateContextTokens(assembled) > this.contextWindow(model) * 0.75) throw new Error("Context capacity exhausted; narrow the input before continuing.");
        }
        const approvals = activeContext.kind === "work" && activeContext.session ? { always: [], refused: [] } : await this.store.readApprovals(id);
        await this.kernel!.start({
          runId: activeRunId,
          ...(this.kernel!.provideContext ? { contextWindow: this.contextWindow(model) } : {}),
          messages: assembled,
          model,
          roots,
          toolPermission: record.settings.workspace?.toolPermission ?? this.settings.defaultToolPermission,
          approvals: approvals.always,
          refused: approvals.refused,
          // Proactive / Work 的本地工具由各自 capability catalog 显式装配。
          // 在那之前默认空集，绝不继承私人 run 的文件和 shell 能力。
          localToolNames: activeContext.kind === "direct"
            ? this.toolCache.map((tool) => tool.name)
            : activeContext.kind === "work"
              ? [...new Set([
                  ...activeContext.catalog
                    .filter((entry) => entry.kind === "local-tool" && entry.enabled)
                    .flatMap((entry) => entry.kind === "local-tool" ? entry.toolNames : []),
                  ...(activeContext.catalog.some((entry) => entry.kind === "knowledge" && entry.enabled)
                    ? ["read", "ls", "glob", "grep"]
                    : [])
                ])]
              : [],
          delegatedTools: delegatedToolsForRunContext(this.delegated.values(), activeContext).map(
            (tool) => tool.definition
          ),
          // turn 循环的静默提醒按「发声工具」计数：direct 是 SendMessage，
          // work 里对用户的可见出口是共享频道的 PostToWork / HandoffTask。
          voiceToolNames: [DelegatedToolNames.sendMessage],
          secrets: this.store.secrets
        });
        } catch (error) {
          if (activeContext.kind === "work" && activeContext.bridgeId) await this.finishWorkDispatch(id, activeContext, "failed", error instanceof Error ? error.message : String(error));
          this.emit(HostEvents.agentError, { agentId: id, runId: activeRunId, message: error instanceof Error ? error.message : String(error) });
          throw error;
        }
      }
    });
    this.background(submitted.completed.then(async status => {
      if (status !== "failed" || this.disposing) return;
      const record = this.store.getAgent(id);
      if (record) this.emit(HostEvents.agentUpdated, { agent: await this.viewFor(record) });
    }));
    return submitted;
  }

  async cancel(id: string): Promise<{ ok: true }> {
    // 只取消这个 agent 的 run，别的 agent 照跑。排着的唤醒一起丢 ——
    // 用户按下停止，意思是「别忙了」，不是「先停这个再接着忙下一个」。
    this.wakes.drop(id);
    const activeRun = this.scheduler.activeRunFor(id);
    if (activeRun) {
      this.compactJobs.delete(activeRun);
      await this.kernel?.cancelSummary?.(`${activeRun}:compact`);
    }
    const queued = this.scheduler.queuedForAgent(id);
    for (const context of queued) {
      if (context.kind === "work" && context.discussionId) await this.stopWorkDiscussion(context.workId);
      if (context.kind === "work" && context.bridgeId) await this.finishWorkDispatch(id, context, "cancelled");
    }
    for (const runId of this.scheduler.cancelAgent(id)) {
      const context = this.scheduler.contextFor(runId);
      if (context?.kind === "work") {
        if (context.bridgeId) {
          this.cancelledExecutions.add(context.bridgeId);
          await this.finishWorkDispatch(id, context, "cancelled");
        }
        if (context.discussionId) await this.stopWorkDiscussion(context.workId);
      }
      await this.kernel?.cancel(runId);
    }
    return { ok: true };
  }

  async decide(id: string, toolCallId: string, resolution: ToolResolution): Promise<{ ok: true }> {
    const pending = this.pendingTools.get(pendingKey(id, toolCallId));
    if (pending && resolution !== "once" && !this.cardSessionFor(id)) {
      const stored = await this.store.readApprovals(id);
      const always = stored.always.filter((item) => !sameApproval(item, pending));
      const refused = stored.refused.filter((item) => !sameApproval(item, pending));
      if (resolution === "always") always.push(pending);
      if (resolution === "deny" || resolution === "never") refused.push(pending);
      await this.store.writeApprovals(id, { always, refused });
    }
    if (resolution === "never" && !this.cardSessionFor(id)) {
      const record = this.store.requireAgent(id);
      const updated = await this.store.updateAgent(id, {
        settings: {
          workspace: {
            projectRoot: record.settings.workspace?.projectRoot ?? null,
            toolPermission: "never"
          }
        }
      });
      this.emit(HostEvents.agentUpdated, { agent: await this.viewFor(updated) });
    }
    if (!this.kernel) throw new RpcError(HostErrorCode.KERNEL_DOWN, "Kernel is not available");
    const runId = this.scheduler.activeRunFor(id);
    if (!runId) throw new RpcError(HostErrorCode.AGENT_NOT_FOUND, "No running turn to decide on");
    this.forgetPending(id, toolCallId);
    await this.kernel.decide({ runId, toolCallId, resolution }, resolution === "deny");
    return { ok: true };
  }

  /** Kernel 本地工具 + Host 委派工具，合起来才是模型看得见的全集。 */
  tools(): ToolDefinition[] {
    return [...this.toolCache, ...[...this.delegated.values()].map((tool) => tool.definition)];
  }

  // ── 委派工具的 handler（§5.2）────────────────────────────────────────────

  /**
   * SendMessage：助手对用户说话的唯一出口。追一条 `message` 事件到真源，UI
   * 拿它画气泡；模型侧仍保留原 SendMessage tool_call，不把该事件
   * 重复回放成 assistant 消息（§2.Q6）。
   */
  async sendMessage(
    agentId: string,
    params: SendMessageParams,
    source: Pick<DelegatedToolContext, "assistantId" | "toolCallId">
  ): Promise<string> {
    this.store.requireAgent(agentId);
    // 消息发出去意味着「这条要给用户看」，所以先把在写的助手块收口，
    // 气泡才会排在它自己那段工作痕迹之后而不是之前。
    await this.flushAssistant(agentId);
    const event = await this.store.appendEvent(agentId, {
      type: "message",
      id: crypto.randomUUID(),
      assistantId: source.assistantId,
      toolCallId: source.toolCallId,
      payload: params,
      createdAt: Date.now()
    });
    if (!this.cardSessionFor(agentId)) this.emit(HostEvents.agentMessageCompleted, { agentId, event });
    if (params.type === "text") return `Delivered. (id: ${event.id})`;
    if (params.type === "attachment") return `Delivered ${params.path}. (id: ${event.id})`;
    if (typeof params.widget === "string") return `Delivered the ${params.widget} widget.`;
    // 提问卡片语义上结束回合：用户的选择会作为下一条用户消息回来。
    return `Question delivered. (id: ${event.id}) Stop after this; the user's selection arrives as their next message.`;
  }

  async createTaskFromModel(agentId: string, params: CreateTaskParams, context: DelegatedToolContext): Promise<string> {
    const run = requireWorkRun(context.runContext);
    this.assertWorkAgent(agentId, run.workId);
    const task = await this.createWorkTask({ ...params, workId: run.workId, priority: "normal", dependencyIds: [] }, { kind: "agent", id: agentId }, `${run.session?.id ?? agentId}:${context.assistantId}:${context.toolCallId}`);
    return JSON.stringify(task);
  }

  async claimTask(agentId: string, params: ClaimTaskParams, context: DelegatedToolContext): Promise<string> {
    const run = requireWorkRun(context.runContext);
    this.assertWorkAgent(agentId, run.workId);
    const key = `${run.session?.id ?? agentId}:${context.assistantId}:${context.toolCallId}`;
    const prior = (await this.workStore.readTimeline(run.workId)).find((event) => event.clientEventId === key);
    if (prior) return "Task already claimed by this command.";
    const task = await this.requireWorkTask(run.workId, params.taskId);
    if (!["ready", "proposed"].includes(task.state) || (task.ownerAgentId !== agentId && task.assigneeIds.length && !task.assigneeIds.includes(agentId))) throw new RpcError(HostErrorCode.WORK_FORBIDDEN, "This task cannot be claimed or resumed by you");
    this.assertTaskRevision(task, params.expectedRevision);
    const event = await this.workStore.appendEvent(run.workId, {
      type: "task.claimed", id: crypto.randomUUID(), workId: run.workId, createdAt: Date.now(), actor: { kind: "agent", id: agentId }, clientEventId: key,
      taskId: task.id, assigneeIds: task.assigneeIds.length ? task.assigneeIds : [agentId], revision: task.revision + 1,
      messageId: crypto.randomUUID(), body: `Started: ${task.title}`, sourceSessionId: run.session?.id ?? `main:${agentId}`
    }, { taskId: task.id, revision: task.revision });
    this.emit(HostEvents.workEventAppended, { workId: run.workId, event });
    return "Task claimed. Use DelegateWork with your own agent_id and this task_id to execute it in its independent card session.";
  }

  async readTask(agentId: string, params: ReadTaskParams, context: DelegatedToolContext): Promise<string> {
    const run = requireWorkRun(context.runContext);
    this.assertWorkAgent(agentId, run.workId);
    return JSON.stringify(params.taskId ? await this.requireWorkTask(run.workId, params.taskId) : projectWork(await this.workStore.readTimeline(run.workId)).tasks.map(({ id, title, state, revision, assigneeIds, ownerAgentId }) => ({ id, title, state, revision, assigneeIds, ownerAgentId })));
  }

  async sendWorkMessage(agentId: string, params: WorkSendMessageParams, context: DelegatedToolContext): Promise<string> {
    if (!params.cardAction) return this.postToWork(agentId, { message: params.content }, context);
    const run = requireWorkRun(context.runContext);
    const commandId = `${run.session?.id ?? agentId}:${context.assistantId}:${context.toolCallId}`;
    const existing = (await this.workStore.readTimeline(run.workId)).find((event) => event.clientEventId === commandId);
    if (existing) return `Delivered. (event: ${existing.id})`;
    if (params.cardAction.expectedRevision !== undefined && (!run.taskId || (await this.requireWorkTask(run.workId, run.taskId)).revision !== params.cardAction.expectedRevision)) {
      throw new RpcError(HostErrorCode.WORK_CONFLICT, "Task revision changed; read the current card before submitting");
    }
    return this.handoffTask(agentId, { summary: params.content, ...params.cardAction }, context);
  }

  async postToWork(
    agentId: string,
    params: PostToWorkParams,
    context: DelegatedToolContext
  ): Promise<string> {
    const run = requireWorkRun(context.runContext);
    this.assertWorkAgent(agentId, run.workId);
    return this.inRoom(run.workId, async () => {
    const history = await this.workStore.readTimeline(run.workId);
    const commandId = `${run.session?.id ?? agentId}:${context.assistantId}:${context.toolCallId}`;
    const prior = history.find(event => event.clientEventId === commandId);
    if (prior?.type === "chat.posted") return `Posted to the Work shared room. (message: ${prior.messageId})`;
    this.assertWorkRunCurrent(run, agentId);
    const discussion = run.discussionId ? this.discussions.get(run.workId) : undefined;
    if (run.discussionId) {
      if (!discussion || discussion.id !== run.discussionId || discussion.stopped) throw new Error("Discussion stopped");
      if (isPass(params.message)) return "No public message sent. Stop this turn.";
      if (discussion.total >= discussionLimits.messages || (discussion.perExecution.get(run.bridgeId!) ?? 0) >= discussionLimits.perTurn) throw new Error("Discussion message budget reached. Stop this turn.");
    }
    const event = await this.workStore.appendEvent(run.workId, {
      type: "chat.posted",
      id: crypto.randomUUID(),
      workId: run.workId,
      createdAt: Date.now(),
      actor: { kind: "agent", id: agentId },
      causationId: run.triggerEventId,
      correlationId: run.discussionId,
      clientEventId: `${run.session?.id ?? agentId}:${context.assistantId}:${context.toolCallId}`,
      messageId: crypto.randomUUID(),
      body: params.message.trim(),
      sourceSessionId: run.session?.id ?? `main:${agentId}`,
      taskId: run.taskId,
      mentionedAgentIds: []
    });
    this.emit(HostEvents.workEventAppended, { workId: run.workId, event });
    if (discussion && event.type === "chat.posted") {
      discussion.total++;
      discussion.perExecution.set(run.bridgeId!, (discussion.perExecution.get(run.bridgeId!) ?? 0) + 1);
      discussion.replies.push(event);
    }
    return `Posted to the Work shared room. (message: ${event.type === "chat.posted" ? event.messageId : event.id})`;
    });
  }

  async handoffTask(
    agentId: string,
    params: HandoffTaskParams,
    context: DelegatedToolContext
  ): Promise<string> {
    const run = requireWorkRun(context.runContext);
    if (!run.taskId) throw new RpcError(HostErrorCode.WORK_CONFLICT, "This Work run has no task to hand off");
    const record = this.assertWorkAgent(agentId, run.workId);
    const history = await this.workStore.readTimeline(run.workId);
    const commandId = `${run.session?.id ?? agentId}:${context.assistantId}:${context.toolCallId}`;
    if (history.some(event => event.clientEventId === commandId && event.type === "task.handed_off")) return "Result already submitted. Stop this run.";
    this.assertWorkRunCurrent(run, agentId);
    if (run.bridgeId) {
      const source = history.find(event => event.id === run.triggerEventId);
      if (!source || !currentCardSource(history, source, run.taskId)) throw new Error("Card execution was superseded by a newer decision");
    }
    const task = await this.requireWorkTask(run.workId, run.taskId);
    if (task.ownerAgentId !== agentId && !task.assigneeIds.includes(agentId)) {
      throw new RpcError(HostErrorCode.WORK_FORBIDDEN, "This task is not assigned to you");
    }
    const role = this.workStore.membership(run.workId, agentId).binding!.role;
    if (params.status === "done") throw new RpcError(HostErrorCode.WORK_FORBIDDEN, "Final acceptance belongs to the human reviewer");
    assertTaskTransition(task.state, params.status, role);
    if (params.status === "blocked" && !params.blocker_reason?.trim()) {
      throw new RpcError(HostErrorCode.WORK_CONFLICT, "blocker_reason is required when status is blocked");
    }
    const now = Date.now();
    const deliverables = params.deliverables.map((item) => ({
      id: crypto.randomUUID(),
      name: item.name,
      uri: item.uri,
      ...(item.mime_type ? { mimeType: item.mime_type } : {}),
      createdAt: now
    }));
    const handoff = await this.workStore.appendEvent(run.workId, {
      type: "task.handed_off",
      id: crypto.randomUUID(),
      workId: run.workId,
      createdAt: now,
      actor: { kind: "agent", id: agentId },
      causationId: run.triggerEventId,
      clientEventId: `${run.session?.id ?? agentId}:${context.assistantId}:${context.toolCallId}`,
      taskId: task.id,
      summary: params.summary.trim(),
      deliverables,
      nextStatus: params.status === "review" && task.ownerAgentId && task.ownerAgentId !== agentId ? "in_progress" : params.status,
      ...(params.status === "review" && task.ownerAgentId && task.ownerAgentId !== agentId ? { returnToAgentId: task.ownerAgentId } : {}),
      ...(params.blocker_reason ? { blockerReason: params.blocker_reason.trim() } : {}),
      revision: task.revision + 1,
      messageId: crypto.randomUUID(),
      sourceSessionId: run.session?.id ?? `main:${agentId}`
    }, { taskId: task.id, revision: task.revision });
    this.emit(HostEvents.workEventAppended, { workId: run.workId, event: handoff });
    this.background(this.deliverCardEvent(handoff));
    if (params.status === "review") return task.ownerAgentId && task.ownerAgentId !== agentId ? "Result returned to the card owner. Stop this run." : "Handed off for review. Stop this run.";
    return "Reported blocked.";
  }

  async readWorkTimeline(
    agentId: string,
    params: ReadWorkTimelineParams,
    context: DelegatedToolContext
  ): Promise<string> {
    const run = requireWorkRun(context.runContext);
    this.assertWorkAgent(agentId, run.workId);
    const events = (await this.workStore.readTimeline(run.workId)).filter((event) => (params.beforeSeq === undefined || event.seq < params.beforeSeq) && (params.afterSeq === undefined || event.seq > params.afterSeq)).slice(-params.limit);
    return events.length ? events.map(renderWorkEventForAgent).join("\n") : "The Work timeline is empty.";
  }

  async runWorkCli(
    agentId: string,
    params: RunWorkCliParams,
    context: DelegatedToolContext
  ): Promise<string> {
    const run = requireWorkRun(context.runContext);
    this.assertWorkAgent(agentId, run.workId);
    const capability = run.catalog.find((entry) => entry.id === params.capability_id && entry.kind === "cli");
    if (!capability || capability.kind !== "cli" || !capability.enabled) {
      throw new RpcError(HostErrorCode.WORK_FORBIDDEN, "CLI capability is not installed in this Work run");
    }
    const subcommand = params.args[0];
    if (subcommand && !capability.allowedSubcommands.includes(subcommand)) {
      throw new RpcError(HostErrorCode.WORK_FORBIDDEN, "That CLI subcommand is not allowed by this Work");
    }
    const work = this.workStore.getWork(run.workId);
    const result = await execFileAsync(capability.executable, params.args, {
      cwd: work.projectRoot ?? undefined,
      timeout: 120_000,
      maxBuffer: 1024 * 1024
    });
    return [result.stdout, result.stderr].filter(Boolean).join("\n").slice(0, 100_000) || "Command completed.";
  }

  async delegateWork(
    agentId: string,
    params: DelegateWorkParams,
    context: DelegatedToolContext
  ): Promise<string> {
    const run = requireWorkRun(context.runContext);
    const caller = this.assertWorkAgent(agentId, run.workId);
    if (!this.workStore.membership(run.workId, agentId).binding!.grants.canAssignTasks) {
      throw new RpcError(HostErrorCode.WORK_FORBIDDEN, "This room membership cannot dispatch tasks");
    }
    const taskId = params.task_id ?? run.taskId;
    if (!taskId) throw new RpcError(HostErrorCode.WORK_CONFLICT, "DelegateWork requires a card. For room discussion, mention the member in SendMessage; the bounded discussion will schedule them.");
    await this.delegateCard({
      workId: run.workId,
      agentId: params.agent_id,
      taskId,
      instruction: params.instruction
    }, { kind: "agent", id: agentId }, `${run.session?.id ?? agentId}:${context.assistantId}:${context.toolCallId}`);
    return "Worker dispatched. The card owner is unchanged; the worker result will return to the owner’s card session. Stop and wait if you have no independent work.";
  }

  /**
   * update_state：agent 改自己。
   *
   * profile 改名 / 改描述会公告进时间线（`profile` 事件），但**不** bump epoch ——
   * 系统段保持冻结，当轮靠尾部飘移说明告知（§6.1）。
   *
   * 显式写记忆**要** bump epoch：用户说「记住我用 pnpm」时期待的是下一句就生效，
   * 而不是等某次压缩。代价是一次 cache miss，那恰好是最值得付的一次。
   */
  async updateState(agentId: string, params: UpdateStateParams): Promise<string> {
    if (params.target === "profile") {
      const patch: { name?: string; description?: string; tags?: string[] } = {};
      if (params.name !== undefined) patch.name = params.name.trim();
      if (params.description !== undefined) patch.description = params.description.trim();
      if (params.tags !== undefined) patch.tags = params.tags;
      if (Object.keys(patch).length === 0) return "Nothing to change: pass name, tags or description.";
      const record = await this.store.updateAgent(agentId, { profile: patch });
      const event = await this.store.appendEvent(agentId, {
        type: "profile",
        id: crypto.randomUUID(),
        patch,
        createdAt: Date.now()
      });
      if (!this.cardSessionFor(agentId)) this.emit(HostEvents.agentMessageCompleted, { agentId, event });
      this.emit(HostEvents.agentUpdated, { agent: await this.viewFor(record) });
      return `Profile updated. You are now "${record.profile.name}".`;
    }

    if (params.target === "settings") {
      const record = this.store.requireAgent(agentId);
      const projectRoot = params.project_root?.trim() ? path.resolve(params.project_root) : null;
      const updated = await this.store.updateAgent(agentId, {
        settings: {
          workspace: {
            projectRoot,
            toolPermission: record.settings.workspace?.toolPermission ?? null
          }
        }
      });
      this.emit(HostEvents.agentUpdated, { agent: await this.viewFor(updated) });
      return projectRoot ? `Project directory set to ${projectRoot}.` : "Project directory cleared.";
    }

    const memory = new MemoryStore(this.store.memoryDir(agentId));
    if (params.action === "forget") {
      const { removed } = await memory.forget(params.fact);
      if (removed === 0) return "Nothing matched that, so nothing was removed.";
      await this.store.bumpPromptEpoch(agentId);
      return `Forgotten (${removed} ${removed === 1 ? "entry" : "entries"} removed).`;
    }
    const { written } = await memory.write(params.fact, params.tier);
    if (!written) return "Already recorded — nothing to do.";
    await this.store.bumpPromptEpoch(agentId);
    return `Recorded to ${params.tier === "profile" ? "your standing facts" : "your log"}.`;
  }

  /**
   * CreateAgent：建一个真的队友 —— 自己的目录、自己的 transcript、自己的 run。
   * 创建免审批，约束靠提示词守则、没有删除工具和这里的硬护栏：
   * 单轮最多 1 个、全局上限 50。
   */
  async createAgentFromModel(agentId: string, params: CreateAgentParams): Promise<string> {
    const runId = this.scheduler.activeRunFor(agentId);
    if (!this.wakes.claimCreate(runId)) {
      return `Refused: you have already created an agent this turn. Use it, or ask the user before creating more.`;
    }
    if (this.store.listAgents().length >= MAX_AGENTS) {
      return `Refused: there are already ${MAX_AGENTS} agents. Ask the user to delete one first.`;
    }
    const view = await this.createAgent({
      name: params.name,
      description: params.description
    });
    const created = view.profile;
    if (!params.first_message) {
      return `Created "${created.name}" (id ${created.id}). It has no instructions yet — use SendToAgent to give it work.`;
    }
    const delivered = await this.sendToAgent(agentId, {
      agent_id: created.id,
      message: params.first_message
    });
    return `Created "${created.name}" (id ${created.id}). ${delivered}`;
  }

  /** UpdateAgent：改**别的** agent 的 name / description。不传的字段不动。 */
  async updateAgentFromModel(agentId: string, params: UpdateAgentParams): Promise<string> {
    if (params.agent_id === agentId) {
      return "That is you. Use update_state target=profile to change your own profile.";
    }
    const target = this.store.getAgent(params.agent_id);
    if (!target) return `No agent with id ${params.agent_id}.`;
    const patch: { name?: string; description?: string; tags?: string[] } = {};
    if (params.name !== undefined) patch.name = params.name.trim();
    if (params.description !== undefined) patch.description = params.description.trim();
    if (params.tags !== undefined) patch.tags = params.tags;
    if (Object.keys(patch).length === 0) return "Nothing to change: pass name, tags or description.";
    const record = await this.store.updateAgent(params.agent_id, { profile: patch });
    const event = await this.store.appendEvent(params.agent_id, {
      type: "profile",
      id: crypto.randomUUID(),
      patch,
      createdAt: Date.now()
    });
    this.emit(HostEvents.agentMessageCompleted, { agentId: params.agent_id, event });
    this.emit(HostEvents.agentUpdated, { agent: await this.viewFor(record) });
    return `Updated "${record.profile.name}".`;
  }

  /**
   * SendToAgent：往对方的 transcript 追一条 `wake`，然后调度它的 run。
   *
   * fire-and-forget：**立刻**回投递确认，不等对方跑完 —— 对方在自己的时间线上
   * 回话，不在这条。发送方这边不额外写出站事件：这次调用的 `tool` 事件已经把
   * 「我发了什么给谁」记在发送方时间线里了。
   */
  async sendToAgent(agentId: string, params: SendToAgentParams): Promise<string> {
    const from = this.store.getAgent(agentId);
    const target = this.store.getAgent(params.agent_id);
    if (!target) return `No agent with id ${params.agent_id}.`;
    const hops = (await this.hopsOf(agentId)) + 1;
    const verdict = this.wakes.check(agentId, params.agent_id, hops);
    if (!verdict.ok) return verdict.reason;

    const fromName = from?.profile.name ?? "another agent";
    const event = await this.store.appendEvent(params.agent_id, {
      type: "wake",
      id: crypto.randomUUID(),
      source: {
        kind: "agent",
        fromId: agentId,
        fromName,
        ...(params.priority ? { priority: true } : {})
      },
      text: params.message,
      hops,
      createdAt: Date.now()
    });
    this.emit(HostEvents.agentMessageCompleted, { agentId: params.agent_id, event });

    const wake = { fromId: agentId, fromName, text: params.message, hops };
    if (params.priority && this.scheduler.isBusy(params.agent_id)) {
      // priority 做成「取消后重起一个 run」而不是 steer：模型会重新看到完整
      // 上下文（含这条新指令），代价是丢掉当前 turn 已做的中间推理（§2.Q5）。
      //
      // 排队而不是立刻起：槽位要等 Kernel 确认 `turn.ended` 才腾出来，抢在
      // 那之前起第二个 run 会让同一个 agent 有两个 run 同时写同一条转录。
      // `cancel` 顺手清了队列，所以这条一定在队头。
      await this.cancel(params.agent_id);
      this.wakes.enqueue(params.agent_id, wake);
      return `Sent to ${target.profile.name} as priority. It is dropping what it was doing to take this.`;
    }
    if (this.scheduler.isBusy(params.agent_id)) {
      this.wakes.enqueue(params.agent_id, wake);
      return `Sent to ${target.profile.name}. It is busy, so this is queued behind what it is doing.`;
    }
    const { started } = this.launch(params.agent_id, DIRECT_RUN_CONTEXT);
    this.emit(HostEvents.agentUpdated, { agent: await this.viewFor(this.store.requireAgent(params.agent_id)) });
    try {
      // 投递是 fire-and-forget（不等对方跑完），但**起 run** 这一步要等 ——
      // 不等的话拉起失败会被吞掉，调用方以为发出去了，而对方永远不会响应。
      await started;
    } catch (error) {
      return `Delivered to ${target.profile.name}, but it could not start: ${
        error instanceof Error ? error.message : String(error)
      }. It will pick the message up next time it runs.`;
    }
    return `Sent to ${target.profile.name}.`;
  }

  /** ReadAgentTranscript：读对方时间线的文本投影。只读。 */
  async readAgentTranscript(agentId: string, params: ReadAgentTranscriptParams): Promise<string> {
    const target = this.store.getAgent(params.agent_id);
    if (!target) return `No agent with id ${params.agent_id}.`;
    const requestedLimit = params.limit ?? 40;
    // 读取窗口比展示窗口大：投影会丢掉 thinking、消息工具回执和旧版修复行，
    // 不能让这些内部事件把真正有意义的末尾内容挤出去。
    const scanLimit = Math.min(200, requestedLimit * 8);
    const { entries } = await this.store.readTranscriptPage(params.agent_id, undefined, scanLimit);
    if (entries.length === 0) return `"${target.profile.name}" has not said anything yet.`;
    const lines = entries
      .flatMap((event) => renderForPeer(event, target.profile.name))
      .slice(-requestedLimit);
    if (lines.length === 0) return `"${target.profile.name}" has no user-visible updates yet.`;
    const busy = this.scheduler.isBusy(params.agent_id) ? " (still working)" : "";
    const noun = lines.length === 1 ? "update" : "updates";
    return [`Last ${lines.length} ${noun} from "${target.profile.name}"${busy}:`, "", ...lines].join("\n");
  }

  /**
   * CheckAgent：看队友此刻在干什么，不打扰也不唤醒。比 ReadAgentTranscript 轻：
   * 只回状态与最近的工具活动，细节让模型自己 read 转录文件。只读。
   */
  async checkAgent(agentId: string, params: CheckAgentParams): Promise<string> {
    if (params.agent_id === agentId) return "That is you — you already know what you are doing.";
    const target = this.store.getAgent(params.agent_id);
    if (!target) return `No agent with id ${params.agent_id}.`;
    const runId = this.scheduler.activeRunFor(params.agent_id);
    const runContext = runId ? this.scheduler.contextFor(runId) : undefined;
    const status = runContext
      ? runContext.kind === "work"
        ? `"${target.profile.name}" is currently working in Work "${this.workStore.getWork(runContext.workId).name}".`
        : `"${target.profile.name}" is currently working in their own chat.`
      : `"${target.profile.name}" is idle.`;
    const { entries } = await this.store.readTranscriptPage(params.agent_id, undefined, 60);
    const recentTools = entries
      .filter((event): event is Extract<TranscriptEvent, { type: "tool" }> => event.type === "tool")
      .slice(-5);
    const lines = [status];
    if (recentTools.length > 0) {
      lines.push("Recent tool activity (oldest first):");
      for (const tool of recentTools) {
        const preview = tool.content.length > 120 ? `${tool.content.slice(0, 119)}…` : tool.content;
        lines.push(`  ${tool.name}: ${tool.ok === false ? "failed" : "done"} — ${preview}`);
      }
    }
    lines.push(`Their transcript is at ${this.store.transcriptFile(params.agent_id)} if you need the full play-by-play (read-only).`);
    return lines.join("\n");
  }

  /** StopAgent：掐掉对方当前的 run，排着的唤醒也一起丢。 */
  async stopAgent(agentId: string, params: StopAgentParams): Promise<string> {
    if (params.agent_id === agentId) return "That would stop you. Just stop calling tools instead.";
    const target = this.store.getAgent(params.agent_id);
    if (!target) return `No agent with id ${params.agent_id}.`;
    if (!this.scheduler.isBusy(params.agent_id)) {
      return `"${target.profile.name}" is not doing anything.`;
    }
    const dropped = this.wakes.depth(params.agent_id);
    await this.cancel(params.agent_id);
    return dropped > 0
      ? `Stopped "${target.profile.name}" and dropped ${dropped} queued message(s).`
      : `Stopped "${target.profile.name}".`;
  }

  // ── 提示词 ──────────────────────────────────────────────────────────────

  /**
   * 拼这一轮的 system prompt。profile 段按 epoch 冻结：命中快照就照用，模型看到
   * 的前缀因此逐字节不变；identity 与快照不一致时不去 bump epoch（一次改名不值
   * 得作废整个前缀缓存），而是在上下文尾部补一条飘移说明（§6.1）。
   */
  async buildSystemPrompt(
    id: string,
    hasCompact?: boolean,
    runContext: RunContext = DIRECT_RUN_CONTEXT
  ): Promise<{ text: string; notices: string[] }> {
    const record = this.store.requireAgent(id);
    if (runContext.kind === "work" && runContext.session) {
      return {
        text: [
          `You are ${record.profile.name} (${id}), working in your own card session.`,
          `Persona: ${record.profile.description}`,
          "This is the same Nunu identity, with a separate task history. Private conversation and memory are not available here.",
          "Use SendMessage for team-visible progress; include cardAction for delivery or blockers. Plain text is private scratch space.",
          "Only use the capabilities explicitly provided in this run. Do not read private agent state.",
          await this.renderWorkPrompt(runContext)
        ].join("\n\n"),
        notices: []
      };
    }
    const expert = this.options.expert?.resolve(id);
    if (expert) return { text: expert.systemPrompt, notices: [] };

    const identity: AgentIdentity = {
      name: record.profile.name,
      description: record.profile.description,
      tags: record.profile.tags
    };
    const cache = await this.store.readPromptCache(id);
    const agentDir = this.store.agentDir(id);
    const memoryDir = this.store.memoryDir(id);
    // 记忆段同样按 epoch 冻结。没有快照才去读磁盘上的 Markdown 重渲染。
    const memory =
      cache.memory ?? renderMemory(await new MemoryStore(memoryDir).all(), memoryDir);
    const compacted = hasCompact ?? Boolean((await this.store.readForAssemble(id)).compact);
    const render = renderSystemPrompt({
      identity,
      paths: {
        profile: path.join(agentDir, "profile.json"),
        settings: path.join(agentDir, "settings.json"),
        agentDir,
        scratchDir: this.store.scratchDir(id)
      },
      environment: {
        os: `${platform()} ${release()}`,
        now: new Date(),
        timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        // 第 8 步换成每 agent 的 AgentSettings.workspace.projectRoot。
        projectRoot: record.settings.workspace?.projectRoot ?? null,
        permission: describePermission(
          record.settings.workspace?.toolPermission ?? this.settings.defaultToolPermission
        )
      },
      frozenProfile: cache.profile?.render,
      memory,
      ...(runContext.kind === "work" ? {
        communication: [
          "## Talking in this Work",
          "",
          "SendMessage is your only voice in this Work: the shared room is where the user and teammates read your progress, and a message counts only once it is inside SendMessage. Plain text you write stays invisible.",
          "- Acknowledgement is optional; silence is allowed when there is nothing new. Keep the room posted on meaningful beats — a step finished, a real result, a decision, a blocker, a change of plan. Never vanish into a long silent stretch, and do not narrate routine mechanics, retries, or minor snags.",
          "- Keep updates short and specific to what changed; fold trivial mechanics under one intent.",
          "- Keep each message short and conversational — like quick texts in a busy room, not a status report. When an update has two or three beats, send them as a short run of two to four separate SendMessage calls instead of one welded paragraph.",
          "- If nothing new has happened since your last update, say nothing until there is; an update the room doesn't need is noise everyone pays for.",
          "- SendMessage with cardAction is the only way to submit an assigned task for review or report it blocked. Final acceptance belongs to the human reviewer. An update is not a handoff.",
          "Your private Agent chat remains separate. SendMessage routes to this room in this run, never to the private chat."
        ].join("\n")
      } : {}),
      agentDirectory: renderAgentDirectory(
        id,
        this.store
          .listAgents()
          .filter((mate) => mate.profile.id !== id && !mate.settings.hiddenFromSidebar)
          .filter((mate) => runContext.kind !== "work" || Boolean(this.workStore.membership(runContext.workId, mate.profile.id).binding))
          // 按 createdAt 排序，让这一段在队友集合不变时逐字节相同。
          .sort((a, b) => a.profile.createdAt - b.profile.createdAt)
          .map((mate) => ({
            id: mate.profile.id,
            name: mate.profile.name,
            description: mate.profile.description,
            tags: mate.profile.tags
          })),
        path.join(this.options.dataDir, "agents")
      ),
      compactNotice: compacted ? renderCompactNotice(this.store.transcriptFile(id)) : undefined
    });

    if (!cache.profile || !cache.memory) {
      await this.store.writePromptCache(id, {
        epoch: cache.epoch,
        profile: cache.profile ?? { render: render.liveProfile, identity },
        memory
      });
    }
    const frozenIdentity = cache.profile?.identity;
    const notice = frozenIdentity ? profileDriftNotice(frozenIdentity, identity) : null;
    const workPrompt = runContext.kind === "work" ? await this.renderWorkPrompt(runContext) : "";
    return {
      text: workPrompt ? `${render.text}\n\n${workPrompt}` : render.text,
      notices: notice ? [notice] : []
    };
  }

  private contextWindow(model: AgentSettings["model"]): number {
    if (this.options.contextWindowTokens) return this.options.contextWindowTokens;
    const known: Record<string, number> = {
      "deepseek:deepseek-chat": 128_000,
      "openai:gpt-4o": 128_000,
      "anthropic:claude-sonnet-4-20250514": 128_000
    };
    return known[`${model.provider}:${model.model}`] ?? 128_000;
  }

  private async renderWorkPrompt(context: Extract<RunContext, { kind: "work" }>): Promise<string> {
    const work = this.workStore.getWork(context.workId);
    const task = context.taskId ? await this.requireWorkTask(context.workId, context.taskId) : null;
    const members = this.store.listAgents()
      .filter((record) => Boolean(this.workStore.membership(context.workId, record.profile.id).binding))
      .map((record) => `${record.profile.name} (${record.profile.id}) — ${this.workStore.membership(context.workId, record.profile.id).binding!.role}`);
    const capabilityLines: string[] = [];
    for (const entry of context.catalog.filter((candidate) => candidate.enabled)) {
      if (entry.kind === "skill") {
        let instructions = "";
        try {
          instructions = (await readFile(entry.manifestPath, "utf8")).slice(0, 20_000);
        } catch {
          instructions = `(Could not read ${entry.manifestPath})`;
        }
        capabilityLines.push(`### Skill: ${entry.name}\nSource: ${entry.manifestPath}\n${instructions}`);
      } else if (entry.kind === "cli") {
        capabilityLines.push(`### CLI: ${entry.name}\nCapability id: ${entry.id}\nExecutable: ${entry.executable}\nAllowed subcommands: ${entry.allowedSubcommands.join(", ") || "none; call without arguments"}\nUse RunWorkCLI; do not invoke it through a shell.`);
      } else if (entry.kind === "knowledge") {
        capabilityLines.push(`### Knowledge: ${entry.name}\nRead-only roots: ${entry.roots.join(", ")}`);
      } else {
        capabilityLines.push(`### Local tools: ${entry.name}\nEnabled tools: ${entry.toolNames.join(", ")}`);
      }
    }
    return [
      "## Current Work",
      `Name: ${work.name}`,
      `Goal: ${work.description || "(not specified)"}`,
      `Project root: ${work.projectRoot ?? "(not set)"}`,
      `Catalog revision: ${context.catalogRevision}`,
      "",
      "This run belongs to this Work. Work progress and handoff go to the shared room, not the private Agent chat.",
      task ? [
        "",
        "### Assigned task",
        `Task id: ${task.id}`,
        `Permanent owner: ${task.ownerAgentId ?? "human-created card"}. Workers: ${task.assigneeIds.join(", ") || "none"}.`,
        "DelegateWork assigns workers without changing the owner. Worker SendMessage cardAction review returns results to the owner; owner review requests human acceptance. A blocked report pauses the card until a human confirms resume. Stop after reporting review or blocked.",
        `Title: ${task.title}`,
        `Description: ${task.description || "(not specified)"}`,
        `State: ${task.state}`,
        `Acceptance criteria: ${task.acceptanceCriteria.join("; ") || "(not specified)"}`
      ].join("\n") : "",
      "",
      "### Work members",
      members.join("\n") || "(none)",
      capabilityLines.length ? `\n## Work capabilities\n${capabilityLines.join("\n\n")}` : ""
    ].filter(Boolean).join("\n");
  }

  private workTaskView(task: WorkTask): WorkTaskView {
    return {
      ...task,
      allowedTransitions: allowedTaskTransitions(task.state, "user")
    };
  }

  private async requireWorkTask(workId: string, taskId: string): Promise<WorkTask> {
    this.workStore.requireWork(workId);
    const task = projectWork(await this.workStore.readTimeline(workId)).tasks.find(
      (candidate) => candidate.id === taskId
    );
    if (!task) throw new RpcError(HostErrorCode.WORK_NOT_FOUND, `Task ${taskId} not found`);
    return task;
  }

  private assertTaskRevision(task: WorkTask, expectedRevision: number): void {
    if (task.revision === expectedRevision) return;
    throw new RpcError(
      HostErrorCode.WORK_CONFLICT,
      `Task revision is ${task.revision}, expected ${expectedRevision}`
    );
  }

  private assertMembershipRevision(actual: number, expected: number): void {
    if (actual === expected) return;
    throw new RpcError(
      HostErrorCode.WORK_CONFLICT,
      `Membership revision is ${actual}, expected ${expected}`
    );
  }

  private assertNotRunningWork(agentId: string, workId: string): void {
    const runId = this.scheduler.activeRunFor(agentId);
    if (!runId) return;
    const context = this.scheduler.contextFor(runId);
    if (context?.kind !== "work" || context.workId !== workId) return;
    throw new RpcError(
      HostErrorCode.AGENT_BUSY,
      "Stop the Agent's current Work run before removing or moving it"
    );
  }

  private async assertWorkAssignees(workId: string, agentIds: string[]): Promise<void> {
    this.workStore.requireWork(workId);
    for (const agentId of agentIds) {
      const record = this.store.requireAgent(agentId);
      if (Boolean(this.workStore.membership(workId, agentId).binding)) continue;
      throw new RpcError(HostErrorCode.WORK_CONFLICT, `Agent ${agentId} is not a member of this Work`);
    }
  }

  private assertWorkAgent(agentId: string, workId: string): AgentRecord {
    const record = this.store.requireAgent(agentId);
    if (!this.workStore.membership(workId, agentId).binding) {
      throw new RpcError(HostErrorCode.WORK_FORBIDDEN, "Agent is no longer a member of this Work");
    }
    return record;
  }

  private toolRoots(record: AgentRecord, context: RunContext = DIRECT_RUN_CONTEXT) {
    const dataParent = path.dirname(this.options.dataDir);
    return {
      home: path.resolve(process.env.NUUM_LOCAL_EXEC_ROOT || homedir()),
      project: context.kind === "work"
        ? this.workStore.getWork(context.workId).projectRoot
        : record.settings.workspace?.projectRoot ?? null,
      scratch: context.kind === "work" && context.session ? path.join(this.sessions.directory(context.session), "scratch") : this.store.scratchDir(record.profile.id),
      terminals: path.join(context.kind === "work" && context.session ? this.sessions.directory(context.session) : this.store.agentDir(record.profile.id), "terminals"),
      denied: [
        ...(context.kind === "work" && context.session ? [path.join(this.options.dataDir, "agents")] : []),
        path.join(dataParent, "secrets.bin"),
        path.join(this.options.dataDir, "host-secrets.json"),
        path.join(this.options.dataDir, "credentials.json"),
        path.join(this.options.dataDir, "secrets.json")
      ],
      readOnly: context.kind === "work"
        ? context.catalog
            .filter((entry) => entry.kind === "knowledge" && entry.enabled)
            .flatMap((entry) => entry.kind === "knowledge" ? entry.roots : [])
        : []
    };
  }

  private readonly compactJobs = new Map<string, {
    epoch: number; throughSeq: number; tailFromSeq: number; ready: boolean;
    result: Promise<string>; activeRequest?: string; session?: import("./session-store.js").CardSession;
  }>();

  private prepareCompact(agentId: string, runId: string, transcript: TranscriptEvent[], model: AgentSettings["model"], withinTurn = false) {
    const existing = this.compactJobs.get(runId);
    if (existing) return existing;
    const partition = partitionForCompaction(transcript, withinTurn);
    if (!partition || !this.kernel) return undefined;
    const session = this.cardSessionFor(agentId);
    const request = transcript.findLast(event => event.type === "user" || event.type === "wake");
    const activeRequest = request && "text" in request ? request.text : transcript.findLast(event => event.type === "compact")?.activeRequest;
    const job = { activeRequest: withinTurn ? activeRequest : undefined, epoch: transcript.findLast(event => event.type === "compact")?.epoch ?? 0,
      throughSeq: partition.throughSeq, tailFromSeq: partition.tailFromSeq, ready: false, session,
      result: Promise.resolve("") };
    const kernel = this.kernel;
    this.compactJobs.set(runId, job);
    const deadline = Date.now() + 120_000;
    job.result = summarizePrefix(kernel, {
      runId: `${runId}:compact`, messages: partition.messagesToSummarize, model, secrets: this.store.secrets,
      systemPrompt: COMPACTION_PROMPT,
      current: () => !this.disposing && Date.now() < deadline && this.compactJobs.get(runId) === job && !!this.scheduler.contextFor(runId)
    });
    void job.result.then(() => { job.ready = true; }, () => { job.ready = true; });
    this.compactJobs.set(runId, job);
    return job;
  }

  private async compact(agentId: string, runId: string, transcript: TranscriptEvent[], model: AgentSettings["model"], withinTurn = false): Promise<boolean> {
    const job = this.prepareCompact(agentId, runId, transcript, model, withinTurn);
    if (!job) return false;
    try {
      const summary = await job.result;
      const context = this.scheduler.contextFor(runId);
      if (this.compactJobs.get(runId) !== job || !context || this.disposing || (context.kind === "work" && context.bridgeId && this.cancelledExecutions.has(context.bridgeId))) return false;
      const current = await this.readModelTranscript(agentId, context);
      if ((current.compact?.epoch ?? 0) !== job.epoch) return false;
      const record = { type: "compact" as const, id: crypto.randomUUID(), createdAt: Date.now(), epoch: job.epoch + 1,
        throughSeq: job.throughSeq, tailFromSeq: job.tailFromSeq, summary, activeRequest: job.activeRequest };
      // The captured session and prefix are immutable; later events remain in the preserved tail.
      if (job.session) await this.sessions.append(job.session, record);
      else { await this.store.appendEvent(agentId, record); await this.store.bumpPromptEpoch(agentId); }
      return true;
    } finally {
      if (this.compactJobs.get(runId) === job) this.compactJobs.delete(runId);
    }
  }

  /**
   * turn 收束后的记忆抽取（§8）。**异步、不阻塞 UI、不 bump epoch** ——
   * 这条路径高频且用户无感，攒到下次压缩统一进提示词，别每轮打碎前缀缓存。
   */
  private async extractMemory(agentId: string, runId: string): Promise<void> {
    const record = this.store.getAgent(agentId);
    if (!record || !this.kernel) return;
    const { events } = await this.store.readForAssemble(agentId);
    const lastPrompt = [...events]
      .reverse()
      .find((event) => event.type === "user" || event.type === "wake");
    if (!lastPrompt) return;
    const prompt = lastPrompt.type === "user" ? lastPrompt.text : lastPrompt.text;
    if (!isMemorableExchange(prompt)) return;

    const since = events.filter((event) => event.seq >= lastPrompt.seq);
    const { text } = await this.kernel.summarize({
      runId,
      systemPrompt: EXTRACTION_PROMPT,
      messages: assembleContext({ transcript: since, systemPrompt: "" }).slice(1),
      model: record.settings.model,
      secrets: this.store.secrets
    });
    const { writes, removals } = parseExtraction(text);
    if (writes.length === 0 && removals.length === 0) return;
    const memory = new MemoryStore(this.store.memoryDir(agentId));
    for (const removal of removals) await memory.forget(removal);
    for (const entry of writes) await memory.write(entry.fact, entry.tier);
  }

  // ── Kernel 事件 ─────────────────────────────────────────────────────────

  private async onKernelEvent(method: string, raw: unknown): Promise<void> {
    const params = (raw ?? {}) as Record<string, any>;
    const runId = String(params.runId ?? "");
    // Kernel 只认 runId，agent 的归属在 Host 这边查。查不到说明该 run 已收束，
    // 迟到的事件直接丢，别把它记到别人账上。
    const agentId = this.scheduler.agentIdFor(runId);
    if (!agentId) return;

    if (method === "turn.context") {
      try {
        await this.flushAssistant(agentId);
        const context = this.scheduler.contextFor(runId)!;
        const model = resolveSessionModel({ sessionModel: this.store.requireAgent(agentId).settings.model, defaultModel: this.settings.defaultModel, secrets: this.store.secrets });
        const limit = this.contextWindow(model);
        const used = Number(params.usedTokens);
        let transcript = await this.readModelTranscript(agentId, context);
        const startAt = Math.min(limit * 0.8, limit - Math.min(10_000, limit * 0.2));
        const applyAt = Math.min(limit * 0.85, limit - Math.min(5_000, limit * 0.15));
        if (used >= startAt) this.prepareCompact(agentId, runId, transcript.events, model, true);
        const job = this.compactJobs.get(runId);
        let messages;
        if (job && (job.ready || used >= applyAt)) {
          const applied = await this.compact(agentId, runId, transcript.events, model, true);
          if (applied) {
            transcript = await this.readModelTranscript(agentId, context);
            const prompt = await this.buildSystemPrompt(agentId, true, context);
            messages = assembleContext({ transcript: transcript.events, systemPrompt: prompt.text, notices: prompt.notices });
          }
        }
        await this.kernel?.provideContext?.({ runId, requestId: String(params.requestId), messages });
      } catch (error) {
        await this.kernel?.provideContext?.({ runId, requestId: String(params.requestId), error: `Context compaction failed: ${String(error)}` });
      }
      return;
    }

    if (method === "turn.delta") {
      const part = params.part === "thinking" ? "thinking" : "text";
      const current = this.openBuffer(agentId, String(params.messageId));
      current.parts = appendAssistantDelta(current.parts, part, String(params.delta ?? ""));
      this.buffers.set(agentId, current);
      if (!this.cardSessionFor(agentId)) this.emit(HostEvents.agentMessageDelta, {
        agentId,
        runId,
        messageId: current.messageId,
        delta: params.delta,
        part
      });
      return;
    }
    if (method === "turn.tool.pending") {
      this.rememberPending(agentId, String(params.toolCallId), {
        action: params.action as LocalToolAction,
        target: String(params.target)
      });
      await this.recordToolCall(agentId, params);
      this.emit(HostEvents.agentToolPending, { ...params, agentId, runId });
      return;
    }
    if (method === "turn.tool.started") {
      await this.recordToolCall(agentId, params);
      this.emit(HostEvents.agentToolStarted, { ...params, agentId, runId });
      return;
    }
    if (method === "turn.tool.delegate") {
      const assistantId = await this.recordToolCall(agentId, params);
      await this.runDelegatedTool(agentId, runId, params, assistantId);
      return;
    }
    if (method === "turn.tool.completed") {
      // 硬拒与 anti-nag 不经过 pending/started，也一样必须把 tool_call 记下来，
      // 否则下一轮会出现孤立 tool result。
      const assistantId = await this.recordToolCall(agentId, params);
      // 序号来自内存里的 lastSeq —— 不再为了算下一个序号而整文件重读。
      const event = await this.appendRunEvent(agentId, {
        type: "tool",
        id: crypto.randomUUID(),
        assistantId,
        name: params.name,
        toolCallId: params.toolCallId,
        content: String(params.output ?? ""),
        ok: params.ok !== false,
        createdAt: Date.now()
      });
      this.forgetPending(agentId, String(params.toolCallId));
      if (!this.cardSessionFor(agentId)) this.emit(HostEvents.agentMessageCompleted, { agentId, event });
      this.emit(HostEvents.agentToolCompleted, { ...params, agentId, runId });
      return;
    }
    if (method === "turn.error") {
      this.clearAgentPending(agentId);
      this.emit(HostEvents.agentError, { ...params, agentId, runId });
      return;
    }
    if (method === "turn.ended") {
      this.compactJobs.delete(runId);
      await this.kernel?.cancelSummary?.(`${runId}:compact`);
      await this.flushAssistant(agentId);
      this.buffers.delete(agentId);
      this.recordedCalls.delete(agentId);
      this.callOrigins.delete(agentId);
      this.clearAgentPending(agentId);
      const context = this.scheduler.contextFor(runId);
      const runContext = context?.kind === "work" ? context : undefined;
      const status: "idle" | "error" | "cancelled" =
        params.status === "error" ? "error" : params.status === "cancelled" ? "cancelled" : "idle";
      // 先摘掉 run 再算派生运行态，否则 agentUpdated 里还会带着 running。
      if (runContext?.bridgeId) await this.finishWorkDispatch(agentId, runContext, status === "idle" ? "completed" : status === "error" ? "failed" : "cancelled");
      this.scheduler.settle(runId, status === "idle" ? "completed" : status === "error" ? "failed" : "cancelled");
      await this.mark(agentId, status);
      this.emit(HostEvents.agentEnded, { agentId, runId, status });
      this.wakes.closeRun(runId);
      if (status === "idle" && !runContext?.session) {
        // 抽取失败不该影响这一轮 —— 它是后台工作，用户没在等它。
        this.background(this.extractMemory(agentId, runId));
      }
      // 腾出槽位就接着跑排着的唤醒。取消路径已经把队列清了，所以只有正常
      // 收束才会有下一条。
      await this.pumpWakes(agentId);
    }
  }

  /**
   * stdio event 没有 request/response 的 await 语义。若直接调 async handler，
   * completed / ended 会交叉落盘；按 runId 串行后，seq 才是可信的发生顺序。
   */
  private enqueueKernelEvent(method: string, raw: unknown): void {
    const params = (raw ?? {}) as Record<string, unknown>;
    const runId = String(params.runId ?? "");
    const previous = this.kernelEventChains.get(runId) ?? Promise.resolve();
    const current = previous.catch(() => undefined).then(() => this.onKernelEvent(method, raw));
    this.kernelEventChains.set(runId, current);
    void current
      .catch((error) => {
        const message = error instanceof Error ? error.stack ?? error.message : String(error);
        process.stderr.write(`[nuum-host] kernel event ${method} failed: ${message}\n`);
      })
      .finally(() => {
        if (this.kernelEventChains.get(runId) === current) this.kernelEventChains.delete(runId);
      });
  }

  /** 当前工作离用户几手（护栏用）。从转录派生，见 `currentHops` 的注释。 */
  private async hopsOf(id: string): Promise<number> {
    const { entries } = await this.store.readTranscriptPage(id, undefined, HOPS_SCAN_LIMIT);
    return currentHops(entries);
  }

  /** 起下一条排着的唤醒。wake 事件早在投递时就写进转录了，这里只是起 run。 */
  private async pumpWakes(agentId: string): Promise<void> {
    if (this.scheduler.isBusy(agentId)) return;
    const next = this.wakes.dequeue(agentId);
    if (!next) return;
    this.launch(agentId, DIRECT_RUN_CONTEXT);
    const record = this.store.getAgent(agentId);
    if (record) this.emit(HostEvents.agentUpdated, { agent: await this.viewFor(record) });
  }

  /**
   * 启动时重放没被响应过的唤醒（§2.Q5）。判据在转录尾部，不需要 inbox 文件：
   * 末条 `wake` 之后没有 assistant / message 就说明上次没跑完。
   */
  private async replayPendingWakes(): Promise<void> {
    for (const record of this.store.listAgents()) {
      const id = record.profile.id;
      const { entries } = await this.store.readTranscriptPage(id, undefined, 20);
      const wake = pendingWake(entries);
      if (!wake) continue;
      if (this.scheduler.isBusy(id)) this.wakes.enqueue(id, wake);
      else this.launch(id, DIRECT_RUN_CONTEXT);
    }
  }

  /**
   * 后台任务。记账是为了让 `dispose()` 能等它们结束：不等的话进程退出时
   * 半写的记忆文件会留在磁盘上，而测试里则会漏出「测试结束后还在写文件」。
   */
  private background(work: Promise<unknown>): void {
    const tracked = work.catch(() => undefined).finally(() => this.pending.delete(tracked));
    this.pending.add(tracked);
  }

  /**
   * 委派工具的往返：Host 执行完把结果塞回 Kernel，Kernel 接着跑 loop。
   * 无论成败都必须回一条结果，否则那个 run 会永远卡在等待里。
   */
  private async runDelegatedTool(
    agentId: string,
    runId: string,
    params: Record<string, any>,
    assistantId: string
  ): Promise<void> {
    const name = String(params.name ?? "");
    const toolCallId = String(params.toolCallId ?? "");
    const tool = this.delegated.get(name);
    const runContext = this.scheduler.contextFor(runId);
    let ok = true;
    let output: string;
    if (!runContext) {
      ok = false;
      output = `Run ${runId} has already ended.`;
    } else if (!tool) {
      ok = false;
      output = `Unknown delegated tool: ${name}`;
    } else if (!isDelegatedToolAvailable(tool, runContext)) {
      ok = false;
      output = `${name} is not available in a ${runContext.kind} run.`;
    } else {
      try {
        if (runContext.kind === "work") this.assertWorkRunCurrent(runContext, agentId);
        output = await tool.execute((params.arguments ?? {}) as Record<string, unknown>, {
          agentId,
          assistantId,
          toolCallId,
          runContext
        });
      } catch (error) {
        ok = false;
        output = error instanceof Error ? error.message : String(error);
      }
    }
    const endTurn = ok && runContext?.kind === "work" && (
      name === DelegatedToolNames.delegateWork ||
      (name === DelegatedToolNames.sendMessage && !!params.arguments?.cardAction) ||
      (runContext.discussionId !== undefined && name === DelegatedToolNames.sendMessage &&
        (isPass(String(params.arguments?.content ?? "")) || (this.discussions.get(runContext.workId)?.perExecution.get(runContext.bridgeId!) ?? 0) >= discussionLimits.perTurn))
    );
    await this.kernel?.provideToolResult({ runId, toolCallId, ok, output, ...(endTurn ? { endTurn: true } : {}) });
  }

  // ── 派生视图 ────────────────────────────────────────────────────────────

  private async viewFor(record: AgentRecord, workId?: string): Promise<AgentView> {
    return {
      profile: record.profile,
      settings: { ...record.settings, workMembership: workId ? this.workStore.membership(workId, record.profile.id) : undefined },
      roomMemberships: this.workStore.membershipsFor(record.profile.id),
      runtime: await this.runtimeFor(record.profile.id, record.lastActivityAt)
    };
  }

  private async runtimeFor(id: string, lastActivityAt: number): Promise<AgentRuntimeView> {
    const activeRunId = this.scheduler.activeRunFor(id);
    return {
      ...(activeRunId ? { activeRunId } : {}),
      status: this.scheduler.isBusy(id) ? "running" : this.errored.has(id) ? "error" : "idle",
      unread: await this.store.isUnread(id),
      lastActivityAt
    };
  }

  /**
   * 只读模型活跃窗口。缺失的 tool result 由 assembleContext 纯投影修补，
   * 不追加回 JSONL：「推断为中断」不是真实发生的交互。
   */
  private readModelTranscript(id: string, context?: RunContext): Promise<{
    events: TranscriptEvent[];
    compact?: Extract<TranscriptEvent, { type: "compact" }>;
  }> {
    return context?.kind === "work" && context.session
      ? this.sessions.readForAssemble(context.session)
      : this.store.readForAssemble(id);
  }

  private assertWorkRunCurrent(context: Extract<RunContext, { kind: "work" }>, agentId: string) {
    const membership = this.workStore.membership(context.workId, agentId);
    if (!membership.binding?.grants.canPost || (context.membershipRevision !== undefined && membership.revision !== context.membershipRevision)) throw new Error("Room membership changed");
    if (!context.bridgeId) return;
    const submitted = this.submittedWork.get(context.bridgeId);
    if (this.cancelledExecutions.has(context.bridgeId) || !submitted || !this.scheduler.contextFor(submitted.runId)) throw new Error("Work execution has stopped");
  }

  private async prepareWorkInput(agentId: string, context: Extract<RunContext, { kind: "work" }>, runId: string): Promise<void> {
    if (!context.bridgeId) return;
    this.assertWorkAgent(agentId, context.workId);
    const roomEvents = await this.workStore.readTimeline(context.workId);
    if (context.discussionId) {
      const live = this.discussions.get(context.workId);
      if (!live || live.id !== context.discussionId || live.stopped || live.superseded) throw new Error("Discussion stopped before this member started");
      live.hasStarted = true;
    }
    if (this.cancelledExecutions.has(context.bridgeId) || this.disposing) throw new Error("Execution cancelled");
    if (this.workStore.membership(context.workId, agentId).revision !== context.membershipRevision) throw new Error("Work membership changed before execution");
    if (context.taskId) {
      const task = await this.requireWorkTask(context.workId, context.taskId);
      const source = roomEvents.find(event => event.id === context.triggerEventId);
      if (!source || !currentCardSource(roomEvents, source, context.taskId) || (task.ownerAgentId !== agentId && !task.assigneeIds.includes(agentId)) || task.state !== "in_progress") {
        throw new RpcError(HostErrorCode.WORK_CONFLICT, "Card is no longer assigned for execution; resume or reassign it before dispatching");
      }
    }
    await this.appendWorkEvent(context.workId, {
      type: "execution.started", id: `start:${context.bridgeId}`, clientEventId: `start:${context.bridgeId}`,
      workId: context.workId, createdAt: Date.now(), actor: { kind: "system", id: "host" }, executionId: context.bridgeId,
      sourceEventId: context.triggerEventId, agentId, taskId: context.taskId, sessionId: context.session?.id ?? `main:${agentId}`,
      runId, membershipRevision: context.membershipRevision!
    });
    const existingInput = await this.readModelTranscript(agentId, context);
    if (existingInput.events.some(event => event.id === context.bridgeId)) return;
    const makeDraft = (events: TranscriptEvent[]): TranscriptDraft => {
      let text = context.instruction ?? "Read the room and respond if you have something useful to add.";
      let received;
      if (!context.session) {
        const source = roomEvents.find(event => event.id === context.triggerEventId);
        const triggers = source?.type === "discussion.started" ? source.triggerEventIds : [context.triggerEventId];
        const input = selectRoomInput(roomEvents, events, context.workId, context.membershipRevision!, triggers, context.inputAfterSeq);
        received = { membershipRevision: context.membershipRevision!, fromSeq: input.fromSeq, throughSeq: input.throughSeq,
          messageIds: input.messages.map(message => message.messageId), epoch: input.epoch, mode: input.mode };
        text = [`Room ${context.workId}: ${input.mode === "background" ? "Recent historical background; older messages may be omitted. ReadWorkTimeline can retrieve them." : "New room messages since your previous input."}`,
          ...input.messages.map(message => `[${message.seq} ${message.actor.kind}:${message.actor.id} message:${message.messageId}] ${message.body}`),
          `Current trigger: ${text}`].join("\n\n");
      }
      return { type: "wake", id: context.bridgeId!, createdAt: Date.now(), hops: 0, text,
        source: { kind: "work", workId: context.workId, workName: this.workStore.getWork(context.workId).name, bridgeId: context.bridgeId!, taskId: context.taskId, ...(received ? { roomInput: received } : {}) } };
    };
    // Check capacity before committing an input receipt. Compact only already received history.
    const record = this.store.requireAgent(agentId);
    const model = resolveSessionModel({ sessionModel: record.settings.model, defaultModel: this.settings.defaultModel, secrets: this.store.secrets });
    let transcript = await this.readModelTranscript(agentId, context);
    let draft = makeDraft(transcript.events);
    let prompt = await this.buildSystemPrompt(agentId, Boolean(transcript.compact), context);
    const size = () => estimateContextTokens(assembleContext({ transcript: [...transcript.events, { ...draft, seq: (transcript.events.at(-1)?.seq ?? 0) + 1 } as TranscriptEvent], systemPrompt: prompt.text, notices: prompt.notices }));
    if (size() > this.contextWindow(model) * 0.75) {
      try { await this.compact(agentId, runId, transcript.events, model); } catch { /* No receipt is committed if compaction cannot make room. */ }
      transcript = await this.readModelTranscript(agentId, context);
      draft = makeDraft(transcript.events);
      prompt = await this.buildSystemPrompt(agentId, Boolean(transcript.compact), context);
      if (size() > this.contextWindow(model) * 0.75) throw new Error("Room context is too large. No new room input was consumed; narrow the history range before continuing.");
    }
    const event = context.session ? await this.sessions.append(context.session, draft) : await this.store.appendEvent(agentId, draft);
    if (!context.session) this.emit(HostEvents.agentMessageCompleted, { agentId, event });
  }

  private async finishWorkDispatch(agentId: string, context: Extract<RunContext, { kind: "work" }>, status: "completed" | "failed" | "cancelled", error?: string) {
    return this.inRoom(context.workId, async () => {
    const previous = (await this.workStore.readTimeline(context.workId)).find(event => event.type === "execution.finished" && event.executionId === context.bridgeId);
    if (previous) return;
    if (this.cancelledExecutions.has(context.bridgeId!)) status = "cancelled";
    await this.appendWorkEvent(context.workId, {
      type: "execution.finished", id: `finish:${context.bridgeId}`, clientEventId: `finish:${context.bridgeId}`,
      workId: context.workId, createdAt: Date.now(), actor: { kind: "system", id: "host" },
      executionId: context.bridgeId!, sourceEventId: context.triggerEventId, agentId, taskId: context.taskId, status, error
    });
    });
  }

  private workInterruptions(events: WorkEvent[]): WorkSnapshot["interruptions"] {
    const result: WorkSnapshot["interruptions"] = [];
    const resumed = new Set(events.filter(event => event.type === "work.requested").map(event => event.resumesExecutionId));
    for (const event of events) {
      if (event.type === "history.imported") {
        const uncertain = events.filter(item => event.unconfirmedEventIds.includes(item.id));
        if (uncertain.some(item => item.type === "chat.posted") && !events.some(item => item.clientEventId === `continue:${event.id}`)) result.push({ kind: "discussion", eventId: event.id, error: "Previous room history is preserved. Continue only if this discussion still needs a response." });
        for (const source of uncertain) {
          const task = "taskId" in source && source.taskId ? projectWork(events).tasks.find(task => task.id === source.taskId) : undefined;
          const intent = workIntent(source, task);
          if (intent && task?.state === "in_progress" && currentCardSource(events, source, task.id) && !resumed.has(source.id)) result.push({ kind: "execution", eventId: source.id, agentId: intent.agentId, taskId: intent.taskId, error: "Legacy execution requires confirmation before continuing." });
        }
      }
      if (event.type === "discussion.started") {
        const ended = events.find(item => item.type === "discussion.finished" && item.discussionId === event.id);
        const continued = events.some(item => item.type === "chat.posted" && item.clientEventId === `continue:${event.id}`);
        if (!continued && (!ended || (ended.type === "discussion.finished" && ended.status === "interrupted")) && this.discussions.get(event.workId)?.id !== event.id) result.push({ kind: "discussion", eventId: event.id, error: [...events].reverse().find((item): item is Extract<WorkEvent, { type: "execution.finished" }> => item.type === "execution.finished" && item.sourceEventId === event.id && item.status === "failed")?.error ?? (ended?.type === "discussion.finished" ? ended.error : undefined) ?? "Discussion interrupted. Continue starts a new bounded discussion." });
      }
      if (event.type === "execution.started" || event.type === "execution.finished") {
        if (resumed.has(event.executionId) || this.submittedWork.has(event.executionId)) continue;
        const source = events.find(item => item.id === event.sourceEventId);
        if (source?.type === "discussion.started") continue;
        const end = events.find(item => item.type === "execution.finished" && item.executionId === event.executionId);
        if (event.type === "execution.started" && end) continue;
        if (event.type === "execution.finished" && event.status !== "failed" && !(event.status === "completed" && event.taskId && source && currentCardSource(events, source, event.taskId))) continue;
        if (source && event.taskId && !currentCardSource(events, source, event.taskId)) continue;
        result.push({ kind: "execution", eventId: event.id, agentId: event.agentId, taskId: event.taskId, error: event.type === "execution.finished" ? event.error ?? (event.status === "completed" ? "Card execution ended without a handoff. Continue or cancel the card." : "Execution failed. Check the result before continuing.") : "Execution interrupted. Check tools and published results before continuing." });
      }
      if (event.type === "dispatch.requested" && !resumed.has(event.bridgeId) && !events.some(item => item.type === "chat.posted" && item.clientEventId === `continue:${event.id}`)) {
        const end = events.find(item => item.type === "dispatch.finished" && item.bridgeId === event.bridgeId);
        if (!end || (end.type === "dispatch.finished" && end.status === "failed")) result.push({ kind: "execution", eventId: event.id, agentId: event.agentId, taskId: event.taskId, error: "Legacy execution requires confirmation before continuing." });
      }
    }
    return result;
  }

  async continueWork(workId: string, eventId: string, inputAfterSeq?: number): Promise<{ ok: true }> {
    const events = await this.workStore.readTimeline(workId);
    if (inputAfterSeq !== undefined && (!Number.isSafeInteger(inputAfterSeq) || inputAfterSeq < 0 || inputAfterSeq > (events.at(-1)?.seq ?? 0))) throw new Error("Invalid room history start sequence");
    const event = events.find(item => item.id === eventId);
    if (!event || !this.workInterruptions(events).some(item => item.eventId === eventId)) throw new Error("This work no longer needs continuation");
    if (event.type === "history.imported" || event.type === "discussion.started" || (event.type === "dispatch.requested" && event.discussion)) {
      if (event.type === "discussion.started" && !events.some(item => item.type === "discussion.finished" && item.discussionId === event.id)) await this.endDiscussion(workId, event.id, "interrupted");

      await this.postWorkMessage({ workId, body: "Continue the interrupted discussion, using the existing room history.", mentionedAgentIds: [], inputAfterSeq, clientEventId: `continue:${eventId}` });
      return { ok: true };
    }
    const source = event.type === "execution.started" || event.type === "execution.finished" ? events.find(item => item.id === event.sourceEventId) : event;
    if (!source) throw new Error("Missing work source");
    const task = "taskId" in source && source.taskId ? await this.requireWorkTask(workId, source.taskId) : undefined;
    const intent = workIntent(source, task);
    if (!intent || (task && task.state !== "in_progress")) throw new Error("Resume the card state before continuing execution");
    await this.inRoom(workId, async () => {
      const request = await this.appendWorkEvent(workId, {
        type: "work.requested", id: crypto.randomUUID(), clientEventId: `continue:${eventId}`, workId, createdAt: Date.now(), actor: { kind: "user", id: "local-user" }, ...intent, inputAfterSeq,
        membershipRevision: this.workStore.membership(workId, intent.agentId).revision,
        resumesExecutionId: event.type === "dispatch.requested" ? event.bridgeId : "executionId" in event ? event.executionId : event.id
      });
      await this.deliverCardEventNow(request);
    });
    return { ok: true };
  }

  private async replayWorkDispatches(): Promise<void> {
    for (const work of this.workStore.listWorks()) {
      const events = await this.workStore.readTimeline(work.id);
      const handled = new Set(events.flatMap(event => event.type === "history.imported" ? event.unconfirmedEventIds : event.type === "discussion.started" ? event.triggerEventIds : event.type === "dispatch.requested" && event.discussion ? [event.discussion.rootId] : []));
      for (const event of events) {
        if (event.type === "chat.posted" && event.actor.kind === "user" && !handled.has(event.id)) this.enqueueDiscussion(event);
        if (["task.delegated", "task.handed_off", "task.transitioned", "work.requested"].includes(event.type)) await this.deliverCardEvent(event);
      }
    }
  }

  private cardSessionFor(agentId: string) {
    const runId = this.scheduler.activeRunFor(agentId);
    const context = runId ? this.scheduler.contextFor(runId) : undefined;
    return context?.kind === "work" ? context.session : undefined;
  }

  private appendRunEvent(agentId: string, draft: TranscriptDraft) {
    const session = this.cardSessionFor(agentId);
    return session ? this.sessions.append(session, draft) : this.store.appendEvent(agentId, draft);
  }

  private agentHasPending(id: string): boolean {
    return (this.pendingByAgent.get(id)?.size ?? 0) > 0;
  }

  private rememberPending(agentId: string, toolCallId: string, approval: ToolApproval): void {
    this.pendingTools.set(pendingKey(agentId, toolCallId), approval);
    const current = this.pendingByAgent.get(agentId) ?? new Set<string>();
    current.add(toolCallId);
    this.pendingByAgent.set(agentId, current);
  }

  private forgetPending(agentId: string, toolCallId: string): void {
    this.pendingTools.delete(pendingKey(agentId, toolCallId));
    const current = this.pendingByAgent.get(agentId);
    if (!current) return;
    current.delete(toolCallId);
    if (current.size === 0) this.pendingByAgent.delete(agentId);
  }

  private clearAgentPending(agentId: string): void {
    const current = this.pendingByAgent.get(agentId);
    if (current) {
      for (const toolCallId of current) this.pendingTools.delete(pendingKey(agentId, toolCallId));
    }
    this.pendingByAgent.delete(agentId);
  }

  /**
   * 把一次工具调用记进在写的 assistant 事件，然后收口。
   *
   * 必须对**每个**工具都做，不只是要审批的那些。否则转录里会留下一条没有对应
   * `tool_call` 的孤立 tool 结果 —— 下一轮 assemble 就会给 provider 发一条
   * 「凭空冒出来的 tool 消息」，OpenAI 兼容接口一律 400。而且不收口的话
   * assistant 事件会排在它自己的 tool 结果之后，顺序也是反的。
   *
   * 幂等：mutating 工具先走 pending 再走 started，同一个 toolCallId 只记一次。
   */
  private async recordToolCall(agentId: string, params: Record<string, any>): Promise<string> {
    const toolCallId = String(params.toolCallId ?? "");
    const recorded = this.recordedCalls.get(agentId) ?? new Set<string>();
    const origins = this.callOrigins.get(agentId) ?? new Map<string, string>();
    if (recorded.has(toolCallId)) {
      return origins.get(toolCallId) ?? String(params.messageId ?? toolCallId);
    }
    recorded.add(toolCallId);
    this.recordedCalls.set(agentId, recorded);

    const existing = this.buffers.get(agentId);
    const current = this.openBuffer(
      agentId,
      existing && !existing.flushed ? existing.messageId : crypto.randomUUID()
    );
    current.parts = appendAssistantToolCall(current.parts, {
      id: toolCallId,
      name: String(params.name),
      arguments: params.arguments ?? {}
    });
    origins.set(toolCallId, current.messageId);
    this.callOrigins.set(agentId, origins);
    this.buffers.set(agentId, current);
    await this.flushAssistant(agentId);
    return current.messageId;
  }

  private openBuffer(agentId: string, messageId: string) {
    const existing = this.buffers.get(agentId);
    if (existing && !existing.flushed && existing.messageId === messageId) return existing;
    return { messageId, parts: [] as AssistantPart[] };
  }

  private liveFor(id: string) {
    if (this.cardSessionFor(id)) return null;
    const buffer = this.buffers.get(id);
    if (!buffer || buffer.flushed) return null;
    return { messageId: buffer.messageId, parts: buffer.parts };
  }

  private async flushAssistant(agentId: string): Promise<void> {
    const buffer = this.buffers.get(agentId);
    if (!buffer || buffer.flushed) return;
    buffer.flushed = true;
    const event = await this.appendRunEvent(agentId, {
      type: "assistant",
      id: buffer.messageId,
      parts: buffer.parts,
      createdAt: Date.now()
    });
    if (!this.cardSessionFor(agentId)) this.emit(HostEvents.agentMessageCompleted, { agentId, event });
  }

  private async mark(id: string, status: "idle" | "error" | "cancelled"): Promise<void> {
    if (status === "error") this.errored.add(id);
    else this.errored.delete(id);
    const record = this.store.getAgent(id);
    if (!record) return;
    this.emit(HostEvents.agentUpdated, { agent: await this.viewFor(record) });
  }
}

function currentMembership(record: AgentRecord): NonNullable<AgentSettings["workMembership"]> {
  return record.settings.workMembership ?? { revision: 0, binding: null };
}

function grantsForRole(role: WorkRole) {
  if (role === "coordinator") {
    return {
      canPost: true,
      canManageOwnTasks: true,
      canAssignTasks: true,
      canEditCatalog: true
    };
  }
  if (role === "worker") {
    return {
      canPost: true,
      canManageOwnTasks: true,
      canAssignTasks: false,
      canEditCatalog: false
    };
  }
  return {
    canPost: false,
    canManageOwnTasks: false,
    canAssignTasks: false,
    canEditCatalog: false
  };
}

function requireWorkRun(context: RunContext): Extract<RunContext, { kind: "work" }> {
  if (context.kind !== "work") {
    throw new RpcError(HostErrorCode.WORK_FORBIDDEN, "This tool is only available during a Work run");
  }
  return context;
}

function renderWorkEventForAgent(event: WorkEvent): string {
  if (event.type === "chat.posted") return `[${event.actor.kind}:${event.actor.id}] ${event.body}`;
  if (event.type === "task.created") return `[task] Created ${event.task.id}: ${event.task.title}`;
  if (event.type === "task.delegated") return `[task] ${event.taskId} worker ${event.agentId}: ${event.instruction}`;
  if (event.type === "task.claimed") return `[task] ${event.taskId}: ${event.body}`;
  if (event.type === "task.assigned") return `[task] ${event.taskId} assigned to ${event.assigneeIds.join(", ") || "nobody"}`;
  if (event.type === "task.transitioned") return `[task] ${event.taskId}: ${event.from} -> ${event.to}`;
  if (event.type === "task.progressed") return `[task] ${event.taskId}: ${event.summary}`;
  if (event.type === "task.handed_off") return `[handoff] ${event.taskId} -> ${event.nextStatus}: ${event.summary}`;
  if (event.type === "dispatch.requested") return `[dispatch] ${event.agentId}: ${event.instruction}`;
  if (event.type === "member.attached") return `[member] ${event.agentId} joined as ${event.role}`;
  if (event.type === "member.detached") return `[member] ${event.agentId} left`;
  return `[${event.type}] ${"agentId" in event ? event.agentId : event.actor.id}`;
}

/**
 * 把对方的事件渲染成一行给同伴看的话。给的是**投影**而不是原始事件：
 * 队友要知道那边说了什么、干了什么，不需要它的 thinking。
 */
function renderForPeer(event: TranscriptEvent, name: string): string[] {
  if (event.type === "user") return [`user: ${event.text}`];
  if (event.type === "wake") return [`${describeWake(event)}`];
  if (event.type === "message") return [`${name}: ${describeOutbound(event.payload)}`];
  if (event.type === "tool") {
    // 迁移期生成的补洞行和消息控制工具都不是对方聊天里的可见更新。
    if (event.id.startsWith("missing-tool-") || event.content === "Tool call was interrupted and did not return a result.") {
      return [];
    }
    if (event.name === "SendMessage" || event.name === "SendToAgent" || event.name === "ReadAgentTranscript") return [];
    return [`${name} ran ${event.name} → ${truncate(event.content, 200)}`];
  }
  if (event.type === "profile") return [`${name} changed its profile.`];
  if (event.type === "compact") return ["(earlier messages were summarized)"];
  // assistant 事件里只有草稿与 thinking，对同伴没有信息量，跳过。
  return [];
}

function truncate(text: string, limit: number): string {
  const flat = text.replace(/\s+/g, " ").trim();
  return flat.length <= limit ? flat : `${flat.slice(0, limit)}…`;
}

/** 权限档位要进提示词，模型才知道自己会不会被审批卡拦。 */
function describePermission(permission: ToolPermission): string {
  if (permission === "always") {
    return "always allow local tool actions inside the hard local-execution boundary; protected host state and destructive commands remain blocked.";
  }
  if (permission === "never") return "never allow local tool actions outside pre-approved project and scratch paths.";
  return "ask before each new local action outside project and scratch; exact approvals can be remembered, and denials are not asked again.";
}

function sameApproval(left: ToolApproval, right: ToolApproval): boolean {
  return left.action === right.action && left.target === right.target;
}

function pendingKey(agentId: string, toolCallId: string): string {
  return `${agentId}\0${toolCallId}`;
}

function settleWithin(promise: Promise<void>, timeoutMs: number): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, timeoutMs);
    void promise.finally(() => {
      clearTimeout(timer);
      resolve();
    });
  });
}
