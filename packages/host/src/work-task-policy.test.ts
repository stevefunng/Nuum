import assert from "node:assert/strict";
import { test } from "node:test";
import { allowedTaskTransitions, assertTaskTransition } from "./work-task-policy.js";

test("only a human can resume a blocked card", () => {
  assert.deepEqual(allowedTaskTransitions("blocked", "worker"), []);
  assert.deepEqual(allowedTaskTransitions("blocked", "coordinator"), ["cancelled"]);
  assert.deepEqual(allowedTaskTransitions("blocked", "user"), ["in_progress", "ready", "cancelled"]);
});

test("only a human can accept the final delivery", () => {
  assert.throws(
    () => assertTaskTransition("review", "done", "worker"),
    /not allowed/i
  );
  assert.throws(() => assertTaskTransition("review", "done", "coordinator"), /not allowed/i);
  assert.doesNotThrow(() => assertTaskTransition("review", "done", "user"));
});

test("transition rules are exposed through one policy instead of UI conditionals", () => {
  assert.deepEqual(allowedTaskTransitions("review", "user"), ["done", "in_progress", "cancelled"]);
  assert.deepEqual(allowedTaskTransitions("done", "user"), ["in_progress"]);
});
