import test from "node:test";
import assert from "node:assert/strict";
import { groupToolActivity } from "./activity-groups";
import type { ViewBlock } from "@nuum/protocol";
const activity = (id: string): ViewBlock => ({ type: "assistant", id, thinking: "", tools: [{ id, name: "shell", arguments: {}, status: "ok" }] });
test("consecutive tool calls group across assistant events, but never across a visible message", () => {
  const blocks: ViewBlock[] = [activity("a"), { type: "assistant", id: "hidden", thinking: "", tools: [] }, activity("b"), { type: "message", id: "reply", payload: { type: "text", content: "Done" } }, activity("c")];
  const result = groupToolActivity(blocks);
  assert.equal(result.length, 3);
  assert.equal(result[0]!.id, "a");
  assert.deepEqual(result[0]!.type === "assistant" && result[0]!.tools.map(t => t.id), ["a", "b"]);
  assert.equal(blocks.length, 5);
});
