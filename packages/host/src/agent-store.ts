import { mkdir, open, readFile, readdir, rename, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  AgentProfile,
  AgentSettings,
  DEFAULT_SETTINGS,
  HostErrorCode,
  RpcError,
  Settings,
  ToolApproval,
  ToolPermission,
  maxTranscriptSeq,
  tryParseTranscriptLine,
  type PublicSettings,
  type Secrets,
  type TranscriptDraft,
  type TranscriptEvent
} from "@nuum/protocol";

/** 追加时按需读取的尾窗大小。转录行远小于此，一窗足以定位末条 seq。 */
const TAIL_WINDOW = 64 * 1024;
const DEFAULT_PAGE_LIMIT = 200;
const MIGRATION_VERSION = 3;

export interface AgentRecord {
  profile: AgentProfile;
  settings: AgentSettings;
  /**
   * 末条事件的 createdAt，以 profile.createdAt 兜底。派生，不落盘。
   *
   * 不用文件 mtime：那是文件系统元数据，备份恢复 / rsync / checkout 都会把它抹平，
   * 侧栏顺序就会乱。取 max 是为了让「没有事件的 agent」和「迁移来的 agent」也有
   * 正确的位置 —— 迁移时 profile.createdAt 承接了旧 meta 的 updatedAt。
   */
  lastActivityAt: number;
}

export interface AgentApprovals {
  always: ToolApproval[];
  refused: ToolApproval[];
}

/**
 * 冻结的提示词段。`epoch` 是当前 epoch，快照按定义就是在这个 epoch 上取的，
 * 所以 bump 时直接把快照丢掉，不用再比对版本号。
 */
export interface PromptCache {
  epoch: number;
  profile?: { render: string; identity: { name: string; description: string; tags?: string[] } };
  /** 冻结的记忆段。记忆真源始终是 memory/*.md，这里只是渲染结果的快照。 */
  memory?: string;
}

interface TailState {
  lastSeq: number;
  /** 末条事件的 createdAt，无事件时为 0。 */
  lastEventAt: number;
  /** 已读游标，unread 由它与 lastSeq 比对派生。 */
  cursorSeq: number;
}

export class AgentStore {
  secrets: Secrets = {};
  private readonly agents = new Map<string, AgentRecord>();
  private readonly tails = new Map<string, TailState>();
  private readonly appendChains = new Map<string, Promise<unknown>>();
  private lockHandle: Awaited<ReturnType<typeof open>> | null = null;

  constructor(readonly dataDir: string) {}

  async init(): Promise<void> {
    await mkdir(this.dataDir, { recursive: true });
    await this.acquireLock();
    await this.migrate();
    await mkdir(this.agentsRoot(), { recursive: true });
    await this.scanAgents();
  }

  async dispose(): Promise<void> {
    const handle = this.lockHandle;
    this.lockHandle = null;
    if (!handle) return;
    await handle.close().catch(() => undefined);
    await rm(this.lockPath(), { force: true }).catch(() => undefined);
  }

  // ── 路径 ────────────────────────────────────────────────────────────────

  private lockPath(): string {
    return path.join(this.dataDir, "host.lock");
  }

  private agentsRoot(): string {
    return path.join(this.dataDir, "agents");
  }

  agentDir(id: string): string {
    return path.join(this.agentsRoot(), id);
  }

  private transcriptPath(id: string): string {
    return path.join(this.agentDir(id), "transcript.jsonl");
  }

  transcriptFile(id: string): string {
    return this.transcriptPath(id);
  }

  memoryDir(id: string): string {
    return path.join(this.agentDir(id), "memory");
  }

  scratchDir(id: string): string {
    return path.join(this.agentDir(id), "scratch");
  }

  // ── 单实例锁 ────────────────────────────────────────────────────────────

