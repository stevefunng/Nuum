import { mkdir, mkdtemp, readFile, realpath, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { AttachmentUpload, MAX_ATTACHMENTS, MAX_ATTACHMENT_BYTES, IMAGE_MIME_TYPES, supportsImageInput, type ChatMessage, type ModelRef, type TranscriptEvent, type UserAttachment } from "@nuum/protocol";

export async function saveAttachments(root: string, uploads: readonly AttachmentUpload[]): Promise<UserAttachment[]> {
  if (uploads.length > MAX_ATTACHMENTS) throw new Error("At most 5 attachments per message.");
  const decoded = uploads.map(raw => {
    const upload = AttachmentUpload.parse(raw);
    const bytes = Buffer.from(upload.data, "base64");
    if (bytes.length > MAX_ATTACHMENT_BYTES) throw new Error("Each attachment must be 10 MB or smaller.");
    return { upload, bytes };
  });
  if (decoded.reduce((sum, item) => sum + item.bytes.length, 0) > 20 * 1024 * 1024) throw new Error("Attachments must total 20 MB or less.");
  const directory = path.join(root, ".nuum-attachments");
  await mkdir(directory, { recursive: true });
  const canonicalRoot = await realpath(root);
  if (await realpath(directory) !== path.join(canonicalRoot, ".nuum-attachments")) throw new Error("Attachment directory must not be a symbolic link.");
  const batch = await mkdtemp(path.join(directory, "upload-"));
  const result: UserAttachment[] = [];
  for (const { upload, bytes } of decoded) {
    const name = path.basename(upload.name.replaceAll("\\", "/")).replace(/[\x00-\x1f]/g, "_");
    if (!name || name === "." || name === "..") throw new Error("Invalid attachment name.");
    const filePath = path.join(batch, `${result.length}-${name}`);
    await writeFile(filePath, bytes, { flag: "wx", mode: 0o600 });
    let text: string | undefined;
    if (bytes.length <= 64 * 1024 && !upload.mimeType.startsWith("image/")) {
      try {
        const decodedText = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
        if (!decodedText.includes("\0")) text = decodedText;
      } catch { /* Binary files remain available through workspace file tools. */ }
    }
    result.push({ name, path: filePath, mimeType: upload.mimeType, size: bytes.length, ...(text !== undefined ? { text } : {}) });
  }
  return result;
}

/** Images live on disk; only the active model request receives base64. */
export async function hydrateAttachmentImages(messages: ChatMessage[], events: readonly TranscriptEvent[], root: string, model: ModelRef): Promise<ChatMessage[]> {
  if (!supportsImageInput(model)) return messages;
  const directory = path.join(await realpath(root), ".nuum-attachments") + path.sep;
  const users = new Map(events.filter(event => event.type === "user").map(event => [event.id, event]));
  return Promise.all(messages.map(async message => {
    const attachments = users.get(message.id)?.attachments;
    if (message.role !== "user" || !attachments?.length) return message;
    const images = [];
    const unavailable: string[] = [];
    for (const file of attachments) {
      if (!(IMAGE_MIME_TYPES as readonly string[]).includes(file.mimeType)) continue;
      try {
        const canonical = await realpath(file.path);
        if (!canonical.startsWith(directory)) throw new Error("Outside attachment directory");
        if ((await stat(canonical)).size > MAX_ATTACHMENT_BYTES) throw new Error("Image too large");
        images.push({ mimeType: file.mimeType as typeof IMAGE_MIME_TYPES[number], data: (await readFile(canonical)).toString("base64") });
      } catch { unavailable.push(file.name); }
    }
    return { ...message, images, content: message.content + (unavailable.length ? `\n[Image uploads unavailable: ${unavailable.join(", ")}. Ask the user to attach them again.]` : "") };
  }));
}
