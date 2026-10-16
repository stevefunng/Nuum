import type { SummarizeRunParams, SummarizeRunResult } from "@nuum/protocol";
import { selectModel } from "./model/router.js";

/**
 * 一次无工具的单发模型调用（`summarize.run`，§3.2）。压缩与记忆抽取都要调
 * 模型，Kernel 是唯一持有 model port 的地方，所以它们从这里过。
 *
 * 不发事件、不落盘、不进 `runs`：调用方拿到的就是一段文本。
 */
export async function runSummarize(
  params: SummarizeRunParams,
  deps: { selectModel: typeof selectModel; signal?: AbortSignal } = { selectModel }
): Promise<SummarizeRunResult> {
  const { port, apiKey } = deps.selectModel(params.model, params.secrets);
  const messages = [
    { id: "system", role: "system" as const, content: params.systemPrompt, seq: 0, createdAt: 0 },
    ...params.messages
  ];
  let text = "";
  const timeout = AbortSignal.timeout(params.timeoutMs ?? 60_000);
  const signal = deps.signal ? AbortSignal.any([deps.signal, timeout]) : timeout;
  for await (const chunk of port.streamChat({ model: params.model, messages, tools: [], apiKey, maxOutputTokens: params.maxOutputTokens ?? 2048 }, signal)) {
    // thinking 不进结果：调用方要的是摘要本身，不是它怎么想出来的。
    if (chunk.type === "text") text += chunk.text;
  }
  return { text: text.trim() };
}
