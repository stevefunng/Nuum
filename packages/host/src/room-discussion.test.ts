import assert from "node:assert/strict";
import { test } from "node:test";
import { discussionResponders, orderSpeakers, isPass, discussionLimits } from "./room-discussion.js";
const members = [{ id: "a", name: "Alice Smith" }, { id: "b", name: "Bob" }];
test("Grokbot-style mentions accumulate since the latest user message", () => {
  assert.deepEqual(discussionResponders(members, [{ body: "hello", mentionedAgentIds: [] }]).map(x => x.id), ["a", "b"]);
  assert.deepEqual(discussionResponders(members, [{ body: "@Alice hello", mentionedAgentIds: [] }, { body: "@Bob check", mentionedAgentIds: [] }]).map(x => x.id), ["a", "b"]);
  assert.deepEqual(discussionResponders(members, [{ body: "@BOB check", mentionedAgentIds: [] }]).map(x => x.id), ["b"]);
  assert.deepEqual(discussionResponders(members, [{ body: "@Bobby", mentionedAgentIds: [] }]).map(x => x.id), ["a", "b"]);
  assert.deepEqual(discussionResponders(members, [{ body: "@Alice @all", mentionedAgentIds: [] }]).map(x => x.id), ["a", "b"]);
});
test("round rotation and pass follow the bounded room policy", () => {
  assert.deepEqual(orderSpeakers(["a", "b"], 1), ["b", "a"]);
  assert.equal(isPass(" (pass). "), true);
  assert.equal(isPass("a useful message"), false);
  assert.deepEqual(discussionLimits, { rounds: 3, messages: 10, perTurn: 2 });
});

test("sequential loop rotates, excludes failed members and stops on a silent round", async () => {
  const { runDiscussion } = await import("./room-discussion.js");
  const calls: string[] = [];
  await runDiscussion({ current: () => true, responders: async () => ["a", "b"], runMember: async id => {
    calls.push(id);
    return { messages: calls.length === 1 ? 1 : 0, failed: id === "b" };
  } });
  assert.deepEqual(calls, ["a", "b", "a"]);
});
