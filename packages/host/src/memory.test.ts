import { testTempDir } from "../../../scripts/test-temp.mjs";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import {
  MemoryStore,
  dedupeKey,
  estimateTokens,
  isMemorableExchange,
  normalize,
  parseExtraction,
  recallRank,
  renderMemory,
  type MemoryFact
} from "./memory.js";

async function freshStore(): Promise<MemoryStore> {
  return new MemoryStore(path.join(await testTempDir(path.join(tmpdir(), "nuum-mem-")), "memory"));
}

test("a standing fact and a dated fact land in different files", async () => {
  const store = await freshStore();
  await store.write("The user runs tests with pnpm test", "profile");
  await store.write("Fixed the flaky login test", "log", new Date("2026-09-03T10:00:00Z"));

  const profile = await readFile(store.profilePath, "utf8");
  assert.ok(profile.includes("- The user runs tests with pnpm test"));
  // 常驻事实不带日期 —— 它不是「某天发生的事」。
  assert.equal(/\d{4}-\d{2}-\d{2}/.test(profile), false);

  const log = await readFile(store.logPath(new Date("2026-09-03T10:00:00Z")), "utf8");
  assert.ok(log.includes("- 2026-09-03 · Fixed the flaky login test"));
});

test("notes go under their own heading, so tier survives a round trip", async () => {
  const store = await freshStore();
  const day = new Date("2026-09-03T10:00:00Z");
  await store.write("Chose pnpm over npm", "log", day);
  await store.write("Tried vitest first and it did not work here", "note", day);

  const facts = await store.all();
  assert.deepEqual(
    facts.map((entry) => [entry.tier, entry.fact]),
    [
      ["log", "Chose pnpm over npm"],
      ["note", "Tried vitest first and it did not work here"]
    ]
  );
  // 文件是给人和模型读的 Markdown，tier 写成小节标题而不是埋一个权重字段。
  const log = await readFile(store.logPath(day), "utf8");
  assert.ok(log.indexOf("## Facts") < log.indexOf("## Notes"));
});

test("writing the same fact twice is idempotent, punctuation and case aside", async () => {
  const store = await freshStore();
  assert.deepEqual(await store.write("The user prefers pnpm.", "profile"), { written: true });
  assert.deepEqual(await store.write("the user prefers pnpm", "profile"), { written: false });
  assert.equal((await store.all()).length, 1);
});

test("a fact recorded in one tier is not recorded again in another", async () => {
  const store = await freshStore();
  await store.write("The user prefers pnpm", "profile");
  // 同一件事换个 tier 再写一遍仍是同一件事 —— 否则记忆会被自动抽取灌成两倍。
  assert.deepEqual(await store.write("The user prefers pnpm", "log"), { written: false });
});

test("forget removes a fact wherever it was filed", async () => {
  const store = await freshStore();
  await store.write("Deploys go out on Fridays", "log", new Date("2026-09-03T10:00:00Z"));
  assert.deepEqual(await store.forget("deploys go out on fridays"), { removed: 1 });
  assert.deepEqual(await store.all(), []);
  // 删完文件还得是合法的 Markdown，不是留一堆空行。
  const log = await readFile(store.logPath(new Date("2026-09-03T10:00:00Z")), "utf8");
  assert.equal(log.includes("Deploys"), false);
});

test("forget on something never recorded says so instead of pretending", async () => {
  const store = await freshStore();
  await store.write("Something else", "profile");
  assert.deepEqual(await store.forget("never said this"), { removed: 0 });
  assert.equal((await store.all()).length, 1);
});

test("a store with no files at all reads as empty, not as an error", async () => {
  const store = await freshStore();
  assert.deepEqual(await store.all(), []);
});

test("standing facts always render; dated ones are ranked and budgeted", () => {
  const now = new Date("2026-09-03T00:00:00Z");
  const facts: MemoryFact[] = [
    { fact: "The user prefers pnpm", tier: "profile" },
    { fact: "recent decision", tier: "log", day: "2026-09-02" },
    { fact: "ancient detail", tier: "log", day: "2024-01-01" }
  ];
  const render = renderMemory(facts, "/data/agents/a1/memory", now);
  assert.ok(render.startsWith("## Memory"));
  assert.ok(render.includes("- The user prefers pnpm"));
  assert.ok(render.includes("2026-09-02 · recent decision"));
  // 记忆目录的本机绝对路径必须在里面，模型才知道去哪 grep 更老的。
  assert.ok(render.includes("/data/agents/a1/memory"));
});

