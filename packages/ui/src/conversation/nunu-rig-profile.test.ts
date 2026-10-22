import assert from "node:assert/strict";
import { test } from "node:test";
import { nunuRigProfile } from "./nunu-rig-profile";

test("glass eyes and their rims stay entirely inside the rigid part of the face patches", () => {
  const profile = nunuRigProfile("glass");
  // Bounds measured on the original texture, including the dark reflective rims.
  for (const [index, bounds] of [[0, [420, 575, 522, 676]], [2, [760, 575, 860, 676]]] as const) {
    const x = profile.eyes[index], y = profile.eyes[index + 1]!;
    assert.ok(bounds[0] >= x - profile.eyeRadius && bounds[2] <= x + profile.eyeRadius);
    assert.ok(bounds[1] >= y - profile.eyeRadius && bounds[3] <= y + profile.eyeRadius);
  }
  assert.deepEqual(nunuRigProfile("aurora"), profile);
});
