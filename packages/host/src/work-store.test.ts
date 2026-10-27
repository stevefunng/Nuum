import { testTempDir } from "../../../scripts/test-temp.mjs";
import assert from "node:assert/strict";
import { appendFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { WorkStore, projectWork } from "./work-store.js";

async function openStore() {
  const dataDir = await testTempDir(path.join(tmpdir(), "nuum-work-store-"));
  const store = new WorkStore(dataDir);
  await store.init();
  return { dataDir, store };
}

test("a work owns one append-only timeline with serialized sequence numbers", async () => {
  const { store } = await openStore();
  await store.createWork({
    id: "work-1",
    name: "Launch",
    description: "Ship it",
    projectRoot: null,
    createdAt: 1
  });

  const [first, second] = await Promise.all([
    store.appendEvent("work-1", {
      type: "chat.posted",
      id: "event-1",
      workId: "work-1",
      createdAt: 2,
      actor: { kind: "user", id: "local-user" },
      messageId: "message-1",
      body: "first",
      mentionedAgentIds: []
    }),
    store.appendEvent("work-1", {
      type: "chat.posted",
      id: "event-2",
      workId: "work-1",
      createdAt: 3,
      actor: { kind: "user", id: "local-user" },
      messageId: "message-2",
      body: "second",
      mentionedAgentIds: []
    })
  ]);

  assert.deepEqual([first.seq, second.seq], [1, 2]);
  assert.deepEqual((await store.readTimeline("work-1")).map((event) => event.seq), [1, 2]);
});

test("timeline projection derives chat and tasks without another stored truth", async () => {
  const { store } = await openStore();
  await store.createWork({
    id: "work-1",
    name: "Launch",
    description: "Ship it",
    projectRoot: null,
    createdAt: 1
  });
  await store.appendEvent("work-1", {
    type: "task.created",
    id: "event-1",
    workId: "work-1",
    createdAt: 2,
    actor: { kind: "user", id: "local-user" },
    task: {
      id: "task-1",
      title: "Review",
      description: "Review the build",
      acceptanceCriteria: [],
      state: "ready",
      assigneeIds: [],
      dependencyIds: [],
      priority: "normal",
      revision: 1,
      deliverables: [],
      createdAt: 2,
      updatedAt: 2
    }
  });
  await store.appendEvent("work-1", {
    type: "task.transitioned",
    id: "event-2",
    workId: "work-1",
    createdAt: 3,
    actor: { kind: "agent", id: "agent-1" },
    taskId: "task-1",
    from: "ready",
    to: "in_progress",
    revision: 2
  });
  await store.appendEvent("work-1", {
    type: "chat.posted",
    id: "event-3",
    workId: "work-1",
    createdAt: 4,
    actor: { kind: "agent", id: "agent-1" },
    messageId: "message-1",
    body: "I started",
    mentionedAgentIds: []
  });

  const projected = projectWork(await store.readTimeline("work-1"));
  assert.equal(projected.tasks[0]!.state, "in_progress");
  assert.equal(projected.tasks[0]!.revision, 2);
  assert.equal(projected.chat.at(-1)!.body, "I started");
});

test("init removes a torn final line before the next append", async () => {
  const { dataDir, store } = await openStore();
  await store.createWork({
    id: "work-1",
    name: "Launch",
    description: "Ship it",
    projectRoot: null,
    createdAt: 1
  });
  await store.appendEvent("work-1", {
    type: "chat.posted",
    id: "event-1",
    workId: "work-1",
    createdAt: 2,
    actor: { kind: "user", id: "local-user" },
    messageId: "message-1",
    body: "kept",
    mentionedAgentIds: []
  });
  const timeline = path.join(dataDir, "works", "work-1", "timeline.jsonl");
  await appendFile(timeline, "{\"type\":\"chat.posted\"");

  const reopened = new WorkStore(dataDir);
  await reopened.init();
  const appended = await reopened.appendEvent("work-1", {
    type: "chat.posted",
    id: "event-2",
    workId: "work-1",
    createdAt: 3,
    actor: { kind: "user", id: "local-user" },
    messageId: "message-2",
    body: "also kept",
    mentionedAgentIds: []
  });

  assert.equal(appended.seq, 2);
  assert.equal((await reopened.readTimeline("work-1")).length, 2);
  assert.equal((await readFile(timeline, "utf8")).endsWith("\n"), true);
});

test("a complete corrupt record is reported instead of silently dropping history", async () => {
  const { store } = await openStore();
  await store.createWork({ id: "r", name: "Room", description: "", projectRoot: null, createdAt: 0 });
  await appendFile(store.timelineFile("r"), '{"broken":true}\n');
  await assert.rejects(store.readTimeline("r"), /corrupt|invalid/i);
  await assert.rejects(store.appendEvent("r", { type: "chat.posted", id: "new", workId: "r", actor: { kind: "user", id: "u" }, createdAt: 1, body: "new", messageId: "m", mentionedAgentIds: [] }), /corrupt|invalid/i);
});

test("retry identity cannot silently accept different message content", async () => {
  const { store } = await openStore();
  await store.createWork({ id: "r", name: "Room", description: "", projectRoot: null, createdAt: 0 });
  const draft = { type: "chat.posted" as const, id: "first", workId: "r", actor: { kind: "user" as const, id: "u" }, createdAt: 1, body: "first", messageId: "m", mentionedAgentIds: [], clientEventId: "request" };
  const original = await store.appendEvent("r", draft);
  assert.equal((await store.appendEvent("r", { ...draft, id: "retry", messageId: "other", createdAt: 2 })).seq, original.seq);
  await assert.rejects(store.appendEvent("r", { ...draft, body: "different" }), /conflict/i);
});

test("legacy migration backs up history and records uncertainty without scheduling or rewriting it", async () => {
  const { unlink } = await import("node:fs/promises");
  const { store, dataDir } = await openStore();
  await store.createWork({ id: "r", name: "Legacy", description: "", projectRoot: null, createdAt: 0 });
  await store.appendEvent("r", { type: "chat.posted", id: "old", workId: "r", actor: { kind: "user", id: "u" }, createdAt: 1, messageId: "m", body: "Unanswered old message", mentionedAgentIds: [] });
  await unlink(path.join(store.workDir("r"), "runtime-version.json"));
  const before = await readFile(store.timelineFile("r"), "utf8");
  const reopened = new WorkStore(dataDir);
  await reopened.init();
  await reopened.migrateExecutionHistory();
  assert.equal(await readFile(`${store.timelineFile("r")}.pre-simplification.bak`, "utf8"), before);
  const events = await reopened.readTimeline("r");
  assert.equal(events[0]?.id, "old");
  assert.equal(events[1]?.type, "history.imported");
  assert.deepEqual(events[1]?.type === "history.imported" ? events[1].unconfirmedEventIds : [], ["old"]);
  await reopened.migrateExecutionHistory();
  assert.equal((await reopened.readTimeline("r")).length, 2);
});
