import assert from "node:assert/strict";
import { test } from "node:test";
import {
  appendAssistantDelta,
  eventFromChatMessage,
  OutboundMessage,
  parseTranscriptLine,
  projectAgent
} from "./transcript.js";

test("parseTranscriptLine reads an event-shaped jsonl line", () => {
  const event = parseTranscriptLine({ type: "user", id: "u", seq: 1, createdAt: 1, text: "x" });
  assert.deepEqual(event, { type: "user", id: "u", seq: 1, createdAt: 1, text: "x" });
});

test("parseTranscriptLine upgrades a legacy ChatMessage user line", () => {
  const event = parseTranscriptLine({
    id: "u1",
    role: "user",
    content: "hello",
    seq: 1,
    createdAt: 10
  });
  assert.deepEqual(event, { type: "user", id: "u1", seq: 1, createdAt: 10, text: "hello" });
});

test("eventFromChatMessage keeps thinking as a part", () => {
  const event = eventFromChatMessage({
    id: "a1",
    role: "assistant",
    content: "hello",
    thinking: "plan",
    seq: 2,
    createdAt: 11
  });
  assert.equal(event?.type, "assistant");
  if (event?.type !== "assistant") return;
  assert.deepEqual(event.parts[0], { type: "thinking", text: "plan" });
});

test("parseTranscriptLine upgrades assistant toolCalls into parts", () => {
  const event = parseTranscriptLine({
    id: "a1",
    role: "assistant",
    content: "working",
    toolCalls: [{ id: "c1", name: "read", arguments: { path: "a.ts" } }],
    seq: 2,
    createdAt: 11
  });
  assert.equal(event?.type, "assistant");
  if (event?.type !== "assistant") return;
  assert.deepEqual(event.parts, [
    { type: "text", text: "working" },
    { type: "tool_call", id: "c1", name: "read", arguments: { path: "a.ts" } }
  ]);
});

test("parseTranscriptLine skips legacy system messages", () => {
  assert.equal(
    eventFromChatMessage({
      id: "sys",
      role: "system",
      content: "hidden",
      seq: 0,
      createdAt: 0
    }),
    null
  );
});

test("projectAgent groups tool results under the assistant turn", () => {
  const view = projectAgent([
    { type: "user", id: "u1", seq: 1, createdAt: 1, text: "list files" },
    {
      type: "assistant",
      id: "a1",
      seq: 2,
      createdAt: 2,
      parts: [
        { type: "thinking", text: "I should read" },
        { type: "text", text: "reading" },
        { type: "tool_call", id: "c1", name: "bash", arguments: { command: "ls" } }
      ]
    },
    { type: "tool", id: "t1", seq: 3, createdAt: 3, toolCallId: "c1", name: "bash", content: "a.ts", ok: true }
  ]);
  assert.deepEqual(view.blocks, [
    { type: "user", id: "u1", text: "list files" },
    {
      type: "assistant",
      id: "a1",
      thinking: "I should read",
      tools: [{ id: "c1", name: "bash", arguments: { command: "ls" }, output: "a.ts", status: "ok" }]
    }
  ]);
});

test("SendMessage projects only as its delivered bubble, not as a tool card or draft", () => {
  const view = projectAgent([
    { type: "user", id: "u1", seq: 1, createdAt: 1, text: "say hi" },
    {
      type: "assistant",
      id: "a1",
      seq: 2,
      createdAt: 2,
      parts: [
        { type: "text", text: "draft: maybe say hello" },
        { type: "tool_call", id: "c1", name: "SendMessage", arguments: { type: "text", content: "hi" } }
      ]
    },
    {
      type: "message",
      id: "m1",
      seq: 3,
      createdAt: 3,
      assistantId: "a1",
      toolCallId: "c1",
      payload: { type: "text", content: "hi" }
    },
    {
      type: "tool",
      id: "t1",
      seq: 4,
      createdAt: 4,
      assistantId: "a1",
      toolCallId: "c1",
      name: "SendMessage",
      content: "Delivered.",
      ok: true
    }
  ]);
  assert.deepEqual(
    view.blocks.map((block) => [block.type, block.id]),
    [
      ["user", "u1"],
      ["message", "m1"]
    ]
  );
  assert.equal(view.blocks.some((block) => block.type === "assistant"), false);
});

test("agent wakes render as peer messages while profile and compact stay notices", () => {
  const view = projectAgent([
    {
      type: "wake",
      id: "w1",
      seq: 1,
      createdAt: 1,
      source: { kind: "agent", fromId: "a2", fromName: "Scout" },
      text: "check the logs",
      hops: 1
    },
    { type: "profile", id: "p1", seq: 2, createdAt: 2, patch: { name: "Ranger" } },
    { type: "compact", id: "k1", seq: 3, createdAt: 3, epoch: 1, throughSeq: 2, tailFromSeq: 3, summary: "..." }
  ]);
  assert.deepEqual(
    view.blocks.map((block) => [block.type, (block as any).kind]),
    [
      ["peer", undefined],
      ["notice", "profile"],
      ["notice", "compact"]
    ]
  );
  assert.deepEqual(view.blocks[0], {
    type: "peer",
    id: "w1",
    direction: "inbound",
    agentId: "a2",
    agentName: "Scout",
    text: "check the logs",
    priority: false
  });
  assert.ok((view.blocks[1] as any).text.includes("Ranger"));
});

