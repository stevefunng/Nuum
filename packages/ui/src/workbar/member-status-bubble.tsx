import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { AgentView, WorkSnapshot } from "@nuum/protocol";
import { t } from "../i18n";
import { memberActivity } from "./member-status";

export function MemberStatusBubble({ agent, snapshot, anchor, shape, onClose }: {
  agent: AgentView; snapshot: WorkSnapshot; anchor: HTMLElement; shape: number; onClose(): void;
}) {
  const bubble = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState({ left: 0, top: 0 });
  useLayoutEffect(() => {
    const place = () => {
      const rect = anchor.getBoundingClientRect();
      const height = bubble.current?.offsetHeight ?? 40;
      const width = bubble.current?.offsetWidth ?? 80;
      setPosition({ left: Math.max(12, rect.left - width - 12), top: Math.max(12, Math.min(window.innerHeight - height - 12, rect.top + rect.height / 2 - height / 2)) });
    };
    place();
    const observer = new ResizeObserver(place);
    if (bubble.current) observer.observe(bubble.current);
    window.addEventListener("resize", place);
    window.addEventListener("scroll", place, true);
    return () => { observer.disconnect(); window.removeEventListener("resize", place); window.removeEventListener("scroll", place, true); };
  }, [anchor, agent, snapshot]);
  useEffect(() => {
    const outside = (event: PointerEvent) => { if (!bubble.current?.contains(event.target as Node) && !anchor.contains(event.target as Node)) onClose(); };
    const escape = (event: KeyboardEvent) => { if (event.key === "Escape") { event.stopPropagation(); onClose(); anchor.focus(); } };
    document.addEventListener("pointerdown", outside);
    document.addEventListener("keydown", escape);
    return () => { document.removeEventListener("pointerdown", outside); document.removeEventListener("keydown", escape); };
  }, [anchor, onClose]);
  const activity = memberActivity(agent, snapshot);
  const preview = activity.kind === "task" ? `${t("Working on card")}${activity.title ? `：${activity.title}` : ""}` : t({ idle: "Idle", error: "Run failed", discussion: "Discussing", elsewhere: "Working in another session" }[activity.kind]);
  return createPortal(<div ref={bubble} className="sand-member-status-bubble" data-shape={shape} data-running={agent.runtime.status === "running" || undefined} style={position} role="status" aria-label={t("Status of {name}", { name: agent.profile.name })}>
    <p>{preview}</p>
  </div>, document.body);
}
