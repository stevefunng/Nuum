export const NUNU_ACTIONS = ["wave", "think", "cheer", "sleepy", "nod", "sway"] as const;
export type NunuAction = (typeof NUNU_ACTIONS)[number];
export const NUNU_DURATIONS: Record<NunuAction, number> = { wave: 900, think: 1250, cheer: 1050, sleepy: 1400, nod: 1100, sway: 1300 };
export const NUNU_REST = { leftArm: 0, rightArm: 0, head: 0, gazeX: 0, gazeY: 0, blink: 0, smile: 0, bob: 0, leftFoot: 0, rightFoot: 0 };
export type NunuPose = typeof NUNU_REST;

function blinkPulse(t: number, center: number, width: number) {
  const distance = Math.abs(t - center) / width;
  return distance >= 1 ? 0 : .94 * Math.cos(distance * Math.PI / 2) ** 2;
}

function smooth(a: number, b: number, t: number) {
  const x = Math.max(0, Math.min(1, (t-a)/(b-a)));
  return x*x*(3-2*x);
}
function track(t: number, keys: Array<[number, number]>) {
  for (let i = 1; i < keys.length; i++) {
    const [end, value] = keys[i]!;
    const [start, previous] = keys[i-1]!;
    if (t <= end) return previous + (value-previous)*smooth(start, end, t);
  }
  return keys[keys.length-1]![1];
}

/** Continuous joint tracks: fast anticipation, readable action, soft landing. */
export function sampleNunuPose(action: NunuAction, elapsed: number): NunuPose {
  const t = elapsed / NUNU_DURATIONS[action];
  if (t <= 0 || t >= 1) return { ...NUNU_REST };
  const envelope = smooth(0, .16, t) * (1-smooth(.78, 1, t));
  const pose = { ...NUNU_REST };
  switch (action) {
    case "wave":
      pose.rightArm = -(1.1 + .4 * Math.sin(t * Math.PI * 6)) * envelope;
      pose.leftArm = .14 * Math.sin(t*Math.PI*6) * envelope;
      pose.head = -.06 * envelope;
      pose.gazeX = 8 * envelope;
      pose.blink = blinkPulse(t, .7, .1);
      break;
    case "think":
      pose.gazeX = track(t, [[0,0],[.18,-25],[.4,-25],[.58,22],[.72,22],[1,0]]);
      pose.gazeY = -12 * envelope;
      pose.head = -pose.gazeX / 280;
      // Inward rotation must stay shallow: the connected mesh cannot overlap the torso.
      pose.rightArm = .28 * envelope;
      pose.leftArm = -.15 * envelope;
      pose.blink = blinkPulse(t, .48, .09);
      break;
    case "cheer": {
      const jump = (start: number, end: number) => t <= start || t >= end ? 0 : Math.sin(Math.PI*(t-start)/(end-start))**2;
      pose.leftArm = 1.8 * envelope;
      pose.rightArm = -1.8 * envelope;
      pose.blink = .6 * envelope;
      pose.smile = .5 * envelope;
      pose.bob = -48*jump(0,.46)-32*jump(.44,.9);
      pose.leftFoot = .25 * envelope;
      pose.rightFoot = -.25 * envelope;
      break;
    }
    case "nod":
      pose.gazeY = 12 * envelope;
      pose.head = .035 * Math.sin(t * Math.PI * 4) * envelope;
      pose.bob = 12 * (1 - Math.cos(t * Math.PI * 4)) * envelope;
      pose.blink = blinkPulse(t, .3, .12) + blinkPulse(t, .7, .12);
      pose.smile = .25 * envelope;
      pose.leftArm = .2 * envelope;
      pose.rightArm = -.2 * envelope;
      break;
    case "sway": {
      const swing = Math.sin(t * Math.PI * 4) * envelope;
      pose.head = .065 * swing;
      pose.gazeX = 14 * swing;
      pose.leftArm = .3 * envelope + .2 * swing;
      pose.rightArm = -.3 * envelope + .2 * swing;
      pose.leftFoot = .08 * swing;
      pose.rightFoot = -.08 * swing;
      pose.smile = .3 * envelope;
      pose.blink = blinkPulse(t, .65, .1);
      break;
    }
    case "sleepy":
      pose.head = track(t, [[0,0],[.16,.05],[.42,-.09],[.62,.09],[.8,.02],[1,0]]);
      pose.gazeY = 9 * envelope;
      pose.blink = .96 * smooth(.08,.26,t) * (1-smooth(.64,.9,t));
      pose.bob = track(t, [[0,0],[.28,24],[.5,6],[.65,18],[1,0]]);
      pose.leftArm = -.4 * envelope;
      pose.rightArm = .4 * envelope;
      break;
  }
  return pose;
}

/** A burst may schedule one follow-up, but never interrupt a moving joint. */
export class NunuMotionPlayer {
  private active: { action: NunuAction; started: number } | null = null;
  private pending: NunuAction | null = null;

  request(action: NunuAction, now: number) {
    this.sample(now);
    if (this.active) this.pending = action;
    else this.active = { action, started: now };
  }

  sample(now: number): { action: NunuAction; pose: NunuPose } | null {
    while (this.active && now - this.active.started >= NUNU_DURATIONS[this.active.action]) {
      const started = this.active.started + NUNU_DURATIONS[this.active.action];
      this.active = this.pending ? { action: this.pending, started } : null;
      this.pending = null;
    }
    return this.active ? { action: this.active.action, pose: sampleNunuPose(this.active.action, now - this.active.started) } : null;
  }

  reset() { this.active = null; this.pending = null; }
}

/** Share one shuffled deck between idle and click gestures. */
export class NunuActionBag {
  private remaining: NunuAction[] = [];
  private previous: NunuAction | undefined;
  constructor(private random: () => number = Math.random) {}

  next(): NunuAction {
    if (!this.remaining.length) {
      this.remaining = [...NUNU_ACTIONS];
      for (let i = this.remaining.length - 1; i > 0; i--) {
        const j = Math.floor(this.random() * (i + 1));
        [this.remaining[i], this.remaining[j]] = [this.remaining[j]!, this.remaining[i]!];
      }
      const last = this.remaining.length - 1;
      if (this.remaining[last] === this.previous) {
        [this.remaining[0], this.remaining[last]] = [this.remaining[last]!, this.remaining[0]!];
      }
    }
    this.previous = this.remaining.pop()!;
    return this.previous;
  }
}
