import { testTempDir } from "../../../scripts/test-temp.mjs";
import assert from "node:assert/strict";
import { appendFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { SessionStore } from "./session-store.js";

test("card participants resume separate durable histories and idempotent inputs", async () => {
  const dir = await testTempDir(path.join(tmpdir(), "nuum-sessions-"));
  const store = new SessionStore(dir);
  const a = await store.ensure("room", "card", "a", 1);
  const b = await store.ensure("room", "card", "b", 1);
  assert.notEqual(a.id, b.id);
  const draft = { type: "user" as const, id: "input", text: "Build", createdAt: 1 };
  await Promise.all([store.append(a, draft), store.append(a, draft)]);
  assert.equal((await store.read(a)).length, 1);
  assert.deepEqual(await store.read(b), []);
  const restored = new SessionStore(dir);
  assert.deepEqual(await restored.ensure("room", "card", "a", 1), a);
  assert.equal((await restored.read(a))[0]!.seq, 1);
  assert.notEqual((await restored.ensure("room", "card", "a", 2)).id, a.id);
});

test("session append repairs a torn final line without losing committed entries", async () => {
  const store = new SessionStore(await testTempDir(path.join(tmpdir(), "nuum-sessions-")));
  const session = await store.ensure("room", "card", "a", 0);
  await store.append(session, { type: "user", id: "first", text: "First", createdAt: 1 });
  await appendFile(store.transcriptFile(session), '{"type":"assistant"');
  await store.append(session, { type: "user", id: "second", text: "Second", createdAt: 2 });
  assert.deepEqual((await store.read(session)).map((event) => event.id), ["first", "second"]);
});
