import assert from "node:assert/strict";
import { mkdir, readFile, readdir, stat, utimes, writeFile } from "node:fs/promises";
import { testTempDir } from "../../../scripts/test-temp.mjs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test, type TestContext } from "node:test";
import type { AgentProfile, AgentSettings } from "@nuum/protocol";
import { AgentStore } from "./agent-store.js";

const MODEL: AgentSettings["model"] = { provider: "deepseek", model: "deepseek-chat" };

/** dataDir 锁是刻意长持的文件句柄，所以每个用例都要收尾释放。 */
function track(t: TestContext, store: AgentStore): AgentStore {
  t.after(() => store.dispose());
  return store;
}

async function openStore(t: TestContext, dir: string): Promise<AgentStore> {
  const store = track(t, new AgentStore(dir));
  await store.init();
  return store;
}

async function freshStore(t: TestContext): Promise<{ store: AgentStore; dir: string }> {
  const dir = await testTempDir(path.join(tmpdir(), "nuum-agents-"));
  return { store: await openStore(t, dir), dir };
}

function profile(id: string, name: string): AgentProfile {
  return { id, name, description: "", createdAt: 1000 };
}

async function seedLegacySession(
  dir: string,
  id: string,
  meta: Record<string, unknown>,
  lines: unknown[]
): Promise<void> {
  const sessionDir = path.join(dir, "sessions", id);
  await mkdir(sessionDir, { recursive: true });
  await writeFile(path.join(sessionDir, "meta.json"), JSON.stringify(meta));
  await writeFile(
    path.join(sessionDir, "transcript.jsonl"),
    lines.map((line) => JSON.stringify(line)).join("\n") + (lines.length ? "\n" : "")
  );
}

test("appendEvent assigns sequential seq without reading the whole file", async (t) => {
  const { store } = await freshStore(t);
  await store.createAgent(profile("a1", "One"), { model: MODEL });
  const first = await store.appendEvent("a1", { type: "user", id: "u1", text: "hi", createdAt: 1 });
  const second = await store.appendEvent("a1", { type: "user", id: "u2", text: "there", createdAt: 2 });
  assert.equal(first.seq, 1);
  assert.equal(second.seq, 2);
  assert.equal(await store.lastSeq("a1"), 2);
});

test("concurrent appends keep call order and never collide on seq", async (t) => {
  const { store } = await freshStore(t);
  await store.createAgent(profile("a1", "One"), { model: MODEL });
  const events = await Promise.all(
    Array.from({ length: 24 }, (_, index) =>
      store.appendEvent("a1", { type: "user", id: `u${index}`, text: `m${index}`, createdAt: index })
    )
  );
  assert.deepEqual(
    events.map((event) => event.seq),
    Array.from({ length: 24 }, (_, index) => index + 1)
  );
  const read = await store.readTranscript("a1");
  assert.equal(read.length, 24);
  assert.deepEqual(
    read.map((event) => event.seq),
    Array.from({ length: 24 }, (_, index) => index + 1)
  );
});

test("a torn last line costs only that line, not the whole transcript", async (t) => {
  const { store, dir } = await freshStore(t);
  await store.createAgent(profile("a1", "One"), { model: MODEL });
  await store.appendEvent("a1", { type: "user", id: "u1", text: "kept", createdAt: 1 });
  await store.appendEvent("a1", { type: "user", id: "u2", text: "also kept", createdAt: 2 });
  const file = path.join(dir, "agents", "a1", "transcript.jsonl");
  await writeFile(file, '{"type":"user","id":"u3","seq":3,"createdAt":3,"te', { flag: "a" });
  await store.dispose();

  const reopened = await openStore(t, dir);
  const events = await reopened.readTranscript("a1");
  assert.deepEqual(
    events.map((event) => event.id),
    ["u1", "u2"]
  );
  // 半行被截掉，所以下一次追加不会与它粘成一行垃圾。
  assert.equal(await reopened.lastSeq("a1"), 2);
  const next = await reopened.appendEvent("a1", { type: "user", id: "u4", text: "after", createdAt: 4 });
  assert.equal(next.seq, 3);
  const raw = await readFile(file, "utf8");
  assert.equal(raw.split("\n").filter(Boolean).length, 3);
});

test("a corrupt line in the middle is skipped, not fatal", async (t) => {
  const { store, dir } = await freshStore(t);
  await store.createAgent(profile("a1", "One"), { model: MODEL });
  const file = path.join(dir, "agents", "a1", "transcript.jsonl");
  await writeFile(
    file,
    [
      JSON.stringify({ type: "user", id: "u1", seq: 1, createdAt: 1, text: "first" }),
      "{ not json at all",
      JSON.stringify({ type: "user", id: "u3", seq: 3, createdAt: 3, text: "third" })
    ].join("\n") + "\n"
  );
  const events = await store.readTranscript("a1");
  assert.deepEqual(
    events.map((event) => event.id),
    ["u1", "u3"]
  );
});

