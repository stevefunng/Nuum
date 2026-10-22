import { useEffect, useRef, useState } from "react";
import { BODY_ASSETS, NUNU_SHAPE_PROFILES, resolveAgentAvatarColor, resolveAgentAvatarShape, resolveAgentAvatarMaterial, resolveNunuPigment } from "./nunu-appearance";
import { NunuActionBag, NUNU_REST, NunuMotionPlayer, type NunuAction } from "./nunu-animation";
import { createNunuRig, type NunuRig } from "./nunu-rig";

export function NunuPortrait({ agentId, color, shape, material, reaction }: { agentId: string; color?: string | null; shape?: string | null; material?: string | null; reaction: number }) {
  const ink = resolveAgentAvatarColor(agentId, color);
  const bodyShape = resolveAgentAvatarShape(agentId, shape);
  const surface = resolveAgentAvatarMaterial(agentId, material);
  const source = BODY_ASSETS[surface === "aurora" ? "glass" : surface];
  const canvas = useRef<HTMLCanvasElement>(null);
  const request = useRef<() => void>(() => {});
  const [ready, setReady] = useState(false);
  useEffect(() => {
    const element = canvas.current;
    if (!element) return;
    setReady(false);
    const player = new NunuMotionPlayer();
    const actions = new NunuActionBag();
    let idleTimer: ReturnType<typeof setTimeout> | undefined;
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    let rig: NunuRig | null = null;
    let pendingStart: NunuAction | null = null;
    let frame = 0;
    let disposed = false;
    const scheduleIdle = () => {
      clearTimeout(idleTimer);
      if (disposed || !rig || query.matches || document.hidden) return;
      idleTimer = setTimeout(() => request.current(), 2800 + Math.random() * 3200);
    };
    const draw = (now: number) => {
      frame = 0;
      if (!rig) return;
      const current = player.sample(now);
      rig.draw(current?.pose ?? NUNU_REST);
      const playing = String(Boolean(current));
      if (element.dataset.playing !== playing) element.dataset.playing = playing;
      if (current) {
        if (element.dataset.action !== current.action) element.dataset.action = current.action;
        frame = requestAnimationFrame(draw);
      } else scheduleIdle();
    };
    const stop = () => {
      clearTimeout(idleTimer);
      cancelAnimationFrame(frame);
      frame = 0;
      pendingStart = null;
      player.reset();
      rig?.draw(NUNU_REST);
      element.dataset.playing = "false";
    };
    request.current = () => {
      if (query.matches || document.hidden) return;
      clearTimeout(idleTimer);
      const action = actions.next();
      if (!rig) { pendingStart = action; return; }
      player.request(action, performance.now());
      if (!frame) frame = requestAnimationFrame(draw);
    };
    const image = new Image();
    image.src = source;
    const setup = () => {
      if (disposed) return;
      try {
        rig = createNunuRig(element, image, NUNU_SHAPE_PROFILES[bodyShape], resolveNunuPigment(ink.value, surface), surface);
        rig.resize();
        rig.draw(NUNU_REST);
        setReady(true);
        if (pendingStart) {
          player.request(pendingStart, performance.now());
          pendingStart = null;
          frame = requestAnimationFrame(draw);
        } else scheduleIdle();
      } catch {
        // Keep the full-resolution still visible if graphics acceleration fails.
        rig?.dispose();
        rig = null;
        setReady(false);
      }
    };
    void image.decode().then(setup).catch(() => {});
    const resize = new ResizeObserver(() => {
      rig?.resize();
      rig?.draw(player.sample(performance.now())?.pose ?? NUNU_REST);
    });
    resize.observe(element);
    const reduced = () => { if (query.matches) stop(); else scheduleIdle(); };
    const visibility = () => { if (document.hidden) stop(); else scheduleIdle(); };
    const lost = (event: Event) => { event.preventDefault(); stop(); rig = null; setReady(false); };
    element.addEventListener("webglcontextlost", lost);
    element.addEventListener("webglcontextrestored", setup);
    query.addEventListener("change", reduced);
    document.addEventListener("visibilitychange", visibility);
    return () => {
      disposed = true;
      stop();
      request.current = () => {};
      resize.disconnect();
      rig?.dispose();
      element.removeEventListener("webglcontextlost", lost);
      element.removeEventListener("webglcontextrestored", setup);
      query.removeEventListener("change", reduced);
      document.removeEventListener("visibilitychange", visibility);
    };
  }, [agentId, source, bodyShape, ink.value, surface]);
  useEffect(() => {
    if (reaction) request.current();
  }, [reaction]);
  return <span className="nunu-portrait" aria-hidden="true" data-ready={ready} data-material={surface} data-shape={bodyShape}>
    <span className="nunu-portrait__media">
      <img src={source} width="1254" height="1254" alt="" draggable={false} />
      <canvas ref={canvas} data-playing="false" />
    </span>
  </span>;
}