  private async acquireLock(): Promise<void> {
    try {
      this.lockHandle = await open(this.lockPath(), "wx");
      await this.lockHandle.writeFile(JSON.stringify({ pid: process.pid, at: Date.now() }));
      return;
    } catch (error) {
      if ((error as { code?: string }).code !== "EEXIST") throw error;
    }
    // 陈旧锁：持有者已不在则接管，否则拒绝启动而不是静默双写同一份转录。
    const owner = await readFile(this.lockPath(), "utf8").catch(() => "");
    const pid = Number((JSON.parse(owner || "{}") as { pid?: number }).pid);
    if (Number.isFinite(pid) && pid > 0 && processAlive(pid)) {
      throw new RpcError(
        HostErrorCode.DATA_DIR_LOCKED,
        `Another Nuum host (pid ${pid}) already owns ${this.dataDir}`
      );
    }
    await rm(this.lockPath(), { force: true });
    this.lockHandle = await open(this.lockPath(), "wx");
    await this.lockHandle.writeFile(JSON.stringify({ pid: process.pid, at: Date.now() }));
  }

  // ── 全局设置 ────────────────────────────────────────────────────────────

  async readSettings(): Promise<Settings> {
    try {
      const raw = JSON.parse(await readFile(path.join(this.dataDir, "settings.json"), "utf8"));
      return Settings.parse({ ...DEFAULT_SETTINGS, ...raw });
    } catch {
      return { ...DEFAULT_SETTINGS };
    }
  }

  async writeSettings(settings: Settings): Promise<void> {
    await writeJsonAtomic(path.join(this.dataDir, "settings.json"), settings);
  }

  publicSettings(settings: Settings): PublicSettings {
    return {
      ...settings,
      hasOpenaiKey: Boolean(this.secrets.openaiApiKey),
      hasAnthropicKey: Boolean(this.secrets.anthropicApiKey),
      hasDeepseekKey: Boolean(this.secrets.deepseekApiKey)
    };
  }

  // ── agent 名录（内存即唯一来源，不存 index 文件）────────────────────────

  private async scanAgents(): Promise<void> {
    this.agents.clear();
    let names: string[];
    try {
      names = await readdir(this.agentsRoot());
    } catch {
      return;
    }
    for (const id of names) {
      const record = await this.readAgentDir(id);
      if (record) this.agents.set(id, record);
    }
  }

  private async readAgentDir(id: string): Promise<AgentRecord | null> {
    const profile = await readJson(path.join(this.agentDir(id), "profile.json"), AgentProfile);
    if (!profile) return null;
    const settings =
      (await readJson(path.join(this.agentDir(id), "settings.json"), AgentSettings)) ??
      ({ model: DEFAULT_SETTINGS.defaultModel } satisfies AgentSettings);
    // 启动时就读尾：一次读同时拿到排序用的时间戳、lastSeq，并顺手修掉上次
    // 非正常退出留下的半行。读取量按尾窗封顶，与历史长度无关。
    const tail = await this.loadTail(id);
    return {
      profile,
      settings,
      lastActivityAt: Math.max(tail.lastEventAt, profile.createdAt)
    };
  }

  listAgents(): AgentRecord[] {
    return [...this.agents.values()].sort((a, b) => b.lastActivityAt - a.lastActivityAt);
  }

  getAgent(id: string): AgentRecord | null {
    return this.agents.get(id) ?? null;
  }

  requireAgent(id: string): AgentRecord {
    const record = this.agents.get(id);
    if (!record) throw new RpcError(HostErrorCode.AGENT_NOT_FOUND, "Agent not found");
    return record;
  }

  async createAgent(profile: AgentProfile, settings: AgentSettings): Promise<AgentRecord> {
    await mkdir(this.agentDir(profile.id), { recursive: true });
    await writeJsonAtomic(path.join(this.agentDir(profile.id), "profile.json"), profile);
    await writeJsonAtomic(path.join(this.agentDir(profile.id), "settings.json"), settings);
    const record: AgentRecord = { profile, settings, lastActivityAt: profile.createdAt };
    this.agents.set(profile.id, record);
    this.tails.set(profile.id, { lastSeq: 0, lastEventAt: 0, cursorSeq: 0 });
    return record;
  }

  async updateAgent(
    id: string,
    patch: { profile?: Partial<AgentProfile>; settings?: Partial<AgentSettings> }
  ): Promise<AgentRecord> {
    const current = this.requireAgent(id);
    const next: AgentRecord = {
      profile: { ...current.profile, ...patch.profile, id: current.profile.id },
      settings: { ...current.settings, ...patch.settings },
      lastActivityAt: current.lastActivityAt
    };
    if (patch.profile) await writeJsonAtomic(path.join(this.agentDir(id), "profile.json"), next.profile);
    if (patch.settings) await writeJsonAtomic(path.join(this.agentDir(id), "settings.json"), next.settings);
    this.agents.set(id, next);
    return next;
  }

