import type { ChatMessage, ModelRef, ToolDefinition } from "@nuum/protocol";

export interface NormalizedChatRequest {
  model: ModelRef;
  messages: ChatMessage[];
  tools: ToolDefinition[];
  apiKey: string;
  maxOutputTokens?: number;
}

export type NormalizedChunk =
  | { type: "text"; text: string }
  | { type: "thinking"; text: string }
  | { type: "tool_call"; id: string; name: string; arguments: Record<string, unknown> };

export interface ModelPort {
  streamChat(req: NormalizedChatRequest, signal: AbortSignal): AsyncIterable<NormalizedChunk>;
}
