import { useEffect, useRef, useState } from "react";
import { AgentAvatar } from "./agent-avatar";
import { BODY_ASSETS, NUNU_SHAPE_PROFILES, resolveAgentAvatarColor, resolveAgentAvatarShape, resolveAgentAvatarMaterial, resolveNunuPigment } from "./nunu-appearance";
import { createNunuRig, type NunuRig } from "./nunu-rig";
import { sampleUnboxing, UNBOX_DURATION } from "./nunu-unboxing-motion";
import { drawUnboxing } from "./nunu-unboxing-scene";

export function NunuUnboxing({ color, shape, material }: { color: string; shape: string; material: string }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const source = useRef<HTMLCanvasElement>(null);
  const elapsed = useRef(0);
  const [fallback, setFallback] = useState(false);
  useEffect(() => {
    const output = canvas.current!, texture = source.current!;
    const ctx = output.getContext("2d");
    if (!ctx) { setFallback(true); return; }
    const reduced = matchMedia("(prefers-reduced-motion: reduce)");
    let rig: NunuRig | undefined, frame = 0, disposed = false, previous = 0;
    const surface = resolveAgentAvatarMaterial("new-agent", material);
    const ink = resolveAgentAvatarColor("new-agent", color);
    const image = new Image();
    const render = () => {
      if (!rig || disposed || document.hidden) return;
      const time = reduced.matches ? UNBOX_DURATION : elapsed.current;
      rig.draw(sampleUnboxing(time).pose);
      const rect = output.getBoundingClientRect();
      const dpr = Math.max(2, devicePixelRatio);
      const w = Math.round(rect.width * dpr), h = Math.round(rect.height * dpr);
      if (output.width !== w || output.height !== h) { output.width = w; output.height = h; }
      ctx.setTransform(dpr,0,0,dpr,0,0);
      drawUnboxing(ctx, rect.width, rect.height, time, texture);
      output.dataset.complete = String(time >= UNBOX_DURATION);
    };
    const tick = (now: number) => {
      frame = 0;
      if (document.hidden || disposed) return;
      if (previous) elapsed.current = Math.min(UNBOX_DURATION, elapsed.current + now - previous);
      previous = now;
      render();
      if (!reduced.matches && elapsed.current < UNBOX_DURATION) frame = requestAnimationFrame(tick);
    };
    const resume = () => {
      cancelAnimationFrame(frame); frame = 0; previous = 0;
      if (reduced.matches) elapsed.current = UNBOX_DURATION;
      if (!document.hidden && rig) { render(); if (elapsed.current < UNBOX_DURATION) frame = requestAnimationFrame(tick); }
    };
    const resize = new ResizeObserver(() => { rig?.resize(); render(); });
    resize.observe(output);
    const lost = (event: Event) => { event.preventDefault(); cancelAnimationFrame(frame); setFallback(true); };
    texture.addEventListener("webglcontextlost", lost);
    document.addEventListener("visibilitychange", resume);
    reduced.addEventListener("change", resume);
    image.src = BODY_ASSETS[surface === "aurora" ? "glass" : surface];
    void image.decode().then(() => {
      if (disposed) return;
      try {
        rig = createNunuRig(texture, image, NUNU_SHAPE_PROFILES[resolveAgentAvatarShape("new-agent", shape)], resolveNunuPigment(ink.value, surface), surface);
        rig.resize(); setFallback(false); resume();
      } catch { setFallback(true); }
    }).catch(() => { if (!disposed) setFallback(true); });
    return () => {
      disposed = true; cancelAnimationFrame(frame); resize.disconnect(); rig?.dispose();
      texture.removeEventListener("webglcontextlost", lost);
      document.removeEventListener("visibilitychange", resume); reduced.removeEventListener("change", resume);
    };
  }, [color, shape, material]);
  return <div className="sand-nunu-unbox" aria-hidden="true">
    <canvas ref={canvas} className="sand-nunu-unbox__scene" style={{ visibility: fallback ? "hidden" : undefined }} />
    <canvas ref={source} className="sand-nunu-unbox__source" />
    {fallback && <AgentAvatar agentId="new-agent" color={color} shape={shape} material={material} size={190} fullBody />}
  </div>;
}
