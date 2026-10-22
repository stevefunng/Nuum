import { ExternalGrant } from "./permission-rules.js";
import { z } from "zod";
import { LocalToolAction, ModelImage, NetworkTarget } from "./domain.js";

export const ExecutionEndpoint = z.object({ socket: z.string(), instance: z.string(), token: z.string() });
export type ExecutionEndpoint = z.infer<typeof ExecutionEndpoint>;
export const ExecutionOrigin = z.object({
  runId: z.string(), taskKey: z.string().optional(),
  workId: z.string().optional(),
  membershipRevision: z.number().int().optional(),
  catalogRevision: z.number().int().optional(),
  session: z.object({ id: z.string().regex(/^[a-f0-9]{64}$/), workId: z.string(), taskId: z.string(), agentId: z.string(), membershipRevision: z.number().int() }).optional()
});
export type ExecutionOrigin = z.infer<typeof ExecutionOrigin>;
export const ExecutionContext = z.object({
  id: z.string(), agentId: z.string(), workspaceId: z.string(), root: z.string(),
  commands: z.enum(["ask", "always", "never"]), approvedCommands: z.array(z.string()).default([]), network: z.array(NetworkTarget),
  tools: z.array(z.string()).default([]), readOnly: z.array(z.string()).default([]),
  protectedPaths: z.array(z.string()).optional(), refusedOperations: z.array(z.string()).optional(), externalGrants: z.array(ExternalGrant).optional(), writePaths: z.array(z.string()).optional(),
  policy: z.string().optional(), origin: ExecutionOrigin.optional()
});
export type ExecutionContext = z.infer<typeof ExecutionContext>;
export const ExecutionRequest = z.object({
  id: z.string().min(1).max(256), contextId: z.string(), name: z.string(),
  input: z.record(z.unknown())
});
export type ExecutionRequest = z.infer<typeof ExecutionRequest>;
export const ExecutionResult = z.discriminatedUnion("state", [
  z.object({ state: z.literal("running") }),
  z.object({ state: z.literal("approval"), action: LocalToolAction, target: z.string(), justification: z.string().optional(), allowAlways: z.boolean().optional(), details: z.string().optional(), grant: ExternalGrant.optional() }),
  z.object({ state: z.literal("finished"), ok: z.boolean(), output: z.string(), images: z.array(ModelImage).optional() })
]);
export type ExecutionResult = z.infer<typeof ExecutionResult>;
export interface ExecutionRecord { request: ExecutionRequest; origin?: ExecutionOrigin; result: ExecutionResult }
