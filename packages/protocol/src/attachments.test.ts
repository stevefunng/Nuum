import test from "node:test";
import assert from "node:assert/strict";
import { AgentSendParams } from "./host-contract.js";
import { AttachmentUpload, MAX_ATTACHMENT_BYTES, supportsImageInput } from "./attachments.js";

test("attachment-only messages are allowed, empty and malformed uploads are rejected", () => {
  const file = { name: "note.txt", mimeType: "text/plain", data: "YQ==" };
  assert.equal(AgentSendParams.safeParse({ id: "a", content: "", attachments: [file] }).success, true);
  assert.equal(AgentSendParams.safeParse({ id: "a", content: "  " }).success, false);
  assert.equal(AgentSendParams.safeParse({ id: "a", content: "", attachments: [{ ...file, data: "not base64" }] }).success, false);
  assert.equal(AgentSendParams.safeParse({ id: "a", content: "", attachments: Array(6).fill(file) }).success, false);
});

test("unknown or text-only model IDs do not receive unsupported image payloads", () => {
  assert.equal(supportsImageInput({ provider: "deepseek", model: "deepseek-chat" }), false);
  assert.equal(supportsImageInput({ provider: "openai", model: "custom-model" }), false);
  assert.equal(supportsImageInput({ provider: "openai", model: "o3-mini" }), false);
  assert.equal(supportsImageInput({ provider: "openai", model: "gpt-4o" }), true);
  assert.equal(supportsImageInput({ provider: "anthropic", model: "claude-sonnet-4-20250514" }), true);
});


test("large valid uploads fit the limit without a recursive base64 validator", () => {
  const data = Buffer.alloc(MAX_ATTACHMENT_BYTES, 1).toString("base64");
  assert.equal(AttachmentUpload.safeParse({ name: "large.bin", mimeType: "application/octet-stream", data }).success, true);
});
