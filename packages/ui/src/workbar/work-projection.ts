import { WorkTaskState, type WorkSnapshot } from "@nuum/protocol";

export type TaskView = WorkSnapshot["tasks"][number];
export const TASK_STATES = WorkTaskState.options;

/** 待验收仍是活跃任务；历史 proposed 兼容投影到 ready。 */
export const BOARD_LANES = ["ready", "in_progress", "blocked", "review"] as const;
export type BoardLane = (typeof BOARD_LANES)[number];

export function laneOf(state: TaskView["state"]): BoardLane | null {
  if (state === "proposed") return "ready";
  return BOARD_LANES.includes(state as BoardLane) ? (state as BoardLane) : null;
}

export function taskLanes(tasks: readonly TaskView[]) {
  return BOARD_LANES.map((state) => ({ state, tasks: tasks.filter((task) => laneOf(task.state) === state) }));
}

/** 产物页的完成卡只包含已验收任务。 */
export function completedTasks(tasks: readonly TaskView[]) {
  return tasks.filter((task) => task.state === "done");
}

export function workDeliverables(tasks: readonly TaskView[]) {
  return tasks.flatMap((task) => task.deliverables.map((file) => ({ file, task })))
    .sort((a, b) => b.file.createdAt - a.file.createdAt);
}
