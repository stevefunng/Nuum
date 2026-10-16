import type { ChatMessage, ToolDefinition } from "./domain.js";

/** Conservative fallback, not a provider tokenizer. Includes envelope/tool schemas and images. */
export function estimateModelTokens(messages: readonly ChatMessage[], tools: readonly ToolDefinition[] = []): number {
  const text = JSON.stringify({ messages: messages.map(({ images, ...message }) => message), tools });
  const wide = (text.match(/[^\u0000-\u007f]/g) ?? []).length;
  return Math.ceil((text.length - wide) / 3 + wide * 2) + messages.reduce((total, message) => total + (message.images?.length ?? 0) * 8192, 0);
}
