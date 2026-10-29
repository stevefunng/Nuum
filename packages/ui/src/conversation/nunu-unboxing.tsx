import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { createUnboxingConfetti } from "./nunu-unboxing-confetti";
import { AgentAvatar } from "./agent-avatar";
import { BODY_ASSETS, NUNU_SHAPE_PROFILES, resolveAgentAvatarColor, resolveAgentAvatarShape, resolveAgentAvatarMaterial, resolveNunuPigment } from "./nunu-appearance";
import { NunuActionBag, NunuMotionPlayer } from "./nunu-animation";
import { createNunuRig, type NunuRig } from "./nunu-rig";
import { sampleUnboxing, rollUnboxingPackage, UNBOX_DURATION, UNBOX_PLAYBACK_DURATION } from "./nunu-unboxing-motion";
import { createUnboxingScene, type UnboxingScene } from "./nunu-unboxing-scene";

export function NunuUnboxing({ color, shape, material }: { color: string; shape: string; material: string }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const source = useRef<HTMLCanvasElement>(null);
  const confettiCanvas = useRef<HTMLCanvasElement>(null);
  const elapsed = useRef(0);
  const [packaging] = useState(rollUnboxingPackage);
  const repaint = useRef<(() => void) | null>(null);
  const activeRig = useRef<NunuRig | null>(null);
  const pigment = useRef<number[]>([]);
  pigment.current = resolveNunuPigment(resolveAgentAvatarColor("new-agent", color).value, resolveAgentAvatarMaterial("new-agent", material));
  useEffect(() => { activeRig.current?.setPigment(pigment.current); repaint.current?.(); }, [color]);
  const [fallback, setFallback] = useState(false);
  useEffect(() => {
    const output = canvas.current!, texture = source.current!;
    let scene: UnboxingScene;
    try { scene = createUnboxingScene(output, texture, packaging); }
    catch { setFallback(true); return; }
    const confetti = createUnboxingConfetti(confettiCanvas.current!, output.closest("dialog"));
    const reduced = matchMedia("(prefers-reduced-motion: reduce)");
    let rig: NunuRig | undefined, frame = 0, disposed = false, previous = 0;
    let idleTimer: ReturnType<typeof setTimeout> | undefined;
    let playing = false;
    const player = new NunuMotionPlayer();
    const actions = new NunuActionBag();
    const surface = resolveAgentAvatarMaterial("new-agent", material);
    const image = new Image();
    const render = (force = true) => {
      if (!rig || disposed || document.hidden) return;
      const time = reduced.matches ? UNBOX_PLAYBACK_DURATION : elapsed.current;
      const current = player.sample(performance.now());
      if (force || current || playing || time <= UNBOX_DURATION || output.dataset.complete !== "true") {
        rig.draw(current?.pose ?? sampleUnboxing(time).pose);
        scene.draw(time);
      }
      playing = Boolean(current);
      output.dataset.playing = String(playing);
      if (current) output.dataset.action = current.action;
      confetti.draw(time, reduced.matches);
      output.dataset.complete = String(time >= UNBOX_DURATION);
    };
    repaint.current = () => render();
    const scheduleIdle = () => {
      if (idleTimer !== undefined || playing || disposed || !rig || reduced.matches || document.hidden) return;
      idleTimer = setTimeout(() => {
        idleTimer = undefined;
        if (disposed || reduced.matches || document.hidden) return;
        player.request(actions.next(), performance.now());
        if (!frame) { previous = 0; frame = requestAnimationFrame(tick); }
      }, 2800 + Math.random() * 3200);
    };
    const tick = (now: number) => {
      frame = 0;
      if (document.hidden || disposed) return;
      if (previous) elapsed.current = Math.min(UNBOX_PLAYBACK_DURATION, elapsed.current + now - previous);
      previous = now;
      render(false);
      if (elapsed.current >= UNBOX_DURATION && !playing) scheduleIdle();
      if (!reduced.matches && (elapsed.current < UNBOX_PLAYBACK_DURATION || playing)) frame = requestAnimationFrame(tick);
    };
    const resume = () => {
      clearTimeout(idleTimer); idleTimer = undefined;
      cancelAnimationFrame(frame); frame = 0; previous = 0;
      player.reset(); playing = false;
      if (reduced.matches) elapsed.current = UNBOX_PLAYBACK_DURATION;
      if (!document.hidden && rig) {
        render();
        if (elapsed.current < UNBOX_PLAYBACK_DURATION) frame = requestAnimationFrame(tick);
        else scheduleIdle();
      } else confetti.dispose();
    };
    const resize = new ResizeObserver(() => {
      const rect = output.getBoundingClientRect();
      scene.resize(rect.width, rect.height);
      rig?.resize(); render();
    });
    resize.observe(output);
    const lost = (event: Event) => {
      event.preventDefault(); clearTimeout(idleTimer); cancelAnimationFrame(frame);
      player.reset(); confetti.dispose(); setFallback(true);
    };
    texture.addEventListener("webglcontextlost", lost);
    output.addEventListener("webglcontextlost", lost);
    document.addEventListener("visibilitychange", resume);
    reduced.addEventListener("change", resume);
    image.src = BODY_ASSETS[surface === "aurora" ? "glass" : surface];
    void image.decode().then(() => {
      if (disposed) return;
      try {
        rig = createNunuRig(texture, image, NUNU_SHAPE_PROFILES[resolveAgentAvatarShape("new-agent", shape)], pigment.current, surface);
        activeRig.current = rig;
        rig.resize(); setFallback(false); resume();
      } catch { setFallback(true); }
    }).catch(() => { if (!disposed) setFallback(true); });
    return () => {
      activeRig.current = null; repaint.current = null;
      disposed = true; clearTimeout(idleTimer); player.reset();
      cancelAnimationFrame(frame); resize.disconnect(); rig?.dispose();
      confetti.dispose();
      scene.dispose();
      output.removeEventListener("webglcontextlost", lost);
      texture.removeEventListener("webglcontextlost", lost);
      document.removeEventListener("visibilitychange", resume); reduced.removeEventListener("change", resume);
    };
  }, [shape, material, packaging]);
  return <><div className="sand-nunu-unbox" data-packaging={packaging} aria-hidden="true">
    <canvas ref={canvas} className="sand-nunu-unbox__scene" style={{ visibility: fallback ? "hidden" : undefined }} />
    <canvas ref={source} className="sand-nunu-unbox__source" />
    {fallback && <AgentAvatar agentId="new-agent" color={color} shape={shape} material={material} size={190} fullBody />}
  </div>{createPortal(<canvas ref={confettiCanvas} popover="manual" className="sand-nunu-unbox-confetti" aria-hidden="true" />, document.body)}</>;
}