  async deleteAgent(id: string): Promise<void> {
    await rm(this.agentDir(id), { recursive: true, force: true });
    this.agents.delete(id);
    this.tails.delete(id);
    this.appendChains.delete(id);
  }

  // ── 转录 ────────────────────────────────────────────────────────────────

  /**
   * 追加一条事件。seq 由内存里的 lastSeq 自增得出，不读文件；同一 agent 的追加
   * 串行化，保证落盘顺序与调用顺序一致。
   */
  appendEvent(id: string, draft: TranscriptDraft): Promise<TranscriptEvent> {
    return this.chain(id, async () => {
      const tail = await this.loadTail(id);
      const event = { ...draft, seq: tail.lastSeq + 1 } as TranscriptEvent;
      const file = this.transcriptPath(id);
      await mkdir(path.dirname(file), { recursive: true });
      const handle = await open(file, "a");
      try {
        await handle.writeFile(`${JSON.stringify(event)}\n`);
        await handle.sync();
      } finally {
        await handle.close();
      }
      tail.lastSeq = event.seq;
      tail.lastEventAt = event.createdAt;
      const record = this.agents.get(id);
      if (record) {
        this.agents.set(id, { ...record, lastActivityAt: Math.max(record.lastActivityAt, event.createdAt) });
      }
      return event;
    });
  }

  /** 整份读取。仅用于 UI 全史与显式导出，逐行容错。 */
  async readTranscript(id: string): Promise<TranscriptEvent[]> {
    let raw: string;
    try {
      raw = await readFile(this.transcriptPath(id), "utf8");
    } catch {
      return [];
    }
    const events: TranscriptEvent[] = [];
    for (const line of raw.split("\n")) {
      if (!line.trim()) continue;
      const event = tryParseTranscriptLine(line);
      if (event) events.push(event);
    }
    return events;
  }

  /**
   * 读取模型活跃窗口。没有 compact 时不得不读到文件头；有检查点后从 EOF 倒扫，
   * 找到最后一条 compact，再只补齐它声明的 preserved tail。返回顺序是逻辑模型
   * 顺序（summary 在 tail 前），不是 compact 事件在 JSONL 里的物理追加位置。
   */
  async readForAssemble(
    id: string
  ): Promise<{ events: TranscriptEvent[]; compact?: Extract<TranscriptEvent, { type: "compact" }> }> {
    const newer: TranscriptEvent[] = [];
    let compact: Extract<TranscriptEvent, { type: "compact" }> | undefined;
    const preserved: TranscriptEvent[] = [];
    for await (const line of readLinesBackward(this.transcriptPath(id))) {
      const event = tryParseTranscriptLine(line);
      if (!event) continue;
      if (!compact) {
        if (event.type === "compact") {
          compact = event;
          continue;
        }
        newer.push(event);
        continue;
      }
      if (event.seq < compact.tailFromSeq) break;
      if (event.type !== "compact") preserved.push(event);
    }
    if (!compact) return { events: newer.reverse() };
    preserved.reverse();
    newer.reverse();
    return { events: [compact, ...preserved, ...newer], compact };
  }

  /**
   * 从文件尾部往前分块读，凑够一页就停 —— 读取量由页大小决定，与历史长度无关。
   */
  async readTranscriptPage(
    id: string,
    beforeSeq?: number,
    limit = DEFAULT_PAGE_LIMIT
  ): Promise<{ entries: TranscriptEvent[]; nextBeforeSeq?: number }> {
    const collected: TranscriptEvent[] = [];
    let hasMore = false;
    for await (const line of readLinesBackward(this.transcriptPath(id))) {
      const event = tryParseTranscriptLine(line);
      if (!event) continue;
      if (beforeSeq !== undefined && event.seq >= beforeSeq) continue;
      if (collected.length === limit) {
        hasMore = true;
        break;
      }
      collected.push(event);
    }
    collected.reverse();
    const oldest = collected[0]?.seq;
    return {
      entries: collected,
      ...(hasMore && oldest !== undefined ? { nextBeforeSeq: oldest } : {})
    };
  }

  async lastSeq(id: string): Promise<number> {
    return (await this.loadTail(id)).lastSeq;
  }

