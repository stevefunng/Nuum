import { NUNU_REST, type NunuPose } from "./nunu-animation";

export const UNBOX_DURATION = 3200;
export function smoothStep(start: number, end: number, time: number) {
  const x = Math.max(0, Math.min(1, (time - start) / (end - start)));
  return x * x * (3 - 2 * x);
}

// A push supplies the initial torque. The shell accelerates under gravity,
// then loses energy at each floor contact. Angles never penetrate the floor.
function shellAngle(time: number) {
  if (time < 260) return .018 * Math.sin(Math.PI * Math.max(0, time) / 260);
  if (time < 640) return .16 * smoothStep(260, 640, time);
  if (time < 1280) {
    const t = (time - 640) / 640;
    return .16 + (Math.PI / 2 - .16) * (t * .24 + t * t * .76);
  }
  const t = (time - 1280) / 1000;
  return Math.PI / 2 - .085 * Math.exp(-10 * t) * Math.abs(Math.sin(24 * t));
}

export function sampleUnboxing(time: number) {
  const push = smoothStep(180, 560, time) * (1 - smoothStep(780, 1240, time));
  const settle = smoothStep(1100, 1500, time);
  const greeting = smoothStep(1520, 1770, time) * (1 - smoothStep(2170, 2490, time));
  const pose: NunuPose = {
    ...NUNU_REST,
    leftArm: .75 * push,
    rightArm: -.75 * push - greeting * (.65 + .16 * Math.sin(time / 90)),
    head: -.035 * greeting,
    bob: 20 * (1 - settle),
    gazeY: -8 * push,
    blink: .9 * smoothStep(1380, 1460, time) * (1 - smoothStep(1460, 1540, time)),
    smile: .15 * greeting,
  };
  return {
    left: shellAngle(time), right: shellAngle(time - 65), pose,
    // All geometry is at rest before the editorial dissolve into the portrait.
    packaging: 1 - smoothStep(2520, 3100, time),
    zoom: .78 + .36 * smoothStep(2470, 3200, time),
  };
}
