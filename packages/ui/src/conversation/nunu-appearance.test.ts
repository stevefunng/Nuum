import assert from "node:assert/strict";
import { test } from "node:test";
import { NUNU_EDITIONS, AGENT_AVATAR_SHAPES, AGENT_AVATAR_MATERIALS, AGENT_AVATAR_COLORS, resolveNunuPigment } from "./nunu-appearance";
test("every material can be created with every body shape", () => {
  for (const material of AGENT_AVATAR_MATERIALS) for (const shape of AGENT_AVATAR_SHAPES) {
    assert.ok(NUNU_EDITIONS.some(edition => edition.material === material && edition.shape === shape), `${material}/${shape} unavailable`);
  }
});

test("body variants preserve upright height instead of vertically flattening the mascot", async () => {
  const { NUNU_SHAPE_PROFILES } = await import("./nunu-appearance");
  for (const [shape, profile] of Object.entries(NUNU_SHAPE_PROFILES)) {
    assert.ok(profile[2] >= .98 && profile[2] <= 1.02, `${shape} compresses the body height`);
  }
});

test("glass pigments stay luminous across the palette, including warm honey", () => {
  for (const color of AGENT_AVATAR_COLORS) {
    const pigment = resolveNunuPigment(color.value, "glass");
    assert.ok(pigment.every(channel => channel >= .85 && channel <= 1));
  }
  assert.deepEqual(resolveNunuPigment("#f3e8d4", "glass"), [1, 1, 1]);
});
