import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { saveAttachments, hydrateAttachmentImages } from "./attachments.js";

test("uploads are copied inside the workspace and text is supplied to text-only models", async () => {
 const root = await mkdtemp(path.join(tmpdir(), "nuum-attachment-"));
 try {
  const [file] = await saveAttachments(root, [{ name: "../../note.txt", mimeType: "text/plain", data: Buffer.from("Hello attachment").toString("base64") }]);
  assert.ok(file);
  assert.ok(file.path.startsWith(root + path.sep));
  assert.equal(file.name, "note.txt");
  assert.equal(file.text, "Hello attachment");
  assert.equal(await readFile(file.path, "utf8"), "Hello attachment");
  const again = await saveAttachments(root, [{ name: "note.txt", mimeType: "text/plain", data: "Qg==" }]);
  assert.notEqual(again[0]!.path, file.path);
 } finally { await rm(root, { recursive: true, force: true }); }
});

test("image hydration stays inside imported attachments and respects model support", async () => {
 const root = await mkdtemp(path.join(tmpdir(), "nuum-attachment-"));
 try {
  const files = await saveAttachments(root, [{ name: "pixel.png", mimeType: "image/png", data: "aGVsbG8=" }]);
  const event = { type: "user" as const, id: "u", text: "", seq: 1, createdAt: 1, attachments: files };
  const message = { id: "u", role: "user" as const, content: "", seq: 1, createdAt: 1 };
  const vision = await hydrateAttachmentImages([message], [event], root, { provider: "openai", model: "gpt-4o" });
  assert.equal(vision[0]!.images?.[0]?.data, "aGVsbG8=");
  const textOnly = await hydrateAttachmentImages([message], [event], root, { provider: "deepseek", model: "deepseek-chat" });
  assert.equal(textOnly[0]!.images, undefined);
  const escaped = await hydrateAttachmentImages([message], [{ ...event, attachments: [{ ...files[0]!, path: "/etc/passwd" }] }], root, { provider: "openai", model: "gpt-4o" });
  assert.equal(escaped[0]!.images?.length ?? 0, 0);
 } finally { await rm(root, { recursive: true, force: true }); }
});