  async isUnread(id: string): Promise<boolean> {
    const tail = await this.loadTail(id);
    return tail.lastSeq > tail.cursorSeq;
  }

  async markRead(id: string): Promise<void> {
    const tail = await this.loadTail(id);
    if (tail.cursorSeq === tail.lastSeq) return;
    tail.cursorSeq = tail.lastSeq;
    await writeJsonAtomic(path.join(this.agentDir(id), "read-cursor.json"), { seq: tail.cursorSeq });
  }

  /**
   * 加载尾状态，并顺手修复上次非正常退出留下的半行 —— 半行不截掉，下一次追加会
   * 与它粘成一行垃圾。
   */
  private async loadTail(id: string): Promise<TailState> {
    const cached = this.tails.get(id);
    if (cached) return cached;
    const { lastSeq, lastEventAt } = await repairAndReadTail(this.transcriptPath(id));
    const cursor = await readFile(path.join(this.agentDir(id), "read-cursor.json"), "utf8")
      .then((raw) => Number((JSON.parse(raw) as { seq?: number }).seq) || 0)
      .catch(() => lastSeq);
    const state: TailState = { lastSeq, lastEventAt, cursorSeq: Math.min(cursor, lastSeq) };
    this.tails.set(id, state);
    return state;
  }

  private chain<T>(id: string, job: () => Promise<T>): Promise<T> {
    const run = (this.appendChains.get(id) ?? Promise.resolve()).then(job, job);
    this.appendChains.set(
      id,
      run.then(
        () => undefined,
        () => undefined
      )
    );
    return run;
  }

  // ── 审批记录 ────────────────────────────────────────────────────────────

  async readApprovals(id: string): Promise<AgentApprovals> {
    try {
      const raw = JSON.parse(
        await readFile(path.join(this.agentDir(id), "tool-approvals.json"), "utf8")
      ) as Partial<AgentApprovals>;
      return {
        always: parseApprovals(raw.always),
        refused: parseApprovals(raw.refused)
      };
    } catch {
      return { always: [], refused: [] };
    }
  }

  async writeApprovals(id: string, approvals: AgentApprovals): Promise<void> {
    await mkdir(this.agentDir(id), { recursive: true });
    await writeJsonAtomic(path.join(this.agentDir(id), "tool-approvals.json"), approvals);
  }

  // ── 冻结的提示词段 ──────────────────────────────────────────────────────

  /**
   * 按 epoch 冻结的段落快照（§6.1）。落盘的是「会漂的输入」而不是拼装的输出：
   * 拼装本身是确定的，漂的是 profile / 记忆这些段（§10.4）。
   */
  async readPromptCache(id: string): Promise<PromptCache> {
    try {
      const raw = JSON.parse(await readFile(this.promptCachePath(id), "utf8")) as PromptCache;
      const epoch = Number(raw.epoch);
      return {
        epoch: Number.isFinite(epoch) && epoch >= 0 ? epoch : 0,
        profile: raw.profile?.render ? raw.profile : undefined,
        memory: typeof raw.memory === "string" && raw.memory.length > 0 ? raw.memory : undefined
      };
    } catch {
      return { epoch: 0 };
    }
  }

  async writePromptCache(id: string, cache: PromptCache): Promise<void> {
    await mkdir(this.agentDir(id), { recursive: true });
    await writeJsonAtomic(this.promptCachePath(id), cache);
  }

  /**
   * 推进 epoch 并丢掉所有快照。调用方是压缩（第 7 步）与显式记忆写入（第 5 步）；
   * 改名之类的 profile 漂移**不**走这里 —— 那用尾部说明补，不作废整个前缀缓存。
   */
  async bumpPromptEpoch(id: string): Promise<number> {
    const next = (await this.readPromptCache(id)).epoch + 1;
    await this.writePromptCache(id, { epoch: next });
    return next;
  }

  private promptCachePath(id: string): string {
    return path.join(this.agentDir(id), "prompt-cache.json");
  }

  // ── 一次性迁移 ──────────────────────────────────────────────────────────

