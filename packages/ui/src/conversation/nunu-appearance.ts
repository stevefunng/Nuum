// Persisted IDs remain compatible with existing profiles; the palette now uses soft pigments.
export const AGENT_AVATAR_COLORS = [
  { id: "cream", chat: "#806444", value: "#f3e8d4", dark: "#c8af8b" },
  { id: "green", chat: "#526c43", value: "#bac8a8", dark: "#7e9270" },
  { id: "orange", chat: "#ad5c30", value: "#f4c2a1", dark: "#ce8e6a" },
  { id: "violet", chat: "#79569d", value: "#d5c6eb", dark: "#a28dbd" },
  { id: "blue", chat: "#39738c", value: "#bedce7", dark: "#7cabbf" },
  { id: "magenta", chat: "#a4526c", value: "#eec3cc", dark: "#bd899b" },
  { id: "honey", chat: "#8c6b22", value: "#efdb9b", dark: "#c1a456" }
] as const;
export const AGENT_AVATAR_SHAPES = ["circle", "blob", "droplet", "cloud", "tablet"] as const;
export type AgentAvatarShape = (typeof AGENT_AVATAR_SHAPES)[number];
export const AGENT_AVATAR_MATERIALS = ["plush", "felt", "matte", "glass"] as const;
export const AGENT_AVATAR_MATERIAL_HIDDEN = "aurora";
export type AgentAvatarMaterial = (typeof AGENT_AVATAR_MATERIALS)[number] | "aurora";
export type AgentAvatarState = "idle" | "thinking" | "working" | "waiting" | "error" | "sending" | "receiving" | "happy" | "wave";

// All five body proportions retain the asymmetric n crest.
export const SHAPES: Record<AgentAvatarShape, string> = {
  blob: "M42 174C32 153 40 112 49 86C54 64 53 26 78 20C105 12 116 31 114 65C138 32 169 43 176 74C182 102 203 143 191 174C179 201 60 203 42 174Z",
  circle: "M34 158C29 131 44 106 54 84C56 53 64 32 84 31C108 28 119 45 118 64C141 40 165 54 173 79C191 100 207 132 199 158C190 207 47 208 34 158Z",
  droplet: "M43 169C38 144 55 108 64 78C65 48 64 18 85 15C110 10 122 34 116 65C139 41 158 53 164 80C173 111 198 147 188 174C174 203 58 204 43 169Z",
  cloud: "M29 167C23 142 36 113 46 99C43 65 62 43 86 49C101 51 109 65 109 77C133 48 159 55 170 83C195 92 211 130 202 162C191 200 45 204 29 167Z",
  tablet: "M32 171C26 150 31 119 38 96C39 61 54 36 80 38C105 37 112 57 111 74C137 43 168 54 178 83C190 109 203 148 195 174C184 194 46 198 32 171Z"
};
function hash(value: string) { let result = 2166136261; for (let i = 0; i < value.length; i++) result = Math.imul(result ^ value.charCodeAt(i), 16777619); return result >>> 0; }
export function resolveAgentAvatarColor(agentId: string, requested?: string | null) {
  if (requested === "black") return { id: "black", chat: "#3b4140", value: "#a7aaa8", dark: "#707873" };
  return AGENT_AVATAR_COLORS.find(color => color.id === requested) ?? AGENT_AVATAR_COLORS[hash(agentId) % AGENT_AVATAR_COLORS.length]!;
}
export function resolveAgentAvatarShape(agentId: string, requested?: string | null): AgentAvatarShape {
  return requested && Object.hasOwn(SHAPES, requested) ? requested as AgentAvatarShape : AGENT_AVATAR_SHAPES[hash(agentId + "shape") % 5]!;
}
export function resolveAgentAvatarMaterial(_agentId: string, requested?: string | null): AgentAvatarMaterial {
  return requested && [...AGENT_AVATAR_MATERIALS, "aurora"].includes(requested) ? requested as AgentAvatarMaterial : "plush";
}
// Shape and surface are independent persisted traits.
export const NUNU_EDITIONS = AGENT_AVATAR_COLORS.flatMap(({ id }) =>
  AGENT_AVATAR_MATERIALS.flatMap(material => AGENT_AVATAR_SHAPES.map(shape => ({ color: id, shape, material })))
);
export const NUNU_SHAPE_PROFILES: Record<AgentAvatarShape, readonly [number, number, number]> = {
  blob: [1, 1, 1], circle: [.96, 1.04, 1], droplet: [.78, .94, 1.02],
  cloud: [1.05, 1.08, .98], tablet: [1.08, .98, .99],
};
export function rollAgentAvatar(): { color: string; shape: string; material: string } {
  return { ...NUNU_EDITIONS[Math.floor(Math.random() * NUNU_EDITIONS.length)]! };
}
export const BODY_ASSETS = {
  plush: new URL("../assets/nunu/plush.png", import.meta.url).href,
  felt: new URL("../assets/nunu/felt.png", import.meta.url).href,
  matte: new URL("../assets/nunu/matte.png", import.meta.url).href,
  glass: new URL("../assets/nunu/glass.png", import.meta.url).href,
};

/** Opal glass takes a light pigment wash; multiplying full pigment into its
 * shadows makes warm variants look like dark amber instead of luminous glass. */
export function resolveNunuPigment(color: string, material: AgentAvatarMaterial): number[] {
  if (color === "#f3e8d4") return [1, 1, 1];
  const strength = material === "glass" || material === "aurora" ? .38 : 1;
  return [1, 3, 5].map(start => 1 + (parseInt(color.slice(start, start + 2), 16)/255 - 1)*strength);
}
