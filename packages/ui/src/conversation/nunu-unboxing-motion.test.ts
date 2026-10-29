import test from "node:test";
import assert from "node:assert/strict";
import { sampleUnboxing, rollUnboxingPackage, UNBOX_DURATION, CONFETTI_START, CONFETTI_DURATION, UNBOX_PLAYBACK_DURATION, sampleUnboxingConfetti } from "./nunu-unboxing-motion";

test("all three packages can be drawn independently", () => {
  assert.deepEqual([0, .4, .9].map(value => rollUnboxingPackage(() => value)), ["soft-tray", "paper-fold", "round-box"]);
});
test("packaging clears before the character emerges, then disappears after the forward hop", () => {
  for (let time = 0; time <= UNBOX_DURATION; time += 16) {
    const state = sampleUnboxing(time);
    if (state.reveal > 0) assert.equal(state.open, 1);
    assert.ok(state.reveal >= 0 && state.reveal <= 1);
  }
  const final = sampleUnboxing(UNBOX_DURATION);
  assert.equal(final.open, 1);
  assert.equal(final.reveal, 1);
  assert.equal(final.pose.bob, 0);
  assert.equal(final.packaging, 0);
  assert.equal(final.approach, 1);
  assert.equal(final.jump, 0);
  assert.deepEqual(final, sampleUnboxing(UNBOX_DURATION + 1000));
});

test("reveal is brisk and the longer falling burst has a finite ending", () => {
  assert.equal(sampleUnboxing(1020).reveal, 1);
  assert.ok(UNBOX_DURATION <= 1500);
  assert.equal(sampleUnboxingConfetti(CONFETTI_START - 1), null);
  assert.equal(sampleUnboxing(CONFETTI_START).reveal, 1);
  assert.equal(sampleUnboxingConfetti(CONFETTI_START), 0);
  assert.equal(CONFETTI_DURATION, 3600);
  assert.equal(sampleUnboxingConfetti(UNBOX_PLAYBACK_DURATION), null);
  assert.equal(sampleUnboxingConfetti(UNBOX_PLAYBACK_DURATION + 1000), null);
});

test("forward hop and quick box exit happen during the falling celebration", () => {
  const hopping = sampleUnboxing(1170);
  assert.ok(hopping.jump > 0);
  assert.ok(hopping.approach > 0 && hopping.approach < 1);
  assert.ok(hopping.packaging > 0 && hopping.packaging < 1);
  assert.notEqual(sampleUnboxingConfetti(1170), null);
  assert.equal(sampleUnboxing(1300).packaging, 0);
  assert.equal(CONFETTI_DURATION, 3600);
  assert.notEqual(sampleUnboxingConfetti(CONFETTI_START + CONFETTI_DURATION - 1), null);
  assert.equal(sampleUnboxingConfetti(CONFETTI_START + CONFETTI_DURATION), null);
});