  private async migrate(): Promise<void> {
    const marker = path.join(this.dataDir, "migrations.json");
    const current = await readFile(marker, "utf8")
      .then((raw) => Number((JSON.parse(raw) as { version?: number }).version) || 0)
      .catch(() => 0);
    if (current >= MIGRATION_VERSION) return;
    const legacyRoot = path.join(this.dataDir, "sessions");
    const hasLegacy = await stat(legacyRoot).then((info) => info.isDirectory()).catch(() => false);
    if (hasLegacy) await this.convertLegacySessions(legacyRoot);
    if (current < 3) await this.migratePermissionModel();
    await writeJsonAtomic(marker, { version: MIGRATION_VERSION });
  }

  private async convertLegacySessions(legacyRoot: string): Promise<void> {
    await mkdir(this.agentsRoot(), { recursive: true });
    const entries = await readdir(legacyRoot).catch(() => [] as string[]);
    for (const id of entries) {
      if (id === "index.json") continue;
      const meta = await readFile(path.join(legacyRoot, id, "meta.json"), "utf8")
        .then((raw) => JSON.parse(raw) as LegacySessionMeta)
        .catch(() => null);
      if (!meta || typeof meta.id !== "string") continue;
      const target = this.agentDir(meta.id);
      await mkdir(target, { recursive: true });
      const title = typeof meta.title === "string" ? meta.title.trim() : "";
      await writeJsonAtomic(path.join(target, "profile.json"), {
        id: meta.id,
        name: !title || title === "New chat" ? "Assistant" : title,
        description: "",
        createdAt: typeof meta.updatedAt === "number" ? meta.updatedAt : Date.now()
      } satisfies AgentProfile);
      await writeJsonAtomic(path.join(target, "settings.json"), {
        model: meta.model ?? DEFAULT_SETTINGS.defaultModel,
        workspace: {
          projectRoot: null,
          toolPermission: meta.sandboxMode === "off" ? "always" : null
        }
      } satisfies AgentSettings);
      // status / unread / preview 全部丢弃：前两者改为派生，preview 由 description 取代。
      await rename(path.join(legacyRoot, id, "transcript.jsonl"), path.join(target, "transcript.jsonl")).catch(
        () => undefined
      );
    }
    await rename(legacyRoot, path.join(this.dataDir, "sessions.legacy")).catch(() => undefined);
    await rm(path.join(this.dataDir, "permissions.json"), { force: true }).catch(() => undefined);
  }

  private async migratePermissionModel(): Promise<void> {
    const settingsPath = path.join(this.dataDir, "settings.json");
    const old = await readFile(settingsPath, "utf8")
      .then((raw) => JSON.parse(raw) as Record<string, unknown>)
      .catch(() => ({} as Record<string, unknown>));
    const projectRoot = typeof old.workspaceRoot === "string" ? old.workspaceRoot : null;
    await writeJsonAtomic(settingsPath, {
      defaultToolPermission: "ask",
      defaultModel: modelOrDefault(old.defaultModel),
      theme: old.theme === "light" || old.theme === "system" ? old.theme : "dark"
    } satisfies Settings);

    await mkdir(this.agentsRoot(), { recursive: true });
    for (const id of await readdir(this.agentsRoot()).catch(() => [] as string[])) {
      const settingsFile = path.join(this.agentDir(id), "settings.json");
      const raw = await readFile(settingsFile, "utf8")
        .then((value) => JSON.parse(value) as Record<string, unknown>)
        .catch(() => ({} as Record<string, unknown>));
      const workspace = raw.workspace && typeof raw.workspace === "object"
        ? raw.workspace as Record<string, unknown>
        : null;
      const parsedPermission = ToolPermission.safeParse(workspace?.toolPermission);
      await writeJsonAtomic(settingsFile, {
        model: modelOrDefault(raw.model),
        workspace: {
          projectRoot,
          toolPermission:
            raw.sandboxMode === "off"
              ? "always"
              : parsedPermission.success
                ? parsedPermission.data
                : null
        },
        ...(typeof raw.hiddenFromSidebar === "boolean" ? { hiddenFromSidebar: raw.hiddenFromSidebar } : {})
      } satisfies AgentSettings);
      // 旧记录是工具名，无法安全映射到精确 action + target；全部丢弃让用户重批。
      await writeJsonAtomic(path.join(this.agentDir(id), "tool-approvals.json"), {
        always: [],
        refused: []
      } satisfies AgentApprovals);
    }
  }
}

