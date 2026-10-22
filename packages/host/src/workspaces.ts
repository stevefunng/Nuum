import { createHash, randomUUID } from "node:crypto";
import { lstat, mkdir, readFile, realpath, rename, writeFile } from "node:fs/promises";
import path from "node:path";

export interface WorkspaceRecord { id: string; root: string; kind: "personal" | "room"; previousRoot?: string }

/** Host-owned records live outside tool-readable workspaces. Names are labels, IDs own directories. */
export class WorkspaceStore {
  constructor(private readonly dataDir: string, private readonly documents: string) {}

  async init(): Promise<void> {
    await mkdir(this.documents, { recursive: true });
    await directory(path.join(this.documents, "Nuum"));
    await directory(path.join(this.documents, "Nuum", "Rooms"));
  }

  async ensure(owner: string, name: string, kind: WorkspaceRecord["kind"], previousRoot?: string | null): Promise<WorkspaceRecord> {
    const id = createHash("sha256").update(owner).digest("hex");
    const records = path.join(this.dataDir, "workspaces");
    const file = path.join(records, `${id}.json`);
    const base = path.join(this.documents, "Nuum");
    await mkdir(this.documents, { recursive: true });
    await directory(base);
    const parent = kind === "room" ? path.join(base, "Rooms") : base;
    await directory(path.join(base, "Rooms"));
    const canonicalParent = await realpath(parent);
    let saved: WorkspaceRecord | undefined;
    try { saved = JSON.parse(await readFile(file, "utf8")) as WorkspaceRecord; }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
    if (saved) {
      if (saved.id !== id || saved.kind !== kind || path.dirname(saved.root) !== canonicalParent) {
        throw new Error("Invalid managed workspace record");
      }
      await directory(saved.root);
      return saved;
    }
    const label = safeName(name);
    let root = path.join(canonicalParent, label);
    for (let suffix = 0; ; suffix++) {
      root = path.join(canonicalParent, suffix ? `${label} (${suffix + 1})` : label);
      try { await mkdir(root); break; }
      catch (error) { if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error; }
    }
    const record: WorkspaceRecord = { id, root, kind, ...(previousRoot ? { previousRoot } : {}) };
    await mkdir(records, { recursive: true, mode: 0o700 });
    const temporary = `${file}.${randomUUID()}.tmp`;
    await writeFile(temporary, JSON.stringify(record, null, 2) + "\n", { mode: 0o600 });
    await rename(temporary, file);
    return record;
  }
}

async function directory(target: string): Promise<void> {
  await mkdir(target, { recursive: true });
  const info = await lstat(target);
  if (info.isSymbolicLink() || !info.isDirectory()) throw new Error(`Managed workspace cannot be a symbolic link: ${target}`);
}

function safeName(name: string): string {
  const cleaned = name.normalize("NFC").replace(/[\x00-\x1f/\\:*?"<>|]/g, "_").replace(/^[. ]+|[. ]+$/g, "").slice(0, 80);
  return !cleaned || /^(rooms|con|prn|aux|nul|com[1-9]|lpt[1-9])$/i.test(cleaned) ? `${cleaned || "Nunu"}_` : cleaned;
}