test("readTranscriptPage walks backwards with a beforeSeq cursor", async (t) => {
  const { store } = await freshStore(t);
  await store.createAgent(profile("a1", "One"), { model: MODEL });
  for (let index = 0; index < 10; index += 1) {
    await store.appendEvent("a1", { type: "user", id: `u${index}`, text: `m${index}`, createdAt: index });
  }
  const tail = await store.readTranscriptPage("a1", undefined, 4);
  assert.deepEqual(
    tail.entries.map((event) => event.seq),
    [7, 8, 9, 10]
  );
  assert.equal(tail.nextBeforeSeq, 7);

  const older = await store.readTranscriptPage("a1", tail.nextBeforeSeq, 4);
  assert.deepEqual(
    older.entries.map((event) => event.seq),
    [3, 4, 5, 6]
  );
  assert.equal(older.nextBeforeSeq, 3);

  const oldest = await store.readTranscriptPage("a1", older.nextBeforeSeq, 4);
  assert.deepEqual(
    oldest.entries.map((event) => event.seq),
    [1, 2]
  );
  // 到头了就不给游标，UI 才知道没有更早的了。
  assert.equal(oldest.nextBeforeSeq, undefined);
});

test("readForAssemble starts at the last compact and restores its preserved tail", async (t) => {
  const { store } = await freshStore(t);
  await store.createAgent(profile("a1", "One"), { model: MODEL });
  await store.appendEvent("a1", { type: "user", id: "u1", text: "old", createdAt: 1 });
  await store.appendEvent("a1", { type: "assistant", id: "a1", parts: [{ type: "text", text: "old answer" }], createdAt: 2 });
  await store.appendEvent("a1", { type: "user", id: "u2", text: "first tail", createdAt: 3 });
  await store.appendEvent("a1", { type: "assistant", id: "a2", parts: [{ type: "text", text: "first tail answer" }], createdAt: 4 });
  await store.appendEvent("a1", { type: "compact", id: "c1", epoch: 1, throughSeq: 2, tailFromSeq: 3, summary: "first summary", createdAt: 5 });
  await store.appendEvent("a1", { type: "user", id: "u3", text: "latest tail", createdAt: 6 });
  await store.appendEvent("a1", { type: "assistant", id: "a3", parts: [{ type: "text", text: "latest answer" }], createdAt: 7 });
  await store.appendEvent("a1", { type: "compact", id: "c2", epoch: 2, throughSeq: 5, tailFromSeq: 6, summary: "latest summary", createdAt: 8 });
  await store.appendEvent("a1", { type: "assistant", id: "a4", parts: [{ type: "text", text: "after checkpoint" }], createdAt: 9 });

  // 热路径不能偷偷退回整份读取。
  store.readTranscript = async () => {
    throw new Error("full transcript read");
  };
  const active = await store.readForAssemble("a1");
  assert.equal(active.compact?.id, "c2");
  assert.deepEqual(active.events.map((event) => event.id), ["c2", "u3", "a3", "a4"]);
});

test("pagination survives multi-byte content across chunk boundaries", async (t) => {
  const { store } = await freshStore(t);
  await store.createAgent(profile("a1", "One"), { model: MODEL });
  const text = "中文内容".repeat(4000);
  for (let index = 0; index < 6; index += 1) {
    await store.appendEvent("a1", { type: "user", id: `u${index}`, text, createdAt: index });
  }
  const page = await store.readTranscriptPage("a1", undefined, 6);
  assert.equal(page.entries.length, 6);
  for (const event of page.entries) {
    assert.equal(event.type === "user" && event.text, text);
  }
});

test("agent list is scanned from disk, with no index file to drift", async (t) => {
  const { store, dir } = await freshStore(t);
  await store.createAgent(profile("a1", "One"), { model: MODEL });
  await store.createAgent(profile("a2", "Two"), { model: MODEL });
  await store.appendEvent("a2", { type: "user", id: "u1", text: "hi", createdAt: 9999 });
  await store.dispose();

  const reopened = await openStore(t, dir);
  const listed = reopened.listAgents();
  assert.deepEqual(new Set(listed.map((item) => item.profile.id)), new Set(["a1", "a2"]));
  // 有新事件的排前面：lastActivityAt 取末条事件的 createdAt，不落盘因此不会漂。
  assert.equal(listed[0]!.profile.id, "a2");
  assert.equal(listed[0]!.lastActivityAt, 9999);
  // a1 没有事件，回落到 profile.createdAt。
  assert.equal(listed[1]!.lastActivityAt, 1000);
  assert.equal((await readdir(path.join(dir, "agents"))).includes("index.json"), false);
});

