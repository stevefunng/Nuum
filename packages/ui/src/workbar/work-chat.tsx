import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { t } from "../i18n";
import type { AgentView, WorkSnapshot } from "@nuum/protocol";
import { useEffect, useRef, useState } from "react";
import { SandIcon } from "../kit/sand-kit-primitives";

export function WorkChatDock({ chat, agents, onPostMessage, expanded = false }: {
  expanded?: boolean;
  chat: WorkSnapshot["chat"]; agents: readonly AgentView[]; onPostMessage(body: string): void;
}) {
  const [opened, setOpen] = useState(false);
  const open = expanded || opened;
  const [message, setMessage] = useState("");
  const root = useRef<HTMLElement>(null);
  const composing = useRef(false);
  const input = useRef<HTMLTextAreaElement>(null);
  const timeline = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (open && timeline.current) timeline.current.scrollTop = timeline.current.scrollHeight;
  }, [open, chat.length]);
  useEffect(() => {
    const outside = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", outside);
    return () => document.removeEventListener("pointerdown", outside);
  }, []);
  const close = () => { setOpen(false); input.current?.blur(); };
  return <section ref={root} className="sand-work-chat-dock" data-open={open || undefined} data-expanded={expanded || undefined} onKeyDown={(event) => {
    if (event.key === "Escape") { event.stopPropagation(); close(); }
  }} onBlur={(event) => {
    if (event.relatedTarget && !event.currentTarget.contains(event.relatedTarget as Node)) setOpen(false);
  }}>
    <div className="sand-work-chat-sheet" id="work-shared-room" aria-hidden={!open} inert={!open}>
      <div className="sand-work-chat-sheet__content">
      <header><span>{t("Shared room")}{" "}<small>{chat.length}</small></span><button className="sand-work-icon-button" aria-label={t("Close shared room")} type="button" onClick={close}><SandIcon name="close" /></button></header>
      <div className="sand-work-chat__timeline" ref={timeline} role="log" aria-label={t("Shared room messages")}>
        {!chat.length ? <p className="sand-work-chat__empty">{t("No messages yet.")}</p> : null}
        {chat.map((event) => event.type === "chat.posted" ? <article className="sand-work-chat__message" data-user={event.actor.kind === "user" || undefined} key={event.id}>
          {event.actor.kind !== "user" ? <span className="sand-work-chat__author">{agents.find((agent) => agent.profile.id === event.actor.id)?.profile.name ?? t("Agent")}</span> : null}
          <div className={`sand-message sand-message--${event.actor.kind === "user" ? "user" : "assistant"}`}><div className="sand-message-prose">{event.actor.kind === "user" ? <p>{event.body}</p> : <ReactMarkdown remarkPlugins={[remarkGfm]}>{event.body}</ReactMarkdown>}</div></div>
        </article> : null)}
      </div>
      </div>
    </div>
    <form className="sand-prompt-form sand-work-chat__composer" onSubmit={(event) => { event.preventDefault(); if (!message.trim()) return; onPostMessage(message.trim()); setMessage(""); if (input.current) input.current.style.height = "auto"; }}>
      <div className="sand-prompt-shell">
        <textarea className="sand-prompt-field" rows={1} ref={input} aria-label={t("Message the Work")} aria-expanded={open} aria-controls="work-shared-room" placeholder={t("Message the Work…")} value={message} onChange={(event) => {
        setMessage(event.target.value);
        event.target.style.height = "auto";
        event.target.style.height = `${Math.min(96, event.target.scrollHeight)}px`;
      }} onCompositionStart={() => { composing.current = true; }} onCompositionEnd={() => { composing.current = false; }} onKeyDown={(event) => {
        if (event.key !== "Enter" || event.shiftKey || composing.current || event.nativeEvent.isComposing || event.nativeEvent.keyCode === 229) return;
        event.preventDefault();
        event.currentTarget.form?.requestSubmit();
      }} onFocus={() => setOpen(true)} />
        <button className="sand-prompt-send" aria-label={t("Post message")} disabled={!message.trim()} type="submit"><SandIcon name="arrow-up" size={16} /></button>
      </div>
    </form>
  </section>;
}
