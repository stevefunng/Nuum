import type { ViewBlock } from "@nuum/protocol";

/** UI-only grouping: transcript events retain their original identities and order. */
export function groupToolActivity(blocks: readonly ViewBlock[]): ViewBlock[] {
  const result: ViewBlock[] = [];
  for (const block of blocks) {
    if (block.type !== "assistant") { result.push(block); continue; }
    if (!block.live && !block.tools.length) continue;
    const previous = result.at(-1);
    if (previous?.type === "assistant") {
      result[result.length - 1] = { ...previous, live: block.live, tools: [...previous.tools, ...block.tools] };
    } else result.push(block);
  }
  return result;
}
