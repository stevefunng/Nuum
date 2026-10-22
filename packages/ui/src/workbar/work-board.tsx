import { ExecutionApproval } from "../conversation/execution-approval";
import type { LocalToolAction, ToolResolution } from "@nuum/protocol";
import { t } from "../i18n";
import type {
  AgentView,
  WorkCatalogAddParams,
  WorkSnapshot,
  WorkTaskState,
  TranscriptEvent
} from "@nuum/protocol";
import { useEffect, useRef, useState, type CSSProperties } from "react";
import { AutoTextarea } from "../kit/auto-textarea";
import { WorkResizeHandle } from "./work-resize";
import { inspectorBounds, projectInspectorLayout, readInspectorPreference, writeInspectorPreference, workDisplayTitle } from "./work-layout";
import { TaskLanes, WorkDeliverables, STATE_LABELS } from "./work-content";
import { MemberStatusBubble } from "./member-status-bubble";
import { WorkChatDock } from "./work-chat";
import { useAgentDrag } from "./agent-drag";
import { SandIcon } from "../kit/sand-kit-primitives";
import { WorkCapabilityDialog, WorkDialog } from "./work-dialog";
import { AgentAvatar } from "../conversation/agent-avatar";

export function WorkCreation({
  canCancel,
  onCancel,
  onCreate
}: {
  canCancel: boolean;
  onCancel(): void;
  onCreate(input: { name: string; kind: "room" | "work" }): void;
}) {
  const [kind, setKind] = useState<"room" | "work">("work");
  const [name, setName] = useState("");
  return (
    <section className="sand-work-create">
      <div className="sand-work-create__card">
        <span className="sand-work-create__eyebrow">{t("A place for the job, not another chat")}</span>
        <h1>{t("Create a Work")}</h1>
        <p>{t("Keep tasks, shared discussion, Agents, capabilities, and deliverables together.")}</p>
        <div className="sand-work-kind-picker">
          <button type="button" aria-pressed={kind === "room"} onClick={() => setKind("room")}>{t("Local room")}</button>
          <button type="button" aria-pressed={kind === "work"} onClick={() => setKind("work")}>NunuBar</button>
        </div>
        <label>
          <span>{t("Name")}</span>
          <input autoFocus onChange={(event) => setName(event.target.value)} placeholder={t("e.g. Product launch")} value={name} />
        </label>
        <div className="sand-work-create__actions">
          {canCancel ? <button onClick={onCancel} type="button">{t("Cancel")}</button> : null}
          <button disabled={!name.trim()} onClick={() => onCreate({ name: name.trim(), kind })} type="button">{t("Create Work")}</button>
        </div>
      </div>
    </section>
  );
}

export interface WorkBoardProps {
  approvals?: { agentId: string; agentName: string; toolCallId: string; action: LocalToolAction; justification?: string; allowAlways?: boolean; details?: string; target: string }[];
  onApproveTool?(agentId: string, resolution: ToolResolution): Promise<void>;
  snapshot: WorkSnapshot;
  agents: readonly AgentView[];
  onPostMessage(body: string): void;
  onContinue(eventId: string, inputAfterSeq?: number): void;
  onStopDiscussion(): void;
  onUpdateWork(patch: { kind: "work" }): void;
  onCreateTask(input: { title: string; assigneeIds: string[] }): void;
  onTransitionTask(taskId: string, to: WorkTaskState, expectedRevision: number, blockerReason?: string): void;
  onReadTaskTrace?(taskId: string, sessionId?: string, beforeSeq?: number): Promise<{ sessions: { id: string; agentId: string }[]; sessionId?: string; entries: TranscriptEvent[]; beforeSeq?: number }>;
  onDispatchTask(agentId: string, taskId: string, instruction: string): void;
  onDetachAgent(agentId: string, expectedRevision: number): void;
  onMoveAgentToWork(agentId: string, workId: string): void;
  onPickDirectory(): Promise<string | null>;
  onAddCatalogEntry(entry: WorkCatalogAddParams["entry"]): Promise<boolean>;
  onRemoveCatalogEntry(entryId: string): void;
}