test("a fresh note outranks a stale fact, and staleness is what decides it", () => {
  const now = new Date("2026-09-03T00:00:00Z");
  const freshNote: MemoryFact = { fact: "n", tier: "note", day: "2026-09-03" };
  const staleFact: MemoryFact = { fact: "f", tier: "log", day: "2025-09-03" };
  assert.ok(recallRank(freshNote, now) > recallRank(staleFact, now));
  // 同日则 tier 说话。
  const freshFact: MemoryFact = { fact: "f", tier: "log", day: "2026-09-03" };
  assert.ok(recallRank(freshFact, now) > recallRank(freshNote, now));
});

test("what does not fit is reported as still being on disk", () => {
  const now = new Date("2026-09-03T00:00:00Z");
  const facts: MemoryFact[] = Array.from({ length: 200 }, (_, i) => ({
    fact: `fact number ${i} ${"x".repeat(60)}`,
    tier: "log" as const,
    day: "2026-09-01"
  }));
  const render = renderMemory(facts, "/data/memory", now);
  // 静默截断是最坏的选项：模型会以为自己看到的就是全部。
  assert.ok(/\d+ older entries did not fit/.test(render));
});

test("an empty memory says it is empty rather than rendering a hole", () => {
  const render = renderMemory([], "/data/memory", new Date());
  assert.ok(render.includes("not recorded anything"));
  assert.ok(render.includes("/data/memory"));
});

test("kept entries read in time order even though ranking picked them", () => {
  const now = new Date("2026-09-03T00:00:00Z");
  const render = renderMemory(
    [
      { fact: "later", tier: "log", day: "2026-09-02" },
      { fact: "earlier", tier: "log", day: "2026-08-01" }
    ],
    "/data/memory",
    now
  );
  assert.ok(render.indexOf("earlier") < render.indexOf("later"));
});

test("small talk is not worth a model call", () => {
  for (const text of ["thanks", "ok", "谢谢", "好的", "Sure."]) {
    assert.equal(isMemorableExchange(text), false, text);
  }
  for (const text of ["what does the scheduler do?", "always use the workspace root for relative paths"]) {
    assert.equal(isMemorableExchange(text), true, text);
  }
});

test("a substantive CJK sentence is not mistaken for small talk", () => {
  // 门槛按 token 粗估，不按字符数：这句 30 字的中文比 30 字的英文说得多得多，
  // 照「长度 > 40」判会被当成客套话直接漏掉。
  assert.equal(isMemorableExchange("从现在起测试都用 pnpm，别再用 npm 了，记住"), true);
  assert.equal(estimateTokens("从现在起测试都用 pnpm"), estimateTokens("从现在起测试都用 pnpm"));
  assert.ok(estimateTokens("九个汉字就够十个") < 10);
  assert.ok(estimateTokens("十一个汉字这下够十个了吧") > 10);
});

test("extraction reads the prefixed lines and ignores the model's chatter", () => {
  const parsed = parseExtraction(
    [
      "Here is what I found:",
      "profile: The user prefers pnpm.",
      "log: Fixed the flaky login test",
      "note: vitest did not work here",
      "remove: The user prefers npm",
      "",
      "That's all."
    ].join("\n")
  );
  assert.deepEqual(parsed.writes, [
    { fact: "The user prefers pnpm", tier: "profile" },
    { fact: "Fixed the flaky login test", tier: "log" },
    { fact: "vitest did not work here", tier: "note" }
  ]);
  assert.deepEqual(parsed.removals, ["The user prefers npm"]);
});

test("an extraction that found nothing parses as nothing, not as an error", () => {
  assert.deepEqual(parseExtraction("Nothing worth recording here."), { writes: [], removals: [] });
  assert.deepEqual(parseExtraction(""), { writes: [], removals: [] });
});

test("normalize strips list bullets the model tends to add", () => {
  assert.equal(normalize("- The  user   prefers pnpm."), "The user prefers pnpm");
  assert.equal(dedupeKey("The User Prefers PNPM!"), "the user prefers pnpm");
});
