import type { AgentAvatarMaterial } from "./nunu-appearance";

// Landmark positions and intact eye radii in the 1254px source textures.
// Glass eyes are larger and farther apart; a plush-sized falloff cuts through them.
const PROFILES = {
  plush: { eyes: [498, 633, 795, 633], eyeRadius: 42, mouth: [642, 674], armScale: .65, footScale: 1 },
  felt: { eyes: [495, 640, 800, 643], eyeRadius: 42, mouth: [640, 680], armScale: .65, footScale: 1 },
  matte: { eyes: [497, 632, 800, 632], eyeRadius: 46, mouth: [644, 674], armScale: .65, footScale: 1 },
  glass: { eyes: [470, 626, 810, 626], eyeRadius: 55, mouth: [640, 665], armScale: .28, footScale: .4 },
} as const;

export function nunuRigProfile(material: AgentAvatarMaterial) {
  return PROFILES[material === "aurora" ? "glass" : material];
}
