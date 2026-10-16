import assert from "node:assert/strict";
import { test } from "node:test";
import {
  delegatedToolsForRunContext,
  isDelegatedToolAvailable,
  type DelegatedTool
} from "./delegated-tools.js";

function tool(name: string, runKinds?: DelegatedTool["runKinds"]): DelegatedTool {
  return {
    definition: {
      name,
      description: name,
      inputSchema: { type: "object", properties: {} },
      mutating: false
    },
    ...(runKinds ? { runKinds } : {}),
    execute: async () => "ok"
  };
}

test("existing product tools are direct-only unless they opt into another domain", () => {
  const direct = tool("SendMessage");
  const work = tool("RunWorkCLI", ["work"]);
  const proactive = tool("ProposeAction", ["proactive"]);
  const tools = [direct, work, proactive];

  assert.deepEqual(
    delegatedToolsForRunContext(tools, { kind: "direct" }).map((item) => item.definition.name),
    ["SendMessage"]
  );
  assert.deepEqual(
    delegatedToolsForRunContext(tools, {
      kind: "work",
      workId: "work-1",
      triggerEventId: "event-1",
      catalogRevision: 1,
      catalog: [],
      requestedBy: { kind: "user", id: "user-1" }
    }).map((item) => item.definition.name),
    ["RunWorkCLI"]
  );
  assert.deepEqual(
    delegatedToolsForRunContext(tools, {
      kind: "proactive",
      proposalId: "proposal-1",
      contextRefs: ["context-1"]
    }).map((item) => item.definition.name),
    ["ProposeAction"]
  );
});

test("availability is checked again when a delegated call arrives", () => {
  const privateTool = tool("ReadAgentTranscript");
  assert.equal(isDelegatedToolAvailable(privateTool, { kind: "direct" }), true);
  assert.equal(
    isDelegatedToolAvailable(privateTool, {
      kind: "proactive",
      proposalId: "proposal-1",
      contextRefs: []
    }),
    false
  );
});
