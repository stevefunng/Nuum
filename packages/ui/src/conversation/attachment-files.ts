import { MAX_ATTACHMENTS, MAX_ATTACHMENT_BYTES, type AttachmentUpload } from "@nuum/protocol";

export async function readAttachmentFiles(files: readonly File[], current: readonly AttachmentUpload[]): Promise<AttachmentUpload[]> {
  if (files.length + current.length > MAX_ATTACHMENTS) throw new Error("At most 5 attachments per message.");
  if (files.some(file => file.size > MAX_ATTACHMENT_BYTES)) throw new Error("Each attachment must be 10 MB or smaller.");
  const currentBytes = current.reduce((sum, file) => sum + Math.floor(file.data.length * 3 / 4), 0);
  if (currentBytes + files.reduce((sum, file) => sum + file.size, 0) > 20 * 1024 * 1024) throw new Error("Attachments must total 20 MB or less.");
  return Promise.all(files.map(file => new Promise<AttachmentUpload>((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("Could not read attachment."));
    reader.onload = () => resolve({ name: file.name, mimeType: file.type || "application/octet-stream", data: String(reader.result).split(",")[1] ?? "" });
    reader.readAsDataURL(file);
  })));
}
