import assert from "node:assert/strict";
import { test } from "node:test";
import { summarizePrefix } from "./compaction.js";
import type { KernelClient } from "./kernel-client.js";

const params = { runId: "r", model: { provider: "deepseek" as const, model: "deepseek-chat" }, secrets: {}, systemPrompt: "Summarize evidence", current: () => true };
test("large summary input is reduced in bounded chunks without dropping the end", async () => {
  const inputs: string[] = [];
  const kernel = { summarize: async (request: any) => { inputs.push(request.messages[0].content); return { text: "summary" }; } } as KernelClient;
  const summary = await summarizePrefix(kernel, { ...params, messages: [{ id: "large", role: "user", content: "x".repeat(50000) + "LAST_FACT", seq: 1, createdAt: 0 }] });
  assert.equal(summary, "summary");
  assert.ok(inputs.some(input => input.includes("LAST_FACT")));
  assert.ok(inputs.every(input => input.length <= 24000));
});
test("summary retries are bounded and cancellation stops subsequent chunks", async () => {
  let calls = 0;
  const kernel = { summarize: async () => { calls++; throw new Error("failed"); } } as unknown as KernelClient;
  const request = { ...params, messages: [{ id: "m", role: "user" as const, content: "evidence", seq: 1, createdAt: 0 }] };
  await assert.rejects(summarizePrefix(kernel, request), /failed/);
  assert.equal(calls, 2);
  await assert.rejects(summarizePrefix(kernel, { ...request, current: () => false }), /cancelled/);
  assert.equal(calls, 2);
});