export function WorkBoard({
  approvals = [], onApproveTool,
  snapshot,
  agents,
  onPostMessage,
  onContinue,
  onStopDiscussion,
  onUpdateWork,
  onCreateTask,
  onTransitionTask,
  onDispatchTask,
  onReadTaskTrace,
  onDetachAgent,
  onMoveAgentToWork,
  onPickDirectory,
  onAddCatalogEntry,
  onRemoveCatalogEntry
}: WorkBoardProps) {
  const [statusAnchor, setStatusAnchor] = useState<{ id: string; element: HTMLElement; shape: number } | null>(null);
  const statusShape = useRef(0);
  useEffect(() => setStatusAnchor(null), [snapshot.profile.id]);
  const statusAgent = statusAnchor && snapshot.members.some(member => member.profile.id === statusAnchor.id) ? agents.find(agent => agent.profile.id === statusAnchor.id) : undefined;
  const [recentHistoryCount, setRecentHistoryCount] = useState(24);
  const mainRef = useRef<HTMLDivElement>(null);
  const [mainSize, setMainSize] = useState({ width: 960, height: 620 });
  const [inspectorPreference, setInspectorPreference] = useState(readInspectorPreference);
  useEffect(() => {
    const element = mainRef.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => setMainSize({ width: entry.contentRect.width, height: entry.contentRect.height }));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  useEffect(() => writeInspectorPreference(inspectorPreference), [inspectorPreference]);
  const inspector = projectInspectorLayout(inspectorPreference, mainSize.width, mainSize.height);
  const bounds = inspectorBounds(mainSize.width, mainSize.height);
  const [dispatchWorkerId, setDispatchWorkerId] = useState("");
  const [trace, setTrace] = useState<Awaited<ReturnType<NonNullable<WorkBoardProps["onReadTaskTrace"]>>> | null>(null);
  const [traceError, setTraceError] = useState("");
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);
  const [page, setPage] = useState<"tasks" | "deliverables">("tasks");
  const [dispatchInstruction, setDispatchInstruction] = useState("");
  const [dialog, setDialog] = useState<"capabilities" | null>(null);
  const selectedTask = snapshot.tasks.find((task) => task.id === selectedTaskId) ?? null;
  const memberDrag = useAgentDrag(({ agentId, workId }) => {
    if (workId) { if (workId !== snapshot.profile.id) onMoveAgentToWork(agentId, workId); return; }
    const member = snapshot.members.find((agent) => agent.profile.id === agentId);
    if (member) onDetachAgent(agentId, member.settings.workMembership?.revision ?? 0);
  });


  return (
    <section className="sand-work-board">
      <header className="sand-work-board__header">
        <div>
          <h1>{workDisplayTitle(snapshot.profile.name)}</h1>
        </div>
        <div className="sand-work-board__summary">
          {snapshot.discussionRunning ? <button type="button" onClick={onStopDiscussion}>{t("Stop discussion")}</button> : null}
          {snapshot.tasks.some((task) => task.state === "blocked") ? <span>{snapshot.tasks.filter((task) => task.state === "blocked").length} {t("Blocked")}</span> : null}
        </div>
      </header>
      {onApproveTool && approvals.length ? <div className="sand-work-approvals">{approvals.map(approval => <ExecutionApproval key={`${approval.agentId}:${approval.toolCallId}`} action={approval.action} justification={approval.justification} allowAlways={approval.allowAlways} details={approval.details} target={approval.target} agentName={approval.agentName} onDecide={resolution => onApproveTool(approval.agentId, resolution)} />)}</div> : null}
      <div className="sand-work-board__main" ref={mainRef} style={{ "--work-inspector-width": `${inspector.width}px`, "--work-capability-height": `${inspector.capabilityHeight}px` } as CSSProperties}>
        <div className="sand-work-board__center">
          {snapshot.profile.kind === "room" ? <div className="sand-work-page-heading">
            <strong>{t("Local room")}</strong>
            <button type="button" onClick={() => onUpdateWork({ kind: "work" })}>{t("Enable task board")}</button>
          </div> : <>
          <div className="sand-work-page-heading">
            <button className="sand-work-page-switch" type="button" title={page === "tasks" ? t("切换到产物") : t("切换到 Tasks")} aria-label={page === "tasks" ? t("切换到产物") : t("切换到 Tasks")}
              onClick={() => setPage(page === "tasks" ? "deliverables" : "tasks")}>
              <strong>{page === "tasks" ? t("Tasks") : t("产物")}</strong>
              <span aria-hidden="true">/</span>
              <small>{page === "tasks" ? t("产物") : t("Tasks")}</small>
            </button>
          </div>
          <div className="sand-work-pages" data-page={page}>
            <div className="sand-work-pages__rotor">
              <section className="sand-work-page sand-work-page--tasks" aria-label={t("Tasks")} inert={page !== "tasks"} aria-hidden={page !== "tasks"}>
                <TaskLanes tasks={snapshot.tasks} agents={agents} onOpen={(id) => { setSelectedTaskId(id); setDispatchInstruction(""); setTrace(null); setTraceError(""); }} />
              </section>
              <section className="sand-work-page sand-work-page--deliverables" aria-label={t("产物")} inert={page !== "deliverables"} aria-hidden={page !== "deliverables"}>
                <WorkDeliverables tasks={snapshot.tasks} agents={agents} onOpenTask={setSelectedTaskId} />
              </section>
            </div>
          </div>
          </>}
          {snapshot.interruptions.length ? <div className="sand-work-notices" role="status">
      {snapshot.interruptions.map(item => <div className="sand-work-notice" key={item.eventId}>
        <span>{item.agentId ? `${snapshot.members.find(member => member.profile.id === item.agentId)?.profile.name ?? item.agentId}: ` : ""}{t(item.error)}</span>
        <button type="button" onClick={() => onContinue(item.eventId)}>{t("Continue")}</button>
        {!item.taskId ? <details>
          <summary>{t("Use less room history")}</summary>
          <label>{t("Only include the most recent messages")}
            <input type="number" min={1} max={Math.max(1, snapshot.chat.length)} value={recentHistoryCount} onChange={event => setRecentHistoryCount(Math.max(1, Number(event.target.value) || 1))} />
          </label>
          <button type="button" onClick={() => onContinue(item.eventId, Math.max(0, (snapshot.chat.slice(-recentHistoryCount)[0]?.seq ?? 1) - 1))}>{t("Continue with this history")}</button>
        </details> : null}
      </div>)}
          </div> : null}
          <WorkChatDock expanded={snapshot.profile.kind === "room"} chat={snapshot.chat} agents={agents} onPostMessage={onPostMessage} />
        </div>

        <aside className="sand-work-inspector">
          <WorkResizeHandle axis="horizontal" label={t("Resize Work inspector")} value={inspector.width} min={bounds.minWidth} max={bounds.maxWidth}
            onChange={(width) => setInspectorPreference((current) => ({ ...current, width }))} />
          <section className="sand-work-inspector__capabilities">
            <div className="sand-work-section-heading"><div><span>{t("Capabilities")}</span><small>{snapshot.catalog.entries.length}</small></div><button className="sand-work-icon-button" aria-label={t("Add capability")} onClick={() => setDialog("capabilities")} type="button"><SandIcon name="plus" size={12} /></button></div>
            <div className="sand-work-capability-list">
              {snapshot.catalog.entries.map((entry) => <div className="sand-work-capability-item" key={entry.id}><div><strong>{entry.name}</strong><small>{t({ "local-tool": "Local tool", skill: "Skill", cli: "CLI", knowledge: "Knowledge" }[entry.kind])}</small></div><button className="sand-work-icon-button" aria-label={t("Remove {name}", { name: entry.name })} onClick={() => onRemoveCatalogEntry(entry.id)} type="button"><SandIcon name="close" size={12} /></button></div>)}
            </div>
          </section>
          <WorkResizeHandle axis="vertical" label={t("Resize capabilities and agents")} value={inspector.capabilityHeight} min={bounds.minHeight} max={bounds.maxHeight}
            onChange={(height) => setInspectorPreference((current) => ({ ...current, split: height / Math.max(1, mainSize.height) }))} />
          <section className="sand-work-inspector__members" data-agent-drop-work={snapshot.profile.id}>
            <div className="sand-work-section-heading"><div><span>{t("Agents")}</span><small>{snapshot.members.length}</small></div></div>
            {statusAgent && statusAnchor ? <MemberStatusBubble key={`${statusAnchor.id}:${statusAnchor.shape}`} shape={statusAnchor.shape} agent={statusAgent} snapshot={snapshot} anchor={statusAnchor.element} onClose={() => setStatusAnchor(null)} /> : null}
            <div className="sand-work-members">
              {snapshot.members.map((member) => (
                <div
                  className="sand-work-member"
                  onPointerDown={(event) => memberDrag.start(event, member.profile.id, true)}
                  onClickCapture={memberDrag.onClickCapture}
                  onDragStart={(event) => event.preventDefault()}
                  key={member.profile.id}

                >
                  <button className="sand-work-member__identity" aria-expanded={statusAnchor?.id === member.profile.id} onClick={(event) => { const element = event.currentTarget; if (statusAnchor?.id === member.profile.id) setStatusAnchor(null); else setStatusAnchor({ id: member.profile.id, element, shape: statusShape.current++ % 4 }); }} type="button">
                    <AgentAvatar agentId={member.profile.id} color={member.profile.avatarColor} shape={member.profile.avatarShape} material={member.profile.avatarMaterial} size={34} state={member.runtime.status === "running" ? "working" : "idle"} />
                    <span><strong>{member.profile.name}</strong></span>
                  </button>
                  <button
                    aria-label={t("Remove {name}", { name: member.profile.name })}
                    onClick={() => onDetachAgent(member.profile.id, member.settings.workMembership?.revision ?? 0)}
                    type="button"
                  ><SandIcon name="close" size={12} /></button>
                </div>
              ))}
            </div>
            <div className="sand-work-member-drop-hint"><SandIcon name="nunu-plus" size={30} /><strong className="sand-work-drop-idle">{t("拖到此处以添加Nunu到当前NunuBar")}</strong><strong className="sand-work-drop-active">{t("Release to add Agent")}</strong><strong className="sand-work-drop-out">{t("Drop outside to remove")}</strong></div>
          </section>
        </aside>
      </div>
      {selectedTask ? <WorkDialog title={selectedTask.title} subtitle={t(STATE_LABELS[selectedTask.state])} onClose={() => setSelectedTaskId(null)}>
        <div className="sand-work-task-detail">
          {selectedTask.description ? <div className="sand-work-task-detail__summary">{selectedTask.description}</div> : null}
          {selectedTask.ownerAgentId ? <div className="sand-work-task-meta"><span>{t("Card owner")}</span><strong>{agents.find(agent => agent.profile.id === selectedTask.ownerAgentId)?.profile.name ?? selectedTask.ownerAgentId}</strong></div> : null}
          <div className="sand-work-task-people">
            <span>{t("Workers")}</span>
            <div className="sand-work-task-people__list">
              {selectedTask.assigneeIds.length ? selectedTask.assigneeIds.map((id) => {
                const agent = agents.find((item) => item.profile.id === id);
                return agent ? (
                  <span className="sand-work-task-person" key={id}>
                    <AgentAvatar agentId={id} color={agent.profile.avatarColor} shape={agent.profile.avatarShape} material={agent.profile.avatarMaterial} size={24} state={agent.runtime.status === "running" ? "working" : "idle"} />
                    <strong>{agent.profile.name}</strong>
                  </span>
                ) : null;
              }) : <strong>{t("Unassigned")}</strong>}
            </div>
          </div>
          <div className="sand-work-task-meta"><span>{t("Priority")}</span><strong>{t({ low: "Low", normal: "Normal", high: "High", urgent: "Urgent" }[selectedTask.priority])}</strong></div>
          {selectedTask.acceptanceCriteria.length ? <section><h3>{t("Acceptance criteria")}</h3><ul>{selectedTask.acceptanceCriteria.map((item, index) => <li key={index}>{item}</li>)}</ul></section> : null}
          {selectedTask.blocker ? <p className="sand-work-task-detail__blocker">{t("Blocked:")}{" "}{selectedTask.blocker.reason}</p> : null}
          {selectedTask.deliverables.length ? <section><h3>{t("产物")}</h3>{selectedTask.deliverables.map((file) => <div className="sand-work-task-file" key={file.id}><strong>{file.name}</strong><span>{file.uri}</span></div>)}</section> : null}
          {selectedTask.state === "blocked" ? <div className="sand-work-task-detail__actions">
            <p>{t("This card is paused until you confirm how to proceed.")}</p>
            <button type="button" onClick={() => onTransitionTask(selectedTask.id, "in_progress", selectedTask.revision)}>{t("Confirm and resume")}</button>
            <button type="button" onClick={() => onTransitionTask(selectedTask.id, "cancelled", selectedTask.revision)}>{t("Cancel task")}</button>
          </div> : null}
          {selectedTask.state === "review" ? <div className="sand-work-task-detail__actions">
            <button type="button" onClick={() => onTransitionTask(selectedTask.id, "in_progress", selectedTask.revision)}>{t("Request changes")}</button>
            <button type="button" onClick={() => onTransitionTask(selectedTask.id, "done", selectedTask.revision)}>{t("Accept delivery")}</button>
          </div> : null}
          {onReadTaskTrace ? <section>
            <button type="button" onClick={() => { setTraceError(""); void onReadTaskTrace(selectedTask.id).then(setTrace).catch((error: unknown) => setTraceError(String(error))); }}>{t("Execution history")}</button>
            {traceError ? <p role="alert">{traceError}</p> : null}
            {trace ? <div className="sand-work-trace">
              <select aria-label={t("Execution history")} value={trace.sessionId ?? ""} onChange={(event) => { void onReadTaskTrace(selectedTask.id, event.target.value).then(setTrace).catch((error: unknown) => setTraceError(String(error))); }}>
                {trace.sessions.map((session) => <option key={session.id} value={session.id}>{agents.find((agent) => agent.profile.id === session.agentId)?.profile.name ?? session.agentId} · {session.id.slice(0, 8)}</option>)}
              </select>
              {!trace.entries.length ? <p>{t("No execution history yet.")}</p> : null}
              {trace.entries.map((event) => <details key={event.id}><summary>{event.seq} · {event.type}</summary><pre>{traceText(event)}</pre></details>)}
              {trace.beforeSeq ? <button type="button" onClick={() => { void onReadTaskTrace(selectedTask.id, trace.sessionId, trace.beforeSeq).then((older) => setTrace({ ...older, entries: [...older.entries, ...trace.entries] })).catch((error: unknown) => setTraceError(String(error))); }}>{t("Load earlier")}</button> : null}
            </div> : null}
          </section> : null}
          {["ready", "in_progress"].includes(selectedTask.state) ? (
            <div className="sand-work-task-detail__actions">
              <div className="sand-work-task-dispatch">
                <select aria-label={t("Choose worker")} value={dispatchWorkerId} onChange={event => setDispatchWorkerId(event.target.value)}>
                  <option value="">{t("Choose worker")}</option>
                  {snapshot.members.filter(member => member.settings.workMembership?.binding?.grants.canManageOwnTasks).map(member => <option key={member.profile.id} value={member.profile.id}>{member.profile.name}</option>)}
                </select>
                <input
                  onChange={(event) => setDispatchInstruction(event.target.value)}
                  placeholder={t("Instruction for the Agent")}
                  value={dispatchInstruction}
                />
                <button
                  disabled={!dispatchInstruction.trim() || !snapshot.members.some(member => member.profile.id === dispatchWorkerId)}
                  onClick={() => {
                    onDispatchTask(dispatchWorkerId, selectedTask.id, dispatchInstruction.trim());
                    setDispatchInstruction("");
                  }}
                  type="button"
                >{t("Run")}</button>
              </div>
            </div>
          ) : null}
        </div>
      </WorkDialog> : null}
      {dialog === "capabilities" ? <WorkCapabilityDialog onClose={() => setDialog(null)} onAdd={onAddCatalogEntry} onPickDirectory={onPickDirectory} /> : null}


    </section>
  );
}


function traceText(event: TranscriptEvent): string {
  if (event.type === "user" || event.type === "wake") return event.text;
  if (event.type === "assistant") return event.parts.map((part) => part.type === "tool_call" ? `${part.name}\n${JSON.stringify(part.arguments, null, 2)}` : part.text).join("\n\n");
  if (event.type === "tool") return `${event.name}\n${event.content}`;
  return JSON.stringify(event, null, 2);
}