test("SendToAgent projects as one outbound peer message instead of a tool card", () => {
  const view = projectAgent([
    {
      type: "assistant",
      id: "a1",
      seq: 1,
      createdAt: 1,
      parts: [
        {
          type: "tool_call",
          id: "c1",
          name: "SendToAgent",
          arguments: { agent_id: "beta", message: "please inspect auth", priority: true }
        }
      ]
    },
    {
      type: "tool",
      id: "t1",
      seq: 2,
      createdAt: 2,
      assistantId: "a1",
      toolCallId: "c1",
      name: "SendToAgent",
      content: "Sent to Beta as priority.",
      ok: true
    }
  ]);

  assert.deepEqual(view.blocks, [
    {
      type: "peer",
      id: "c1",
      direction: "outbound",
      agentId: "beta",
      agentName: "Beta",
      text: "please inspect auth",
      priority: true
    }
  ]);
});

test("a failed SendToAgent remains a visible tool error instead of faking delivery", () => {
  const view = projectAgent([
    {
      type: "assistant",
      id: "a1",
      seq: 1,
      createdAt: 1,
      parts: [{
        type: "tool_call",
        id: "c1",
        name: "SendToAgent",
        arguments: { agent_id: "missing", message: "hello" }
      }]
    },
    {
      type: "tool",
      id: "t1",
      seq: 2,
      createdAt: 2,
      assistantId: "a1",
      toolCallId: "c1",
      name: "SendToAgent",
      content: "No agent with id missing.",
      ok: false
    }
  ]);

  assert.equal(view.blocks.some((block) => block.type === "peer"), false);
  assert.deepEqual(view.blocks[0], {
    type: "assistant",
    id: "a1",
    thinking: "",
    tools: [{
      id: "c1",
      name: "SendToAgent",
      arguments: { agent_id: "missing", message: "hello" },
      output: "No agent with id missing.",
      status: "error"
    }]
  });
});

test("a pending SendToAgent is activity, not a delivered peer message", () => {
  const view = projectAgent([], {
    messageId: "a-live",
    parts: [{
      type: "tool_call",
      id: "c1",
      name: "SendToAgent",
      arguments: { agent_id: "beta", message: "still sending" }
    }]
  });

  assert.equal(view.blocks.some((block) => block.type === "peer"), false);
  assert.deepEqual(view.blocks[0], {
    type: "assistant",
    id: "a-live",
    thinking: "",
    tools: [{
      id: "c1",
      name: "SendToAgent",
      arguments: { agent_id: "beta", message: "still sending" },
      output: undefined,
      status: "pending"
    }],
    live: true
  });
});

test("projectAgent appends live thinking that is not yet on disk", () => {
  const view = projectAgent(
    [{ type: "user", id: "u1", seq: 1, createdAt: 1, text: "hi" }],
    { messageId: "a-live", parts: appendAssistantDelta([], "thinking", "hmm") }
  );
  assert.deepEqual(view.blocks[1], {
    type: "assistant",
    id: "a-live",
    thinking: "hmm",
    tools: [],
    live: true
  });
});

test("OutboundMessage normalizes legacy text payloads at the parse boundary", () => {
  const legacy = { type: "text", text: "hi", images: ["/tmp/a.png", { path: "/tmp/b.png", alt: "b" }] };
  const parsed = OutboundMessage.parse(legacy);
  assert.deepEqual(parsed, {
    type: "text",
    content: "hi",
    images: [{ path: "/tmp/a.png" }, { path: "/tmp/b.png", alt: "b" }]
  });
});

test("OutboundMessage still reads legacy name+props widget payloads", () => {
  const parsed = OutboundMessage.parse({ type: "widget", widget: "color-picker", props: { from: "#fff" } });
  assert.deepEqual(parsed, { type: "widget", widget: "color-picker", props: { from: "#fff" } });
});

test("OutboundMessage accepts a structured widget payload", () => {
  const payload = {
    type: "widget",
    widget: {
      prompt: "Deploy to production?",
      options: [
        { label: "Deploy", value: "Yes, deploy now", style: "primary" },
        { label: "Cancel", style: "danger" }
      ],
      allowCustom: true
    }
  };
  const parsed = OutboundMessage.parse(payload);
  assert.equal(parsed.type, "widget");
  if (parsed.type === "widget" && typeof parsed.widget !== "string") {
    assert.equal(parsed.widget.options[1]?.label, "Cancel");
    assert.equal(parsed.widget.options[0]?.value, "Yes, deploy now");
  }
});

test("room participation remains visible without exposing the internal model prompt", () => {
  const result = projectAgent([{ type: "wake", id: "w", seq: 1, createdAt: 1, hops: 0, text: "Trigger: internal instructions", source: { kind: "work", workId: "room", workName: "Design", bridgeId: "w" } }]);
  assert.ok(JSON.stringify(result).includes("Design"));
  assert.equal(JSON.stringify(result).includes("Trigger:"), false);
});
