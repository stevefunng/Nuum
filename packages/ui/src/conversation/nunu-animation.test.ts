import assert from "node:assert/strict";
import { test } from "node:test";
import { NUNU_ACTIONS, NUNU_DURATIONS, NUNU_REST, NunuMotionPlayer, sampleNunuPose } from "./nunu-animation";

test("rapid clicks finish the current gesture and coalesce into one pending gesture", () => {
  const player = new NunuMotionPlayer();
  player.request("wave", 0);
  const before = player.sample(400);
  for (let i = 0; i < 50; i++) player.request(i % 2 ? "think" : "cheer", 400);
  assert.deepEqual(player.sample(400), before, "clicks cannot reset the current pose");
  assert.equal(player.sample(NUNU_DURATIONS.wave + 10)?.action, "think");
  assert.equal(player.sample(20_000), null, "burst is bounded, not a long playback queue");
  player.request("sleepy", 20_100);
  assert.equal(player.sample(20_500)?.action, "sleepy", "clicking still works after the burst");
});

test("every joint track is continuous and returns exactly to rest", () => {
  for (const action of NUNU_ACTIONS) {
    const duration = NUNU_DURATIONS[action];
    assert.deepEqual(sampleNunuPose(action, 0), NUNU_REST);
    assert.deepEqual(sampleNunuPose(action, duration), NUNU_REST);
    let previous = sampleNunuPose(action, 0);
    for (let ms = 1; ms <= duration; ms += 1) {
      const next = sampleNunuPose(action, ms);
      for (const key of Object.keys(next) as Array<keyof typeof next>) {
        assert.ok(Number.isFinite(next[key]));
        const limit = key === "gazeX" || key === "gazeY" || key === "bob" ? .4 : .025;
        assert.ok(Math.abs(next[key] - previous[key]) < limit, `${action} ${key} jumps at ${ms}ms`);
      }
      previous = next;
    }
    assert.notDeepEqual(sampleNunuPose(action, duration * .4), NUNU_REST);
  }
});

test("reduced motion or hiding the window clears both active and pending gestures", () => {
  const player = new NunuMotionPlayer();
  player.request("wave", 0);
  player.request("cheer", 100);
  player.reset();
  assert.equal(player.sample(200), null);
  assert.equal(player.sample(4000), null);
  player.request("think", 5000);
  assert.equal(player.sample(5100)?.action, "think");
});


test("gestures respond within 150ms and finish in at most 1.4 seconds", () => {
  assert.ok(Object.values(NUNU_DURATIONS).every(duration => duration >= 800 && duration <= 1400));
  assert.ok(Math.abs(sampleNunuPose("wave", 150).rightArm) > .65);
  assert.ok(sampleNunuPose("cheer", 300).bob < -25, "celebration includes a visible jump");
  assert.ok(sampleNunuPose("think", 250).gazeX < -15);
  assert.ok(sampleNunuPose("think", 850).gazeX > 15, "thinking looks both ways");
});

test("six gestures shuffle without repeats within a round or across its boundary", async () => {
  const { NunuActionBag } = await import("./nunu-animation");
  const bag = new NunuActionBag(() => .42);
  let previous: string | undefined;
  for (let round = 0; round < 10; round++) {
    const actions = Array.from({ length: 6 }, () => bag.next());
    assert.equal(new Set(actions).size, 6);
    assert.notEqual(actions[0], previous);
    previous = actions[5];
  }
});

test("thinking keeps the hand outside the torso instead of folding it inward", () => {
  for (let ms = 0; ms <= NUNU_DURATIONS.think; ms++) {
    assert.ok(sampleNunuPose("think", ms).rightArm <= .3);
  }
});
