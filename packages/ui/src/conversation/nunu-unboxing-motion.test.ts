import test from "node:test";
import assert from "node:assert/strict";
import { sampleUnboxing, UNBOX_DURATION } from "./nunu-unboxing-motion";

test("shells clear the character before it stands and never penetrate the floor", () => {
  for (let time = 0; time <= UNBOX_DURATION; time += 8) {
    const state = sampleUnboxing(time);
    assert.ok(state.left >= 0 && state.left <= Math.PI / 2);
    assert.ok(state.right >= 0 && state.right <= Math.PI / 2);
    if (state.pose.bob < 20) assert.ok(state.right > .5);
    if (state.packaging < 1) assert.ok(state.left > 1.57 && state.right > 1.57);
  }
});
test("final preview is stationary with no leftover motion", () => {
  const final = sampleUnboxing(UNBOX_DURATION);
  assert.equal(final.packaging, 0);
  assert.equal(final.pose.bob, 0);
  assert.ok(Math.abs(final.pose.rightArm) === 0);
  assert.equal(final.zoom, 1.14);
});
