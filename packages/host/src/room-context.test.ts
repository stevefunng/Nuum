import assert from "node:assert/strict";
import { test } from "node:test";
import type { WorkEvent } from "@nuum/protocol";
const events: WorkEvent[] = Array.from({ length: 30 }, (_, index) => ({
  type: "chat.posted", id: `e${index + 1}`, messageId: `m${index + 1}`, seq: index + 1,
  workId: "r", createdAt: index, actor: { kind: "agent", id: "a" }, body: `Message ${index + 1}`, mentionedAgentIds: []
}));
test("only uninterrupted same-room input in the same compact epoch continues", async () => {
  const { selectRoomInput } = await import("./room-context.js");
  const prior: any = { type: "wake", id: "w", seq: 1, createdAt: 1, hops: 0, text: "history", source: { kind: "work", workId: "r", workName: "R", bridgeId: "w", roomInput: { membershipRevision: 1, fromSeq: 0, throughSeq: 28, messageIds: [], epoch: 0, mode: "background" } } };
  assert.deepEqual(selectRoomInput(events, [prior], "r", 1).messages.map(m => m.seq), [29, 30]);
  assert.equal(selectRoomInput(events, [], "r", 1).messages.length, 24);
  assert.equal(selectRoomInput(events, [prior, { type: "user", id: "u", seq: 2, createdAt: 2, text: "private" }], "r", 1).mode, "background");
  assert.equal(selectRoomInput(events, [prior, { type: "compact", id: "c", seq: 2, createdAt: 2, epoch: 1, summary: "summary", throughSeq: 0, tailFromSeq: 1 }], "r", 1).mode, "background");
  assert.equal(selectRoomInput(events, [prior], "r", 2).mode, "background");
  assert.ok(selectRoomInput(events, [], "r", 1, ["e1"]).messages.some(m => m.seq === 1));
});
