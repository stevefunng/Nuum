import type { Tool } from "./types.js";
export const networkTool: Tool = {
  definition: {
    name: "request_network", description: "Ask the user for tool network access to an exact hostname on port 443 or 80 in the current workspace. This does not execute a command. Never assume a failed network operation granted access.",
    mutating: false, action: "network",
    inputSchema: { type: "object", properties: { justification: { type: "string", description: "Explain the purpose of this network access in the user’s language." }, target: { type: "string", description: "Exact hostname:port, e.g. registry.npmjs.org:443" } }, required: ["target", "justification"], additionalProperties: false }
  },
  execute: async () => { throw new Error("Network authorization requires the execution daemon and Host approval"); }
};
