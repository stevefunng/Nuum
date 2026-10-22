import type { Tool } from "./types.js";
export const externalTool: Tool = {
  definition: {
    name: "external_operation", mutating: true, action: "run-command",
    description: "Request an authorized operation on the user's computer outside the workspace. Explain its concrete purpose in justification. Prefer read/import/export for files; export/import copy one file, never a directory. shell runs a bounded one-shot command with only the explicitly requested additional readPaths/writePaths; no implicit home access or network. Declare networkTargets when this same operation needs additional network access so the user receives one approval. Never retry a refused operation in the same task. User approval is determined by Host, not by you.",
    inputSchema: { type: "object", properties: {
      operation: { type: "string", enum: ["read", "import", "export", "shell"] },
      justification: { type: "string", description: "Brief natural-language request explaining what you need to do and why, in the user's language." },
      resourceRoot: { type: "string", description: "Optional explicit directory scope for repeated file operations. Approval details must show this directory. Export directory grants only create new files; overwrite is not allowed." },
      source: { type: "string" }, destination: { type: "string" }, overwrite: { type: "boolean", default: false },
      command: { type: "string" }, cwd: { type: "string" },
      networkTargets: { type: "array", items: { type: "string" }, description: "Exact hostname:443 or hostname:80 targets needed by this operation." },
      readPaths: { type: "array", items: { type: "string" } }, writePaths: { type: "array", items: { type: "string" } }
    }, required: ["operation", "justification"], additionalProperties: false }
  },
  execute: async () => { throw new Error("External operations require Host authorization and the execution daemon"); }
};
