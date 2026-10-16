import type { WorkRole, WorkTaskState } from "@nuum/protocol";

export type TaskActorRole = "user" | WorkRole;

type TransitionRule = {
  to: WorkTaskState;
  roles: readonly TaskActorRole[];
};

/**
 * 状态机的唯一策略表。服务端校验和 UI 可用动作投影都从这里读取；体验调整时
 * 改这张表和对应测试，不在 RPC handler 或组件里堆状态分支。
 */
export const WORK_TASK_TRANSITIONS: Readonly<Record<WorkTaskState, readonly TransitionRule[]>> = {
  proposed: [
    { to: "ready", roles: ["user", "coordinator"] },
    { to: "cancelled", roles: ["user", "coordinator"] }
  ],
  ready: [
    { to: "in_progress", roles: ["user", "coordinator", "worker"] },
    { to: "cancelled", roles: ["user", "coordinator"] }
  ],
  in_progress: [
    { to: "review", roles: ["user", "coordinator", "worker"] },
    { to: "blocked", roles: ["user", "coordinator", "worker"] },
    { to: "cancelled", roles: ["user", "coordinator"] }
  ],
  blocked: [
    { to: "in_progress", roles: ["user"] },
    { to: "ready", roles: ["user"] },
    { to: "cancelled", roles: ["user", "coordinator"] }
  ],
  review: [
    { to: "done", roles: ["user"] },
    { to: "in_progress", roles: ["user", "coordinator"] },
    { to: "cancelled", roles: ["user", "coordinator"] }
  ],
  done: [{ to: "in_progress", roles: ["user", "coordinator"] }],
  cancelled: []
};

export function allowedTaskTransitions(state: WorkTaskState, role: TaskActorRole): WorkTaskState[] {
  return WORK_TASK_TRANSITIONS[state]
    .filter((rule) => rule.roles.includes(role))
    .map((rule) => rule.to);
}

export function assertTaskTransition(
  from: WorkTaskState,
  to: WorkTaskState,
  role: TaskActorRole
): void {
  if (allowedTaskTransitions(from, role).includes(to)) return;
  throw new Error(`Transition ${from} -> ${to} is not allowed for ${role}`);
}
