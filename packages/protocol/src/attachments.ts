import { z } from "zod";
import type { ModelRef } from "./domain.js";

export const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;
export const MAX_ATTACHMENTS = 5;
export const AttachmentUpload = z.object({
  name: z.string().min(1).max(255),
  mimeType: z.string().max(120),
  data: z.string().max(Math.ceil(MAX_ATTACHMENT_BYTES / 3) * 4).regex(/^[A-Za-z0-9+/]*={0,2}$/).refine(data => data.length % 4 === 0, "Invalid base64 length")
});
export type AttachmentUpload = z.infer<typeof AttachmentUpload>;
export const UserAttachment = z.object({
  name: z.string(), path: z.string(), mimeType: z.string(), size: z.number().int().nonnegative(),
  /** Small UTF-8 uploads are available to text-only models without a tool round trip. */
  text: z.string().optional()
});
export type UserAttachment = z.infer<typeof UserAttachment>;
export const IMAGE_MIME_TYPES = ["image/png", "image/jpeg", "image/gif", "image/webp"] as const;

/** Conservative defaults for manually entered model IDs; unknown IDs use file tools. */
export function supportsImageInput(model: ModelRef): boolean {
  if (model.provider === "deepseek") return false;
  if (model.provider === "anthropic") return /^claude-(?:3|sonnet-4|opus-4|haiku-4)/i.test(model.model);
  return /^(?:gpt-4o|gpt-4\.1|gpt-4-turbo|gpt-5|o1(?!-mini|-preview)|o3(?!-mini)|o4)/i.test(model.model);
}
