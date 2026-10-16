export type ActorRef =
  | { readonly kind: "user"; readonly id: string }
  | { readonly kind: "agent"; readonly id: string };

/**
 * 一次 run 只能属于一个领域。对象在 submit 时冻结给该 run 使用；运行途中
 * Work catalog 或 Proactive policy 的变化只影响下一次 run。
 */
export type RunContext =
  | { readonly kind: "direct" }
  | { readonly kind: "proactive"; readonly proposalId: string; readonly contextRefs: readonly string[] }
  | {
      readonly kind: "work";
      readonly workId: string;
      readonly taskId?: string;
      readonly bridgeId?: string;
      readonly discussionId?: string;
      readonly inputAfterSeq?: number;
      readonly instruction?: string;
      readonly membershipRevision?: number;
      readonly session?: import("./session-store.js").CardSession;
      readonly triggerEventId: string;
      readonly catalogRevision: number;
      readonly catalog: readonly WorkCatalogEntry[];
      readonly requestedBy: ActorRef;
    };

export const DIRECT_RUN_CONTEXT = Object.freeze({ kind: "direct" } as const);

/** 不保留调用方的可变引用，确保运行中的能力边界不会被配置热更新改写。 */
export function freezeRunContext(context: RunContext): RunContext {
  if (context.kind === "direct") return DIRECT_RUN_CONTEXT;
  if (context.kind === "proactive") {
    return Object.freeze({
      kind: "proactive",
      proposalId: context.proposalId,
      contextRefs: Object.freeze([...context.contextRefs])
    });
  }
  return Object.freeze({
    kind: "work",
    workId: context.workId,
    ...(context.taskId ? { taskId: context.taskId } : {}),
    ...(context.session ? { session: Object.freeze({ ...context.session }) } : {}),
    ...(context.inputAfterSeq !== undefined ? { inputAfterSeq: context.inputAfterSeq } : {}),
    ...(context.discussionId ? { discussionId: context.discussionId } : {}),
    ...(context.bridgeId ? { bridgeId: context.bridgeId } : {}),
    ...(context.instruction !== undefined ? { instruction: context.instruction } : {}),
    ...(context.membershipRevision !== undefined ? { membershipRevision: context.membershipRevision } : {}),
    triggerEventId: context.triggerEventId,
    catalogRevision: context.catalogRevision,
    catalog: Object.freeze(context.catalog.map((entry) => Object.freeze(structuredClone(entry)))),
    requestedBy: Object.freeze({ ...context.requestedBy })
  });
}
import type { WorkCatalogEntry } from "@nuum/protocol";
