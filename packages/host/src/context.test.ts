import assert from "node:assert/strict";
import { test } from "node:test";
import { assembleContext, partitionForCompaction, repairTranscript } from "./context.js";
import type { TranscriptEvent } from "@nuum/protocol";

function event(partial: TranscriptEvent): TranscriptEvent {
  return partial;
}

test("repairTranscript injects tool results for unpaired assistant tool_calls", () => {
  const assistant = event({
    type: "assistant",
    id: "a1",
    seq: 1,
    createdAt: 1,
    parts: [{ type: "tool_call", id: "call-1", name: "bash", arguments: { command: "ls" } }]
  });
  const user = event({ type: "user", id: "u2", seq: 2, createdAt: 2, text: "continue" });
  const { events, injected } = repairTranscript([assistant, user]);
  assert.equal(injected.length, 1);
  assert.equal(injected[0]?.type, "tool");
  assert.equal(injected[0]?.type === "tool" && injected[0].toolCallId, "call-1");
  assert.equal(events[0]?.id, "a1");
  assert.equal(events[1]?.type === "tool" && events[1].toolCallId, "call-1");
  assert.equal(events[2]?.id, "u2");
});

test("repairTranscript is a no-op when every tool_call already has a result", () => {
  const assistant = event({
    type: "assistant",
    id: "a1",
    seq: 1,
    createdAt: 1,
    parts: [{ type: "tool_call", id: "call-1", name: "bash", arguments: {} }]
  });
  const tool = event({
    type: "tool",
    id: "t1",
    seq: 2,
    createdAt: 2,
    toolCallId: "call-1",
    name: "bash",
    content: "ok"
  });
  const { events, injected } = repairTranscript([assistant, tool]);
  assert.deepEqual(injected, []);
  assert.deepEqual(events, [assistant, tool]);
});

test("repairTranscript pairs tool results by causal id instead of physical adjacency", () => {
  const assistant = event({
    type: "assistant",
    id: "a1",
    seq: 2,
    createdAt: 2,
    parts: [{ type: "tool_call", id: "call-1", name: "SendMessage", arguments: { type: "text", text: "hi" } }]
  });
  const message = event({
    type: "message",
    id: "m1",
    seq: 3,
    createdAt: 3,
    payload: { type: "text", content: "hi" }
  });
  const tool = event({
    type: "tool",
    id: "t1",
    seq: 4,
    createdAt: 4,
    toolCallId: "call-1",
    name: "SendMessage",
    content: "Delivered.",
    ok: true
  });

  const repaired = repairTranscript([assistant, message, tool]);
  assert.deepEqual(repaired.injected, []);
  assert.deepEqual(repaired.events.map((item) => item.id), ["a1", "t1", "m1"]);
});

test("assembleContext derives one valid model history from a corrupted legacy UI timeline", () => {
  const assembled = assembleContext({
    systemPrompt: "system",
    transcript: [
      { type: "user", id: "u1", seq: 1, createdAt: 1, text: "hi" },
      {
        type: "assistant",
        id: "a1",
        seq: 2,
        createdAt: 2,
        parts: [{ type: "tool_call", id: "call-1", name: "SendMessage", arguments: { type: "text", text: "hello" } }]
      },
      { type: "message", id: "m1", seq: 3, createdAt: 3, payload: { type: "text", content: "hello" } },
      { type: "tool", id: "t1", seq: 4, createdAt: 4, toolCallId: "call-1", name: "SendMessage", content: "Delivered.", ok: true },
      { type: "assistant", id: "a2", seq: 5, createdAt: 5, parts: [{ type: "text", text: "private follow-up" }] },
      {
        type: "tool",
        id: "missing-tool-call-1",
        seq: 6,
        createdAt: 6,
        toolCallId: "call-1",
        name: "SendMessage",
        content: "Tool call was interrupted and did not return a result.",
        ok: false
      },
      { type: "user", id: "u2", seq: 7, createdAt: 7, text: "who are you" }
    ]
  });

  assert.deepEqual(assembled.map((message) => message.role), [
    "system",
    "user",
    "assistant",
    "tool",
    "assistant",
    "user"
  ]);
  assert.equal(assembled.filter((message) => message.role === "tool").length, 1);
  assert.equal(assembled.some((message) => message.id === "m1"), false);
});

test("a persisted delivery derives a successful model ack when the tool result was lost", () => {
  const assembled = assembleContext({
    systemPrompt: "system",
    transcript: [
      {
        type: "assistant",
        id: "a1",
        seq: 1,
        createdAt: 1,
        parts: [{ type: "tool_call", id: "call-1", name: "SendMessage", arguments: { type: "text", text: "hello" } }]
      },
      {
        type: "message",
        id: "m1",
        seq: 2,
        createdAt: 2,
        assistantId: "a1",
        toolCallId: "call-1",
        payload: { type: "text", content: "hello" }
      }
    ]
  });

  assert.deepEqual(assembled.map((message) => message.role), ["system", "assistant", "tool"]);
  assert.equal(assembled[2]!.content, "Delivered.");
});

