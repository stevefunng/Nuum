import { KernelErrorCode, RpcError, type ChatMessage } from "@nuum/protocol";
import type { ModelPort, NormalizedChatRequest, NormalizedChunk } from "./types.js";

export class OpenAIModel implements ModelPort {
  constructor(
    readonly baseUrl = "https://api.openai.com/v1",
    readonly label = "OpenAI"
  ) {}

  async *streamChat(req: NormalizedChatRequest, signal: AbortSignal): AsyncIterable<NormalizedChunk> {
    const response = await fetch(`${this.baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${req.apiKey}`
      },
      body: JSON.stringify({
        model: req.model.model,
        stream: true,
        ...(req.maxOutputTokens ? { max_tokens: req.maxOutputTokens } : {}),
        messages: req.messages.map((message) => toOpenAIMessage(message, this.label !== "DeepSeek")),
        tools: req.tools.map((tool) => ({
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: tool.inputSchema
          }
        }))
      }),
      signal
    });
    if (!response.ok || !response.body) {
      throw new RpcError(KernelErrorCode.MODEL, `${this.label} HTTP ${response.status}: ${await response.text()}`);
    }
    const toolAcc = new Map<number, { id: string; name: string; args: string }>();
    for await (const line of iterateSse(response.body)) {
      if (line === "[DONE]") break;
      const json = JSON.parse(line) as {
        choices?: Array<{
          delta?: {
            content?: string;
            reasoning_content?: string;
            tool_calls?: Array<{ index: number; id?: string; function?: { name?: string; arguments?: string } }>;
          };
        }>;
      };
      const delta = json.choices?.[0]?.delta;
      for (const chunk of textChunksFromDelta(delta)) yield chunk;
      for (const call of delta?.tool_calls ?? []) {
        const current = toolAcc.get(call.index) ?? { id: "", name: "", args: "" };
        if (call.id) current.id = call.id;
        if (call.function?.name) current.name += call.function.name;
        if (call.function?.arguments) current.args += call.function.arguments;
        toolAcc.set(call.index, current);
      }
    }
    for (const call of toolAcc.values()) {
      yield {
        type: "tool_call",
        id: call.id || crypto.randomUUID(),
        name: call.name,
        arguments: parseArgs(call.args)
      };
    }
  }
}

export function textChunksFromDelta(delta?: {
  content?: string;
  reasoning_content?: string;
}): NormalizedChunk[] {
  const out: NormalizedChunk[] = [];
  if (delta?.reasoning_content) out.push({ type: "thinking", text: delta.reasoning_content });
  if (delta?.content) out.push({ type: "text", text: delta.content });
  return out;
}

export function toOpenAIMessage(message: ChatMessage, supportsImages = true): Record<string, unknown> {
  if (message.role === "tool") {
    return { role: "tool", tool_call_id: message.toolCallId, content: message.content };
  }
  if (message.role === "assistant") {
    const encoded: Record<string, unknown> = {
      role: "assistant",
      content: message.content || (message.toolCalls?.length ? null : "")
    };
    if (message.thinking) encoded.reasoning_content = message.thinking;
    if (message.toolCalls?.length) {
      encoded.tool_calls = message.toolCalls.map((call) => ({
        id: call.id,
        type: "function",
        function: { name: call.name, arguments: JSON.stringify(call.arguments) }
      }));
    }
    return encoded;
  }
  if (message.role === "user" && message.images?.length && supportsImages) {
    return {
      role: "user",
      content: [
        { type: "text", text: message.content },
        ...message.images.map((image) => ({
          type: "image_url",
          image_url: { url: `data:${image.mimeType};base64,${image.data}` }
        }))
      ]
    };
  }
  const suffix = message.images?.length && !supportsImages
    ? "\n[Image content omitted because this model provider does not accept image input.]"
    : "";
  return { role: message.role, content: `${message.content}${suffix}` };
}

function parseArgs(raw: string): Record<string, unknown> {
  if (!raw.trim()) return {};
  const value = JSON.parse(raw) as unknown;
  if (typeof value !== "object" || value === null || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

async function* iterateSse(body: ReadableStream<Uint8Array>): AsyncGenerator<string> {
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
      if (line.startsWith("data:")) yield line.slice(5).trim();
      sep = buffer.indexOf("\n");
    }
  }
}