test("ordering ignores file mtime so a restore or rsync cannot scramble it", async (t) => {
  const { store, dir } = await freshStore(t);
  await store.createAgent(profile("older", "Older"), { model: MODEL });
  await store.createAgent(profile("newer", "Newer"), { model: MODEL });
  await store.appendEvent("older", { type: "user", id: "u1", text: "first", createdAt: 5_000 });
  await store.appendEvent("newer", { type: "user", id: "u2", text: "second", createdAt: 9_000 });
  await store.dispose();

  // 模拟备份恢复：把两份转录的 mtime 反着设回去。
  const flip = async (id: string, when: number) => {
    const file = path.join(dir, "agents", id, "transcript.jsonl");
    await utimes(file, new Date(when), new Date(when));
  };
  await flip("newer", 1_000);
  await flip("older", 8_000_000);

  const reopened = await openStore(t, dir);
  assert.deepEqual(
    reopened.listAgents().map((item) => item.profile.id),
    ["newer", "older"]
  );
});

test("a second host on the same dataDir is refused instead of double-writing", async (t) => {
  const { store, dir } = await freshStore(t);
  await assert.rejects(() => new AgentStore(dir).init(), /already owns/);
  await store.dispose();
  // 前一个实例释放后可以正常接管。
  await openStore(t, dir);
});

test("migration converts legacy sessions and is idempotent", async (t) => {
  const dir = await testTempDir(path.join(tmpdir(), "nuum-migrate-"));
  await seedLegacySession(
    dir,
    "s1",
    {
      id: "s1",
      title: "Fix the parser",
      preview: "old preview",
      status: "running",
      unread: true,
      updatedAt: 4242,
      model: MODEL,
      sandboxMode: "off"
    },
    [{ id: "u1", role: "user", content: "hello", seq: 1, createdAt: 1 }]
  );
  await seedLegacySession(dir, "s2", { id: "s2", title: "New chat", updatedAt: 10, model: MODEL }, []);
  await writeFile(
    path.join(dir, "permissions.json"),
    JSON.stringify({ always: { s1: ["read", "bash"] }, session: { s1: ["write"] } })
  );
  await writeFile(path.join(dir, "settings.json"), JSON.stringify({
    workspaceRoot: dir,
    sandboxMode: "off",
    defaultModel: MODEL,
    theme: "dark"
  }));

  const store = await openStore(t, dir);

  const listed = store.listAgents();
  assert.deepEqual(new Set(listed.map((item) => item.profile.id)), new Set(["s1", "s2"]));
  const first = store.getAgent("s1")!;
  assert.equal(first.profile.name, "Fix the parser");
  assert.deepEqual(first.settings.workspace, { projectRoot: dir, toolPermission: "always" });
  // status / unread / preview 一律丢弃：前两者改为派生，preview 由 description 取代。
  assert.equal("status" in first.profile, false);
  assert.equal("unread" in (first.settings as object), false);
  assert.equal(first.profile.description, "");
  // 默认标题不带进人格。
  assert.equal(store.getAgent("s2")!.profile.name, "Assistant");
  // 旧 meta 的 updatedAt 承接进 profile.createdAt，所以侧栏顺序跨迁移不变。
  assert.equal(first.profile.createdAt, 4242);
  assert.deepEqual(
    store.listAgents().map((item) => item.profile.id),
    ["s1", "s2"]
  );
  // 旧 JSONL 原样可读，且能继续追加。
  assert.deepEqual(await store.readTranscript("s1"), [
    { type: "user", id: "u1", seq: 1, createdAt: 1, text: "hello" }
  ]);
  assert.equal((await store.appendEvent("s1", { type: "user", id: "u2", text: "next", createdAt: 2 })).seq, 2);
  // 工具名无法安全映射到精确 action + target，旧审批丢弃并删除全局副本。
  assert.deepEqual(await store.readApprovals("s1"), { always: [], refused: [] });
  assert.deepEqual(await store.readApprovals("s2"), { always: [], refused: [] });
  await assert.rejects(() => stat(path.join(dir, "permissions.json")));
  // 旧数据保留待用户自行删除，不销毁。
  assert.equal((await stat(path.join(dir, "sessions.legacy"))).isDirectory(), true);
  await store.dispose();

  const again = await openStore(t, dir);
  assert.equal(again.listAgents().length, 2);
  assert.deepEqual(await again.readTranscript("s1"), [
    { type: "user", id: "u1", seq: 1, createdAt: 1, text: "hello" },
    { type: "user", id: "u2", seq: 2, createdAt: 2, text: "next" }
  ]);
});

test("unread is derived from the read cursor, never persisted as a flag", async (t) => {
  const { store, dir } = await freshStore(t);
  await store.createAgent(profile("a1", "One"), { model: MODEL });
  assert.equal(await store.isUnread("a1"), false);
  await store.appendEvent("a1", { type: "user", id: "u1", text: "hi", createdAt: 1 });
  assert.equal(await store.isUnread("a1"), true);
  await store.markRead("a1");
  assert.equal(await store.isUnread("a1"), false);
  await store.dispose();

  const reopened = await openStore(t, dir);
  assert.equal(await reopened.isUnread("a1"), false);
  await reopened.appendEvent("a1", { type: "user", id: "u2", text: "again", createdAt: 2 });
  assert.equal(await reopened.isUnread("a1"), true);
});
