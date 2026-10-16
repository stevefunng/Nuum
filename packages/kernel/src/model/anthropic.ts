import { KernelErrorCode, RpcError, type ChatMessage } from "@nuum/protocol";
import type { ModelPort, NormalizedChatRequest, NormalizedChunk } from "./types.js";

export class AnthropicModel implements ModelPort {
  constructor(private readonly baseUrl = "https://api.anthropic.com/v1") {}

  async *streamChat(req: NormalizedChatRequest, signal: AbortSignal): AsyncIterable<NormalizedChunk> {
    const system = req.messages.filter((message) => message.role === "system").map((message) => message.content).join("\n\n");
    const response = await fetch(`${this.baseUrl}/messages`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": req.apiKey,
        "anthropic-version": "2023-06-01"
      },
      body: JSON.stringify({
        model: req.model.model,
        max_tokens: req.maxOutputTokens ?? 4096,
        stream: true,
        system: system || undefined,
        messages: toAnthropicMessages(req.messages.filter((message) => message.role !== "system")),
        tools: req.tools.map((tool) => ({
          name: tool.name,
          description: tool.description,
          input_schema: tool.inputSchema
        }))
      }),
      signal
    });
    if (!response.ok || !response.body) {
      throw new RpcError(KernelErrorCode.MODEL, `Anthropic HTTP ${response.status}: ${await response.text()}`);
    }
    let toolId = "";
    let toolName = "";
    let toolArgs = "";
    for await (const event of iterateSseJson(response.body)) {
      if (event.type === "content_block_delta" && event.delta?.type === "thinking_delta" && event.delta.thinking) {
        yield { type: "thinking", text: String(event.delta.thinking) };
      }
      if (event.type === "content_block_delta" && event.delta?.type === "text_delta" && event.delta.text) {
        yield { type: "text", text: event.delta.text };
      }
      if (event.type === "content_block_start" && event.content_block?.type === "tool_use") {
        toolId = String(event.content_block.id ?? crypto.randomUUID());
        toolName = String(event.content_block.name ?? "");
        toolArgs = "";
      }
      if (event.type === "content_block_delta" && event.delta?.type === "input_json_delta") {
        toolArgs += String(event.delta.partial_json ?? "");
      }
      if (event.type === "content_block_stop" && toolName) {
        yield { type: "tool_call", id: toolId, name: toolName, arguments: parseArgs(toolArgs) };
        toolName = "";
      }
    }
  }
}

function toAnthropicMessages(messages: ChatMessage[]): unknown[] {
  const out: Array<{ role: "user" | "assistant"; content: unknown }> = [];
  for (const message of messages) {
    if (message.role === "user") {
      out.push({
        role: "user",
        content: message.images?.length
          ? [
              { type: "text", text: message.content },
              ...message.images.map((image) => ({
                type: "image",
                source: { type: "base64", media_type: image.mimeType, data: image.data }
              }))
            ]
          : message.content
      });
      continue;
    }
    if (message.role === "assistant") {
      const content: unknown[] = [];
      if (message.thinking) content.push({ type: "thinking", thinking: message.thinking });
      if (message.content) content.push({ type: "text", text: message.content });
      for (const call of message.toolCalls ?? []) {
        content.push({ type: "tool_use", id: call.id, name: call.name, input: call.arguments });
      }
      out.push({ role: "assistant", content: content.length ? content : message.content });
      continue;
    }
    if (message.role === "tool") {
      out.push({
        role: "user",
        content: [{ type: "tool_result", tool_use_id: message.toolCallId, content: message.content }]
      });
    }
  }
  return out;
}

function parseArgs(raw: string): Record<string, unknown> {
  if (!raw.trim()) return {};
  const value = JSON.parse(raw) as unknown;
  if (typeof value !== "object" || value === null || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

async function* iterateSseJson(body: ReadableStream<Uint8Array>): AsyncGenerator<Record<string, any>> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let sep = buffer.indexOf("\n");
    while (sep >= 0) {
      const line = buffer.slice(0, sep).trim();
      buffer = buffer.slice(sep + 1);
      if (line.startsWith("data:")) {
        const data = line.slice(5).trim();
        if (data && data !== "[DONE]") yield JSON.parse(data) as Record<string, any>;
      }
      sep = buffer.indexOf("\n");
    }
  }
}
