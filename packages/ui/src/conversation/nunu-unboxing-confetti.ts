import { sampleUnboxingConfetti } from "./nunu-unboxing-motion";

const COLORS = ["#c3a066", "#8eaf94", "#dfa579", "#ac95cd", "#7eaec4", "#d58da3"];

/** Analytic flight with air resistance: an impulse spreads first, then gravity wins. */
export function sampleConfettiFlight(vx: number, vy: number, seconds: number) {
  const horizontalDrag = 3.6, verticalDrag = 1.8, gravity = 240;
  const horizontalTravel = (1 - Math.exp(-horizontalDrag * seconds)) / horizontalDrag;
  const verticalTravel = (1 - Math.exp(-verticalDrag * seconds)) / verticalDrag;
  const terminalSpeed = gravity / verticalDrag;
  return { x: vx * horizontalTravel, y: (vy - terminalSpeed) * verticalTravel + terminalSpeed * seconds };
}

/** The top-layer surface covers the widget; its rounded border bounds every particle. */
export function createUnboxingConfetti(canvas: HTMLCanvasElement, widget: HTMLDialogElement | null) {
  const ctx = canvas.getContext("2d");
  let showing = false;
  let width = 0, height = 0;
  const rightWeight = .35 + Math.random() * .3;
  const particles = Array.from({ length: 128 }, (_, index) => {
    const right = index < 2 ? index === 1 : Math.random() < rightWeight;
    const start = right ? 1 : 0;
    // Distribute landing columns over the full widget rather than choosing a
    // narrow speed range that brings both bursts to rest near the center.
    const target = .025 + (index + Math.random()) / 128 * .95;
    const streamer = Math.random() < .23;
    return {
      x: start, vx: (target - start) * 440 * 3.6,
      vy: -35 + Math.random() ** 1.5 * 400,
      delay: Math.random() * 90, fadeOffset: Math.random() * 24,
      angle: Math.random() * Math.PI, spin: (Math.random() - .5) * 16,
      width: 3 + Math.random() * 3, length: streamer ? 28 + Math.random() * 20 : 8 + Math.random() * 12,
      color: COLORS[Math.floor(Math.random() * COLORS.length)]!, streamer,
    };
  });
  const hide = () => {
    if (!showing) return;
    ctx?.clearRect(0, 0, width, height);
    canvas.hidePopover();
    showing = false;
  };
  return {
    draw(time: number, reduced: boolean) {
      const elapsed = reduced ? null : sampleUnboxingConfetti(time);
      if (!ctx || !widget || elapsed === null) { hide(); return; }
      if (!showing) { canvas.showPopover(); showing = true; }
      width = window.innerWidth; height = window.innerHeight;
      const dpr = Math.max(2, devicePixelRatio);
      if (canvas.width !== Math.round(width * dpr) || canvas.height !== Math.round(height * dpr)) {
        canvas.width = Math.round(width * dpr); canvas.height = Math.round(height * dpr);
      }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, height);
      const rect = widget.getBoundingClientRect();
      const stage = widget.querySelector(".sand-nunu-unbox")?.getBoundingClientRect();
      const bodyBottom = stage ? stage.top + stage.height * .83 : rect.top + rect.height * .72;
      ctx.save();
      ctx.beginPath();
      ctx.roundRect(rect.left + 1, rect.top + 1, rect.width - 2, rect.height - 2, 15);
      ctx.clip();
      for (const piece of particles) {
        const age = elapsed - piece.delay;
        if (age < 0) continue;
        const t = age / 1000;
        const flight = sampleConfettiFlight(piece.vx * rect.width / 440, piece.vy, t);
        const flutter = (1 - Math.exp(-3 * t)) * Math.sin(t * 7 + piece.angle) * 6;
        const x = rect.left + 10 + (rect.width - 20) * piece.x + flight.x + flutter;
        const fadeStart = bodyBottom + piece.fadeOffset;
        const fadeEnd = Math.min(rect.bottom - 12, fadeStart + 72);
        const fallScale = (fadeEnd - rect.top - 12) / 350;
        const y = rect.top + 12 + flight.y * fallScale;
        const opacity = Math.min(1, Math.max(0, (fadeEnd - y) / Math.max(1, fadeEnd - fadeStart)));
        if (opacity === 0) continue;
        const tumble = piece.spin * (1 - Math.exp(-4 * t)) / 4 + Math.sin(t * 4 + piece.angle) * .7;
        ctx.save();
        ctx.translate(x, y); ctx.rotate(piece.angle + tumble);
        ctx.scale(.35 + .65 * Math.abs(Math.cos(t * 13 + piece.angle)), 1);
        ctx.globalAlpha = opacity;
        ctx.fillStyle = ctx.strokeStyle = piece.color;
        if (piece.streamer) {
          ctx.lineWidth = piece.width; ctx.lineCap = "round";
          ctx.beginPath(); ctx.moveTo(0, -piece.length / 2);
          const curl = Math.sin(t * 18 + piece.angle) * 9;
          ctx.bezierCurveTo(curl, -piece.length / 6, -curl, piece.length / 6, 0, piece.length / 2);
          ctx.stroke();
        } else {
          ctx.fillRect(-piece.width / 2, -piece.length / 2, piece.width, piece.length);
        }
        ctx.restore();
      }
      ctx.restore();
    },
    dispose: hide,
  };
}
