import { NUNU_REST } from "./nunu-animation";

export const UNBOX_DURATION = 1500;
export const CONFETTI_START = 1020;
export const CONFETTI_DURATION = 3600;
export const UNBOX_PLAYBACK_DURATION = CONFETTI_START + CONFETTI_DURATION;

export function sampleUnboxingConfetti(time: number) {
  const elapsed = time - CONFETTI_START;
  return elapsed >= 0 && elapsed < CONFETTI_DURATION ? elapsed : null;
}
export const UNBOX_PACKAGES = ["soft-tray", "paper-fold", "round-box"] as const;
export type UnboxingPackage = typeof UNBOX_PACKAGES[number];
export function rollUnboxingPackage(random = Math.random): UnboxingPackage {
  return UNBOX_PACKAGES[Math.min(2, Math.floor(random() * 3))]!;
}
export function smoothStep(start: number, end: number, time: number) {
  const x = Math.max(0, Math.min(1, (time - start) / (end - start)));
  return x * x * (3 - 2 * x);
}
export function sampleUnboxing(time: number) {
  const t = Math.min(UNBOX_DURATION, Math.max(0, time));
  const greeting = smoothStep(1020, 1140, t) * (1 - smoothStep(1280, 1480, t));
  const approach = smoothStep(1020, 1400, t);
  const leap = approach > 0 && approach < 1 ? Math.sin(Math.PI * approach) : 0;
  return {
    approach,
    jump: .18 * leap,
    packaging: 1 - smoothStep(1080, 1300, t),
    open: smoothStep(120, 680, t),
    untie: smoothStep(40, 240, t),
    reveal: smoothStep(700, 1020, t),
    pose: { ...NUNU_REST, leftArm: .45 * leap, rightArm: -.55 * greeting - .45 * leap,
      leftFoot: .14 * leap, rightFoot: -.14 * leap, head: -.025 * greeting - .025 * leap, smile: .12 * greeting },
  };
}
