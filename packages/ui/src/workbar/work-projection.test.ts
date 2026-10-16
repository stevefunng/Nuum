import assert from "node:assert/strict";
import test from "node:test";
import { WorkTask, WorkTaskState } from "@nuum/protocol";
import { BOARD_LANES, completedTasks, laneOf, taskLanes, workDeliverables, type TaskView } from "./work-projection";

function task(id: string, state: TaskView["state"], deliverables: TaskView["deliverables"] = []): TaskView {
  return { ...WorkTask.parse({ id, title: `Task ${id}`, description: "", acceptanceCriteria: [], state,
    assigneeIds: [], dependencyIds: [], priority: "normal", revision: 1, deliverables,
    createdAt: 1, updatedAt: 1 }), allowedTransitions: [] };
}

test("board projects only the four active states; proposed folds into ready and finished tasks leave the board", () => {
  const tasks = [task("a", "proposed"), task("b", "ready"), task("c", "in_progress"), task("d", "blocked"), task("e", "review"), task("f", "done"), task("g", "cancelled")];
  const lanes = taskLanes(tasks);
  assert.deepEqual(lanes.map((lane) => lane.state), BOARD_LANES);
  assert.deepEqual(lanes.find((lane) => lane.state === "ready")?.tasks.map((item) => item.id), ["a", "b"]);
  assert.deepEqual(lanes.find((lane) => lane.state === "in_progress")?.tasks.map((item) => item.id), ["c"]);
  assert.deepEqual(lanes.find((lane) => lane.state === "blocked")?.tasks.map((item) => item.id), ["d"]);
  assert.equal(lanes.find((lane) => lane.state === "review")?.tasks[0]?.id, "e");
  assert.equal(lanes.flatMap((lane) => lane.tasks).find((item) => item.id === "f"), undefined);
  assert.equal(laneOf("cancelled"), null);
});

test("only accepted tasks are collected as completed", () => {
  const tasks = [task("a", "review"), task("b", "done"), task("c", "in_progress")];
  assert.deepEqual(completedTasks(tasks).map((item) => item.id), ["b"]);
});

test("outputs include review handoffs, sorted newest first with their source task", () => {
  const draft = { id: "draft", name: "Research draft", uri: "/tmp/research.md", mimeType: "text/markdown", createdAt: 5 };
  const final = { id: "final", name: "Final report", uri: "/tmp/report.pdf", mimeType: "application/pdf", createdAt: 10 };
  const results = workDeliverables([task("a", "review", [draft]), task("b", "done", [final])]);
  assert.deepEqual(results.map(({ file, task }) => [file, task.id]), [[final, "b"], [draft, "a"]]);
});

test("completed tasks without handoff files do not invent outputs", () => {
  assert.deepEqual(workDeliverables([task("a", "done")]), []);
  assert.ok(taskLanes([]).every((lane) => lane.tasks.length === 0));
});
