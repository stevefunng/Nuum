import { createHash } from "node:crypto";
import { mkdir, open, readFile, writeFile, readdir } from "node:fs/promises";
import path from "node:path";
import { TranscriptEvent, type TranscriptDraft } from "@nuum/protocol";
import { activeTranscript } from "./context.js";

export interface CardSession {
  id: string;
  workId: string;
  taskId: string;
  agentId: string;
  membershipRevision: number;
}

/** Card execution stays local; the room publishes only explicit messages and handoffs. */
export class SessionStore {
  private readonly chains = new Map<string, Promise<unknown>>();
  constructor(private readonly dataDir: string) {}

  async ensure(workId: string, taskId: string, agentId: string, membershipRevision: number): Promise<CardSession> {
    const id = createHash("sha256").update(JSON.stringify([workId, taskId, agentId, membershipRevision])).digest("hex");
    const session = { id, workId, taskId, agentId, membershipRevision };
    await mkdir(this.directory(session), { recursive: true });
    try { await writeFile(path.join(this.directory(session), "session.json"), JSON.stringify(session), { flag: "wx" }); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error; }
    return session;
  }

  directory(session: CardSession): string {
    if (!/^[a-f0-9]{64}$/.test(session.id)) throw new Error("Invalid card session id");
    // Hash the room component too: RPC ids are data, never filesystem paths.
    const room = createHash("sha256").update(session.workId).digest("hex");
    return path.join(this.dataDir, "work-sessions", room, session.id);
  }

  async list(workId: string, taskId: string): Promise<CardSession[]> {
    const room = createHash("sha256").update(workId).digest("hex");
    const root = path.join(this.dataDir, "work-sessions", room);
    let ids: string[];
    try { ids = await readdir(root); } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return []; throw error; }
    const sessions: CardSession[] = [];
    for (const id of ids) {
      if (!/^[a-f0-9]{64}$/.test(id)) continue;
      const session = JSON.parse(await readFile(path.join(root, id, "session.json"), "utf8")) as CardSession;
      if (session.id === id && session.workId === workId && session.taskId === taskId) sessions.push(session);
    }
    return sessions;
  }

  transcriptFile(session: CardSession): string {
    return path.join(this.directory(session), "transcript.jsonl");
  }

  async read(session: CardSession): Promise<TranscriptEvent[]> {
    let raw: string;
    try { raw = await readFile(this.transcriptFile(session), "utf8"); }
    catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return []; throw error; }
    // An unterminated line is an uncommitted append, not a readable event.
    return raw.slice(0, raw.lastIndexOf("\n") + 1).split("\n").filter(Boolean)
      .map((line) => TranscriptEvent.parse(JSON.parse(line)));
  }

  async readForAssemble(session: CardSession) {
    const events = activeTranscript(await this.read(session));
    const compact = events.find((event) => event.type === "compact");
    return { events, compact };
  }

  append(session: CardSession, draft: TranscriptDraft): Promise<TranscriptEvent> {
    const previous = this.chains.get(session.id) ?? Promise.resolve();
    const current = previous.catch(() => undefined).then(async () => {
      const events = await this.read(session);
      const existing = events.find((event) => event.id === draft.id);
      if (existing) return existing;
      const event = TranscriptEvent.parse({ ...draft, seq: (events.at(-1)?.seq ?? 0) + 1 });
      const handle = await open(this.transcriptFile(session), "a+");
      try {
        const raw = await handle.readFile();
        const committed = raw.lastIndexOf(10) + 1;
        if (committed < raw.length) await handle.truncate(committed);
        await handle.writeFile(`${JSON.stringify(event)}\n`);
        await handle.sync();
      } finally { await handle.close(); }
      return event;
    });
    this.chains.set(session.id, current);
    void current.finally(() => { if (this.chains.get(session.id) === current) this.chains.delete(session.id); }).catch(() => undefined);
    return current;
  }
}
