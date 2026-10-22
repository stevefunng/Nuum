import assert from "node:assert/strict";
import { test } from "node:test";
import { WorkCatalog, WorkEvent, WorkMembership, WorkProfile, WorkTask } from "./work.js";

test("work schemas keep identity, task state and catalog explicit", () => {
  const profile = WorkProfile.parse({
    id: "work-1",
    name: "Launch",
    description: "Ship the first release",
    projectRoot: "/tmp/launch",
    createdAt: 1
  });
  assert.equal(profile.projectRoot, "/tmp/launch");

  const task = WorkTask.parse({
    id: "task-1",
    title: "Verify package",
    description: "Run release checks",
    acceptanceCriteria: ["all checks pass"],
    state: "review",
    assigneeIds: ["agent-1"],
    dependencyIds: [],
    priority: "normal",
    revision: 3,
    deliverables: [],
    createdAt: 1,
    updatedAt: 2
  });
  assert.equal(task.revision, 3);
  assert.throws(() => WorkTask.parse({ ...task, state: "finished" }));

  const catalog = WorkCatalog.parse({
    revision: 2,
    entries: [
      {
        id: "knowledge-1",
        kind: "knowledge",
        name: "Product docs",
        description: "Local design documents",
        enabled: true,
        roots: ["/tmp/launch/docs"],
        readOnly: true
      }
    ]
  });
  assert.equal(catalog.entries[0]!.kind, "knowledge");
});

test("one membership slot can be attached, detached, and revision checked", () => {
  assert.deepEqual(WorkMembership.parse({ revision: 0, binding: null }), {
    revision: 0,
    binding: null
  });
  const attached = WorkMembership.parse({
    revision: 2,
    binding: {
      workId: "work-1",
      role: "worker",
      joinedAt: 10,
      grants: {
        canPost: true,
        canManageOwnTasks: true,
        canAssignTasks: false,
        canEditCatalog: false
      }
    }
  });
  assert.equal(attached.binding?.workId, "work-1");
  assert.throws(() => WorkMembership.parse({ revision: 2, binding: [attached.binding] }));
});

test("work events carry their own ordered-domain identity", () => {
  const event = WorkEvent.parse({
    type: "chat.posted",
    id: "event-1",
    workId: "work-1",
    seq: 4,
    createdAt: 100,
    actor: { kind: "user", id: "local-user" },
    messageId: "message-1",
    body: "Please review task one",
    mentionedAgentIds: ["agent-1"]
  });
  assert.equal(event.seq, 4);
  assert.equal(event.type, "chat.posted");
});

test("NunuBar creation and update reject removed goal and user-controlled work roots", async () => {
  const { WorkCreateParams, WorkUpdateParams } = await import("./host-contract.js");
  assert.deepEqual(WorkCreateParams.parse({ name: "Team" }), { name: "Team" });
  assert.throws(() => WorkCreateParams.parse({ name: "Team", description: "old goal" }));
  assert.throws(() => WorkUpdateParams.parse({ id: "r", projectRoot: "/" }));
});
