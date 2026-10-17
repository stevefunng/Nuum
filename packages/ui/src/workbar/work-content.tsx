import { t, getLanguage } from "../i18n";
import type { AgentView, WorkTaskState } from "@nuum/protocol";
import { useRef, useState } from "react";
import { AgentAvatar } from "../conversation/agent-avatar";
import { SandIcon } from "../kit/sand-kit-primitives";

import { taskLanes, completedTasks, workDeliverables, type TaskView } from "./work-projection";
export const STATE_LABELS: Record<WorkTaskState, string> = {
  proposed: "Proposed", ready: "Ready", in_progress: "In progress", blocked: "Blocked",
  review: "Review", done: "Done", cancelled: "Cancelled"
};

export function TaskLanes({ tasks, agents, onOpen }: {
  tasks: readonly TaskView[]; agents: readonly AgentView[]; onOpen(id: string): void;
}) {
  const board = useRef<HTMLDivElement>(null);
  const lanes = useRef(new Map<WorkTaskState, HTMLElement>());
  const [focusedState, setFocusedState] = useState<WorkTaskState>("ready");
  const groups = taskLanes(tasks);
  const focusState = (state: WorkTaskState) => {
    setFocusedState(state);
    const lane = lanes.current.get(state);
    if (lane && board.current) board.current.scrollTo({
      left: lane.offsetLeft - board.current.offsetLeft - parseFloat(getComputedStyle(board.current).paddingLeft),
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth"
    });
  };
  return <>
    <div className="sand-work-lanes" ref={board} onScroll={() => {
      const viewport = board.current;
      if (!viewport) return;
      const padding = parseFloat(getComputedStyle(viewport).paddingLeft);
      const nearest = [...lanes.current].sort((a, b) =>
        Math.abs(a[1].offsetLeft - padding - viewport.scrollLeft) - Math.abs(b[1].offsetLeft - padding - viewport.scrollLeft))[0];
      if (nearest) setFocusedState(nearest[0]);
    }}>
      {groups.map(({ state, tasks: items }) => {
        return <section className="sand-work-lane" key={state} aria-label={t("{state} tasks", { state: t(STATE_LABELS[state]) })} data-state={state}
          ref={(node) => { if (node) lanes.current.set(state, node); else lanes.current.delete(state); }}>
          <header><span className="sand-work-state-dot" /><span>{t(STATE_LABELS[state])}</span><small>{items.length}</small></header>
          <div className="sand-work-lane__cards">
            {items.map((task) => <button className="sand-work-task-card" key={task.id} type="button" onClick={() => onOpen(task.id)} aria-label={t("Open task: {title}", { title: task.title })}>
              <strong>{task.title}</strong>
              {task.description ? <p>{task.description}</p> : null}
              <span className="sand-work-task-card__footer">
                <span className="sand-work-task-card__avatars">{task.assigneeIds.slice(0, 3).map((id) => {
                  const agent = agents.find((item) => item.profile.id === id);
                  return agent ? <AgentAvatar key={id} agentId={id} color={agent.profile.avatarColor} shape={agent.profile.avatarShape} material={agent.profile.avatarMaterial} size={20} state="idle" /> : null;
                })}</span>
                <span>{task.assigneeIds.length ? task.assigneeIds.map((id) => agents.find((agent) => agent.profile.id === id)?.profile.name ?? t("Agent")).join(", ") : t("Unassigned")}</span>
                {task.deliverables.length ? <small>{t("{count} files", { count: task.deliverables.length })}</small> : null}
              </span>
            </button>)}
            {!items.length ? <span className="sand-work-lane__empty">{t("No tasks")}</span> : null}
          </div>
        </section>;
      })}
    </div>
    <nav className="sand-work-state-picker" aria-label={t("Task states")}>
      <div className="sand-work-state-popover">
        <div className="sand-work-state-nav">
          {groups.map(({ state, tasks: items }) => <button key={state} type="button" data-state={state}
            aria-pressed={focusedState === state} onClick={() => focusState(state)}>
            <span>{t(STATE_LABELS[state])}</span><small>{items.length}</small>
          </button>)}
        </div>
      </div>
      <div className="sand-work-state-dots">
        {groups.map(({ state, tasks: items }) => <button key={state} type="button" data-state={state}
          aria-label={`${t(STATE_LABELS[state])}: ${items.length}`} aria-pressed={focusedState === state}
          onClick={() => focusState(state)}><span /></button>)}
      </div>
    </nav>
  </>;
}

export function WorkDeliverables({ tasks, agents, onOpenTask }: { tasks: readonly TaskView[]; agents: readonly AgentView[]; onOpenTask(id: string): void }) {
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [copyError, setCopyError] = useState("");
  const completed = completedTasks(tasks);
  const files = workDeliverables(completed);
  return <div className="sand-work-deliverables">
    {completed.length === 0 ? <div className="sand-work-deliverables__empty"><SandIcon name="attach" size={22} /><h2>{t("暂无产物")}</h2><p>{t("Agent 团队交付的文件会汇集在这里。")}</p></div> : null}
    {completed.map((task) => <article className="sand-work-deliverable sand-work-deliverable--task" key={task.id}>
      <button className="sand-work-deliverable__task" type="button" onClick={() => onOpenTask(task.id)}>
        <div className="sand-work-deliverable__head">
          <h2>{task.title}</h2>
          <small className="sand-work-deliverable__state" data-state={task.state}>{t(STATE_LABELS[task.state])}</small>
        </div>
        <p className="sand-work-deliverable__uri">{task.assigneeIds.length ? task.assigneeIds.map((id) => agents.find((agent) => agent.profile.id === id)?.profile.name ?? t("Agent")).join(", ") : t("Unassigned")}</p>
      </button>
      {task.deliverables.map((file) => <div className="sand-work-deliverable__file-row" key={file.id}>
        <div className="sand-work-deliverable__file"><SandIcon name="attach" size={18} /><div><h2>{file.name}</h2><small>{file.mimeType ?? t("File")} · {new Date(file.createdAt).toLocaleDateString(getLanguage())}</small></div></div>
        <button type="button" onClick={async () => {
          try { await navigator.clipboard.writeText(file.uri); setCopiedId(file.id); setCopyError(""); }
          catch { setCopyError(t("无法复制，请选择上方路径手动复制。")); }
        }}>{copiedId === file.id ? t("已复制") : t("复制路径")}</button>
      </div>)}
    </article>)}
    {files.length === 0 && completed.length > 0 ? <p className="sand-work-deliverables__note">{t("该任务还没有交付文件。")}</p> : null}
    {copyError ? <p role="alert">{t(copyError)}</p> : null}
  </div>;
}
