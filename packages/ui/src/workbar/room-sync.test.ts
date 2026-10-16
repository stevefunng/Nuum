import assert from "node:assert/strict";
import test from "node:test";
import type { WorkSnapshot } from "@nuum/protocol";
import { RoomSnapshotReplica } from "./room-sync";

function snapshot(id: string, seq: number): WorkSnapshot {
  const events = Array.from({ length: seq }, (_, i) => ({ type: "chat.posted" as const, id: `${id}:${i}`, workId: id, seq: i + 1, createdAt: 100 - i, actor: { kind: "user" as const, id: "user" }, messageId: `m${i}`, body: `message ${i}`, mentionedAgentIds: [] }));
  return { profile: { id, kind: "room", name: id, description: "", projectRoot: null, createdAt: 0 }, throughSeq: seq, discussionRunning: false, interruptions: [], members: [], catalog: { revision: 0, entries: [] }, events, tasks: [], chat: [...events] };
}

test("late snapshots cannot regress a replica; watermarks belong to each room and replica", () => {
  const replica = new RoomSnapshotReplica();
  const latest = snapshot("room", 42);
  assert.equal(replica.apply(latest), latest);
  assert.equal(replica.apply(snapshot("room", 41)), latest);
  assert.equal(replica.appliedThroughSeq("room"), 42);
  assert.equal(replica.apply(snapshot("other", 1)).throughSeq, 1);
  assert.equal(new RoomSnapshotReplica().appliedThroughSeq("room"), 0);
});

test("watermark counts the full event prefix, not visible chat bubbles", () => {
  const replica = new RoomSnapshotReplica();
  const next = snapshot("room", 3);
  next.events[1] = { type: "member.detached", id: "detach", workId: "room", seq: 2, createdAt: 0, actor: { kind: "user", id: "user" }, membershipOperationId: "op", agentId: "a", membershipRevision: 2 };
  next.chat.splice(1, 1);
  replica.apply(next);
  assert.equal(replica.appliedThroughSeq("room"), 3);
  assert.throws(() => replica.apply({ ...snapshot("room", 4), events: next.events }), /prefix/i);
});