test("assembleContext prepends system, keeps thinking, and repairs history", () => {
  const assembled = assembleContext({
    systemPrompt: "you are nuum",
    transcript: [
      {
        type: "assistant",
        id: "a1",
        seq: 1,
        createdAt: 1,
        parts: [
          { type: "thinking", text: "plan" },
          { type: "text", text: "calling" },
          { type: "tool_call", id: "call-9", name: "read", arguments: { path: "a.ts" } }
        ]
      }
    ]
  });
  assert.equal(assembled[0]?.role, "system");
  assert.equal(assembled[1]?.role, "assistant");
  assert.equal(assembled[1]?.content, "calling");
  assert.equal(assembled[1]?.thinking, "plan");
  assert.equal(assembled[1]?.toolCalls?.[0]?.id, "call-9");
  assert.equal(assembled[2]?.role, "tool");
  assert.equal(assembled[2]?.toolCallId, "call-9");
});

test("an inbound agent wake is a hidden peer turn and replies through SendToAgent", () => {
  const assembled = assembleContext({
    systemPrompt: "system",
    transcript: [
      {
        type: "wake",
        id: "w1",
        seq: 1,
        createdAt: 1,
        source: { kind: "agent", fromId: "alpha", fromName: "Alpha" },
        text: "Can you check auth?",
        hops: 1
      }
    ]
  });

  assert.equal(assembled[1]?.role, "user");
  assert.match(assembled[1]?.content ?? "", /message just arrived from another.*agent/i);
  assert.match(assembled[1]?.content ?? "", /SendToAgent/);
  assert.match(assembled[1]?.content ?? "", /alpha/);
  assert.doesNotMatch(assembled[1]?.content ?? "", /call SendMessage to actually reply/);
});

test("a Work wake directs output to Work tools instead of the private chat", () => {
  const assembled = assembleContext({
    systemPrompt: "system",
    transcript: [{
      type: "wake",
      id: "w-work",
      seq: 1,
      createdAt: 1,
      source: { kind: "work", workId: "work-1", workName: "Launch", bridgeId: "bridge-1", taskId: "task-1" },
      text: "Prepare the release",
      hops: 0
    }]
  });
  assert.match(assembled[1]?.content ?? "", /SendMessage/);
  assert.match(assembled[1]?.content ?? "", /cardAction/);
  assert.match(assembled[1]?.content ?? "", /not a private user message/i);
  assert.doesNotMatch(assembled[1]?.content ?? "", /call SendMessage to actually reply/);
});

test("assembleContext folds multiple checkpoints into the last summary", () => {
  const assembled = assembleContext({
    systemPrompt: "system",
    transcript: [
      { type: "user", id: "u1", seq: 1, createdAt: 1, text: "forgotten" },
      { type: "compact", id: "c1", seq: 4, createdAt: 4, epoch: 1, throughSeq: 1, tailFromSeq: 2, summary: "old summary" },
      { type: "user", id: "u2", seq: 2, createdAt: 2, text: "also folded" },
      { type: "assistant", id: "a2", seq: 3, createdAt: 3, parts: [{ type: "text", text: "old answer" }] },
      { type: "user", id: "u3", seq: 5, createdAt: 5, text: "keep me" },
      { type: "assistant", id: "a3", seq: 6, createdAt: 6, parts: [{ type: "text", text: "kept answer" }] },
      { type: "compact", id: "c2", seq: 7, createdAt: 7, epoch: 2, throughSeq: 4, tailFromSeq: 5, summary: "latest summary" }
    ]
  });
  const summaries = assembled.filter((message) => message.content.startsWith("[previous conversation summary]"));
  assert.equal(summaries.length, 1);
  assert.ok(summaries[0]!.content.includes("latest summary"));
  assert.equal(assembled.some((message) => message.content.includes("forgotten")), false);
  assert.equal(assembled.some((message) => message.content.includes("keep me")), true);
});

test("compaction preserves exactly the newest user turn and folds the previous summary", () => {
  const partition = partitionForCompaction([
    { type: "compact", id: "c1", seq: 5, createdAt: 5, epoch: 1, throughSeq: 2, tailFromSeq: 3, summary: "generation one" },
    { type: "user", id: "u2", seq: 3, createdAt: 3, text: "previous turn" },
    { type: "assistant", id: "a2", seq: 4, createdAt: 4, parts: [{ type: "text", text: "previous answer" }] },
    { type: "user", id: "u3", seq: 6, createdAt: 6, text: "current turn" },
    { type: "assistant", id: "a3", seq: 7, createdAt: 7, parts: [{ type: "text", text: "current work" }] }
  ]);
  assert.ok(partition);
  assert.equal(partition.tailFromSeq, 6);
  assert.equal(partition.throughSeq, 5);
  assert.equal(partition.preservedTail[0]?.role, "user");
  assert.equal(partition.preservedTail.filter((message) => message.role === "user").length, 1);
  assert.equal(partition.messagesToSummarize.some((message) => message.content.includes("generation one")), true);
});

test("long runs compact completed steps without splitting a tool exchange", () => {
  const events: TranscriptEvent[] = [
    { type: "user", id: "u", seq: 1, createdAt: 1, text: "Build it" },
    { type: "assistant", id: "a", seq: 2, createdAt: 2, parts: [{ type: "tool_call", id: "c", name: "read", arguments: {} }] },
    { type: "tool", id: "t", seq: 3, createdAt: 3, assistantId: "a", toolCallId: "c", name: "read", content: "result" },
    { type: "assistant", id: "b", seq: 4, createdAt: 4, parts: [{ type: "text", text: "Next step" }] }
  ];
  const partition = partitionForCompaction(events, true);
  assert.equal(partition?.tailFromSeq, 4);
  assert.equal(partition?.preservedTail[0]?.id, "b");
  assert.ok(partition?.messagesToSummarize.some(message => message.role === "tool"));
});
