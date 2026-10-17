import assert from "node:assert/strict";
import { test } from "node:test";
import { nunuActivityState } from "./nunu-state";

test("approval takes priority over execution and stale tool activity cannot animate an idle Nunu", () => {
  assert.equal(nunuActivityState("running", true, true), "waiting");
  assert.equal(nunuActivityState("running", false, true), "working");
  assert.equal(nunuActivityState("running", false, false), "thinking");
  assert.equal(nunuActivityState("idle", false, true), "idle");
  assert.equal(nunuActivityState("error", false, true), "error");
});