interface LegacySessionMeta {
  id: string;
  title?: string;
  updatedAt?: number;
  model?: AgentSettings["model"];
  sandboxMode?: "workspace" | "off";
}

function parseApprovals(raw: unknown): ToolApproval[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item) => {
    const parsed = ToolApproval.safeParse(item);
    return parsed.success ? [parsed.data] : [];
  });
}

function modelOrDefault(raw: unknown): AgentSettings["model"] {
  const parsed = AgentSettings.shape.model.safeParse(raw);
  return parsed.success ? parsed.data : DEFAULT_SETTINGS.defaultModel;
}

function processAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as { code?: string }).code === "EPERM";
  }
}

async function readJson<T>(file: string, schema: { parse(raw: unknown): T }): Promise<T | null> {
  try {
    return schema.parse(JSON.parse(await readFile(file, "utf8")));
  } catch {
    return null;
  }
}

async function writeJsonAtomic(file: string, value: unknown): Promise<void> {
  const temp = `${file}.tmp`;
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(temp, `${JSON.stringify(value, null, 2)}\n`);
  await rename(temp, file);
}

const NEWLINE = 0x0a;

/**
 * 截掉末尾的半行，并返回末条 seq 与末条事件时间。seq 由本进程单调自增写入，所以
 * 尾窗内的最大值就是全局最大值。
 *
 * 换行定位一律在 Buffer 上做：尾窗可能从某个多字节字符中间开始，先解码再按字符
 * 下标算文件偏移会截错位置。
 */
async function repairAndReadTail(file: string): Promise<{ lastSeq: number; lastEventAt: number }> {
  const empty = { lastSeq: 0, lastEventAt: 0 };
  let handle: Awaited<ReturnType<typeof open>>;
  try {
    handle = await open(file, "r+");
  } catch {
    return empty;
  }
  try {
    const { size } = await handle.stat();
    if (size === 0) return empty;
    const window = Math.min(size, TAIL_WINDOW);
    const buffer = Buffer.alloc(window);
    await handle.read(buffer, 0, window, size - window);
    let usable = buffer;
    if (buffer.at(-1) !== NEWLINE) {
      const cut = buffer.lastIndexOf(NEWLINE);
      if (cut >= 0) {
        await handle.truncate(size - window + cut + 1);
        usable = buffer.subarray(0, cut + 1);
      } else if (window === size) {
        await handle.truncate(0);
        usable = Buffer.alloc(0);
      }
    }
    // 只解码「首个换行之后」的区间，除非本窗就是整个文件（那时首字节必是行首）。
    const start = window === size ? 0 : usable.indexOf(NEWLINE) + 1;
    const events: TranscriptEvent[] = [];
    for (const line of usable.subarray(start).toString("utf8").split("\n")) {
      if (!line.trim()) continue;
      const event = tryParseTranscriptLine(line);
      if (event) events.push(event);
    }
    return {
      lastSeq: maxTranscriptSeq(events),
      lastEventAt: events.at(-1)?.createdAt ?? 0
    };
  } finally {
    await handle.close();
  }
}

/**
 * 从文件末尾往前逐行产出，只读到调用方停止为止。carry 保持为字节，避免跨块的
 * 多字节字符被解码成替换符。
 */
async function* readLinesBackward(file: string): AsyncGenerator<string> {
  let handle: Awaited<ReturnType<typeof open>>;
  try {
    handle = await open(file, "r");
  } catch {
    return;
  }
  try {
    let position = (await handle.stat()).size;
    let carry = Buffer.alloc(0);
    while (position > 0) {
      const length = Math.min(TAIL_WINDOW, position);
      position -= length;
      const buffer = Buffer.alloc(length);
      await handle.read(buffer, 0, length, position);
      const combined = Buffer.concat([buffer, carry]);
      const head = combined.indexOf(NEWLINE);
      if (head === -1) {
        carry = combined;
        continue;
      }
      carry = combined.subarray(0, head);
      const lines = combined.subarray(head + 1).toString("utf8").split("\n");
      for (let i = lines.length - 1; i >= 0; i -= 1) {
        if (lines[i]!.trim()) yield lines[i]!;
      }
    }
    const first = carry.toString("utf8");
    if (first.trim()) yield first;
  } finally {
    await handle.close();
  }
}
