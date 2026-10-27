import { t, useLanguage, setLanguage } from "@nuum/ui";
import {
  DesktopEvents,
  HostEvents,
  HostMethods,
  DEFAULT_MODEL_ID,
  appendAssistantDelta,
  projectAgent,
  resolveAvailableModel,
  type AttachmentUpload,
  type AgentSnapshot,
  type AgentView,
  type LiveAssistant,
  type Language,
  type ProviderId,
  type PublicSettings,
  type SidebarOrganization,
  type ThemePreference,
  type ToolResolution,
  type TranscriptEvent,
  type ViewBlock,
  type WorkCatalogAddParams,
  type WorkListItem,
  type WorkProfile,
  type WorkSnapshot
} from "@nuum/protocol";
import {
  AgentProfilePanel,
  ConversationSidebar,
  ConversationWorkspace,
  SettingsOverlay,
  SettingsSelect,
  WorkBoard,
  RoomSnapshotReplica,
  WorkCreation,
  createRuntimeThemeInstaller,
  readSidebarLayout,
  writeSidebarLayout,
  type RuntimeThemeMode,
  type SidebarLayoutState
} from "@nuum/ui";
import { useEffect, useMemo, useRef, useState } from "react";

function resolveTheme(preference: ThemePreference): RuntimeThemeMode {
  if (preference === "light" || preference === "dark") return preference;
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

type AgentPane = {
  events: TranscriptEvent[];
  live: LiveAssistant | null;
  notice: string | null;
  pendingTool: {
    toolCallId: string;
    name: string;
    arguments: Record<string, unknown>;
    action: "read-file" | "list-directory" | "write-file" | "run-command" | "network";
    workId?: string;
    target: string;
    justification?: string; allowAlways?: boolean; details?: string;
  } | null;
  draft: string;
  attachments: AttachmentUpload[];
  sending?: boolean;
};

const emptyPane: AgentPane = { events: [], live: null, notice: null, pendingTool: null, draft: "", attachments: [] };

/**
 * Host 通知与 agent.get 快照可能交错到达。JSONL 的 seq 才是顺序真值；
 * renderer 只做去重和排序，不发明第二条时间线。
 */
function mergeTranscriptEvents(...sources: readonly (readonly TranscriptEvent[])[]): TranscriptEvent[] {
  const byId = new Map<string, TranscriptEvent>();
  for (const source of sources) {
    for (const event of source) byId.set(event.id, event);
  }
  return [...byId.values()].sort((left, right) => left.seq - right.seq || left.id.localeCompare(right.id));
}

function applyPanePatch(
  current: Record<string, AgentPane>,
  id: string,
  patch: Partial<AgentPane> | ((current: AgentPane) => Partial<AgentPane>)
): Record<string, AgentPane> {
  const previous = current[id] ?? emptyPane;
  const next = typeof patch === "function" ? patch(previous) : patch;
  return { ...current, [id]: { ...previous, ...next } };
}

function transcriptTimestamps(events: readonly TranscriptEvent[]): Readonly<Record<string, number>> {
  const timestamps: Record<string, number> = {};
  for (const event of events) {
    timestamps[event.id] = event.createdAt;
    if (event.type === "assistant") {
      for (const part of event.parts) {
        if (part.type === "tool_call") timestamps[part.id] = event.createdAt;
      }
    }
  }
  return timestamps;
}

export function App() {
  const language = useLanguage();
  const [languageSaving, setLanguageSaving] = useState(false);
  const [languageError, setLanguageError] = useState("");
  useEffect(() => { document.documentElement.lang = language; }, [language]);
  const [agents, setAgents] = useState<AgentView[]>([]);
  const [works, setWorks] = useState<WorkListItem[]>([]);
  // 侧栏 subtitle 的最近一句话：用既有 RPC 拉一小页转录，经 projectAgent 投影后
  // 取最后一条用户可见的对话内容。口径与聊天页同源（单一投影），host 不做第二套解释。
  const [previews, setPreviews] = useState<Record<string, string>>({});
  const [activeId, setActiveId] = useState<string | null>(null);
  const [activeWorkId, setActiveWorkId] = useState<string | null>(null);
  const [workSnapshot, setWorkSnapshot] = useState<WorkSnapshot | null>(null);
  const [creatingWork, setCreatingWork] = useState(false);
  const [workNotice, setWorkNotice] = useState<string | null>(null);
  const [panes, setPanes] = useState<Record<string, AgentPane>>({});
  const [creatingAgent, setCreatingAgent] = useState(false);
  const [creationError, setCreationError] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [profileEditorId, setProfileEditorId] = useState<string | null>(null);
  const profileSave = useRef(Promise.resolve());
  const [settingsSection, setSettingsSection] = useState<"general" | "models">("general");
  const [settings, setSettings] = useState<PublicSettings | null>(null);
  const [openaiKey, setOpenaiKey] = useState("");
  const [anthropicKey, setAnthropicKey] = useState("");
  const [deepseekKey, setDeepseekKey] = useState("");
  const [themePref, setThemePref] = useState<ThemePreference>("dark");
  const [sidebarLayout, setSidebarLayout] = useState<SidebarLayoutState>(() =>
    typeof localStorage === "undefined" ? { expandedWidth: 236, isCollapsed: false } : readSidebarLayout()
  );
  const sidebarSave = useRef(Promise.resolve());
  const themeHandle = useRef<ReturnType<typeof createRuntimeThemeInstaller> | null>(null);
  const activeWorkIdRef = useRef<string | null>(null);
  const roomReplica = useRef(new RoomSnapshotReplica());
  function selectWork(id: string | null): void {
    activeWorkIdRef.current = id;
    setActiveWorkId(id);
    setWorkSnapshot(id ? roomReplica.current.get(id) ?? null : null);
  }

  const active = useMemo(
    () => agents.find((agent) => agent.profile.id === activeId) ?? null,
    [agents, activeId]
  );
  const pane = (activeId ? panes[activeId] : undefined) ?? emptyPane;
  const draft = activeId ? pane.draft : "";
  const inputModel = resolveAvailableModel({
    openaiApiKey: settings?.hasOpenaiKey ? "available" : undefined,
    anthropicApiKey: settings?.hasAnthropicKey ? "available" : undefined,
    deepseekApiKey: settings?.hasDeepseekKey ? "available" : undefined
  }, active?.settings.model) ?? active?.settings.model;
  const blocks = projectAgent(pane.events, pane.live).blocks;
  const blockTimestamps = transcriptTimestamps(pane.events);

  function patchPane(id: string, patch: Partial<AgentPane> | ((current: AgentPane) => Partial<AgentPane>)): void {
    setPanes((current) => applyPanePatch(current, id, patch));
  }

  useEffect(() => {
    const handle = createRuntimeThemeInstaller(document as never, resolveTheme(themePref));
    themeHandle.current = handle;
    return () => {
      handle.dispose();
      themeHandle.current = null;
    };
  }, []);

  useEffect(() => {
    themeHandle.current?.update(resolveTheme(themePref));
    document.documentElement.className = resolveTheme(themePref) === "dark" ? "nuum-dark" : "nuum-light";
    document.documentElement.style.colorScheme = resolveTheme(themePref);
  }, [themePref]);

  useEffect(() => {
    if (window.nuum == null) return;
    void refresh();
    return window.nuum.host.onEvent((method, params) => {
      const payload = params as Record<string, any>;
      if (method === DesktopEvents.navigateAgent && typeof payload.agentId === "string") {
        setSettingsOpen(false);
        void openAgent(payload.agentId);
      }
      if (method === HostEvents.settingsUpdated) {
        const preferences = params as PublicSettings;
        setSettings(preferences);
        setLanguage(preferences.language ?? "zh-CN");
        setThemePref(preferences.theme ?? "dark");
      }
      const agentId = typeof payload.agentId === "string" ? payload.agentId : "";
      if (method === HostEvents.agentUpdated && payload.agent) {
        setAgents((current) => upsert(current, payload.agent as AgentView));
        void loadPreview((payload.agent as AgentView).profile.id);
      }
      if (method === HostEvents.agentMessageDelta && agentId) {
        setPanes((current) => applyPanePatch(current, agentId, (pane) => {
          const messageId = String(payload.messageId);
          const base = pane.live?.messageId === messageId ? pane.live.parts : [];
          return {
            live: {
              messageId,
              parts: appendAssistantDelta(base, payload.part === "thinking" ? "thinking" : "text", String(payload.delta ?? ""))
            }
          };
        }));
      }
      if (method === HostEvents.agentMessageCompleted && agentId && payload.event) {
        const event = payload.event as TranscriptEvent;
        setPanes((current) => applyPanePatch(current, agentId, (pane) => ({
          events: mergeTranscriptEvents(pane.events, [event]),
          live: event.type === "assistant" && pane.live?.messageId === event.id ? null : pane.live
        })));
      }
      if (method === HostEvents.agentToolPending && agentId) {
        setPanes((current) => applyPanePatch(current, agentId, {
          pendingTool: {
            toolCallId: payload.toolCallId,
            name: payload.name,
            arguments: payload.arguments ?? {},
            action: payload.action,
            workId: payload.workId,
            justification: payload.justification, allowAlways: payload.allowAlways, details: payload.details,
            target: payload.target
          }
        }));
      }
      if (method === HostEvents.agentToolCompleted && agentId) {
        setPanes((current) => applyPanePatch(current, agentId, { pendingTool: null }));
      }
      if (method === HostEvents.agentError && agentId) {
        setPanes((current) => applyPanePatch(current, agentId, {
          notice: String(payload.message ?? t("Host error")),
          live: null
        }));
      }
      if (method === HostEvents.agentEnded && agentId) {
        if (activeWorkIdRef.current) void loadWork(activeWorkIdRef.current);
        setPanes((current) => applyPanePatch(current, agentId, {
          live: null,
          // 被掐和跑完是两回事，不能都静悄悄地收场。
          ...(payload.status === "cancelled" ? { notice: t("Stopped.") } : {})
        }));
      }
      if (method === HostEvents.workUpdated && payload.work) {
        // workUpdated 只带 profile；侧栏要的预览/最近动态以重拉列表为准。
        void refreshWorks();
      }
      if (
        (method === HostEvents.workEventAppended || method === HostEvents.workCatalogUpdated) &&
        typeof payload.workId === "string" &&
        payload.workId === activeWorkIdRef.current
      ) {
        void loadWork(payload.workId);
      }
    });
  }, []);

  async function refresh(): Promise<void> {
    const [list, workList, publicSettings] = await Promise.all([
      window.nuum.host.request(HostMethods.agentList) as Promise<AgentView[]>,
      window.nuum.host.request(HostMethods.workList) as Promise<WorkListItem[]>,
      window.nuum.host.request(HostMethods.settingsGet) as Promise<PublicSettings>
    ]);
    setAgents(list);
    setWorks(workList);
    setSettings(publicSettings);
    setLanguage(publicSettings.language ?? "zh-CN");
    setThemePref(publicSettings.theme ?? "dark");
    void Promise.all(list.map((agent) => loadPreview(agent.profile.id)));
    const secrets = await window.nuum.desktop.getSecrets();
    setOpenaiKey(secrets.openaiApiKey ?? "");
    setAnthropicKey(secrets.anthropicApiKey ?? "");
    setDeepseekKey(secrets.deepseekApiKey ?? "");
    if (!activeId && list[0]) {
      setCreatingAgent(false);
      await openAgent(list[0].profile.id);
    } else if (list.length === 0) {
      setActiveId(null);
      setCreatingAgent(true);
    }
  }

  async function openAgent(id: string, editProfile = false): Promise<void> {
    setProfileEditorId(editProfile ? id : null);
    setCreatingAgent(false);
    setCreatingWork(false);
    setCreationError(null);
    selectWork(null);
    setWorkSnapshot(null);
    setActiveId(id);
    await loadAgent(id);
  }

  async function loadAgent(id: string): Promise<void> {
    const snapshot = await window.nuum.host.request(HostMethods.agentGet, { id }) as AgentSnapshot;
    setAgents((current) => upsert(current, snapshot.view));
    setPanes((current) => {
      const previous = current[id] ?? emptyPane;
      return {
        ...current,
        [id]: {
          ...previous,
          events: mergeTranscriptEvents(snapshot.events, previous.events),
          live: snapshot.live
        }
      };
    });
  }

  async function refreshWorks(): Promise<void> {
    const workList = await window.nuum.host.request(HostMethods.workList) as WorkListItem[];
    setWorks(workList);
  }

  async function loadPreview(id: string): Promise<void> {
    // 预览只是锦上添花：任何失败（如 agent 恰被删除）保持原值即可，绝不能产生未处理拒绝。
    try {
      const page = await window.nuum.host.request(HostMethods.agentGetTranscript, { id, limit: 40 }) as { entries: TranscriptEvent[] };
      const text = extractPreviewText(projectAgent(page.entries).blocks);
      if (!text) return;
      setPreviews((current) => ({ ...current, [id]: text.replace(/\s+/g, " ").trim().slice(0, 160) }));
    } catch {
      // 保持现有 preview 不变。
    }
  }

  async function loadWork(id: string): Promise<void> {
    const snapshot = await window.nuum.host.request(HostMethods.workGet, { id }) as WorkSnapshot;
    if (activeWorkIdRef.current !== id) return;
    setWorkSnapshot(roomReplica.current.apply(snapshot));
  }

  async function openWork(id: string): Promise<void> {
    setCreatingAgent(false);
    setCreatingWork(false);
    setActiveId(null);
    selectWork(id);
    setWorkNotice(null);
    await loadWork(id);
  }

  function newAgent(): void {
    setActiveId(null);
    selectWork(null);
    setWorkSnapshot(null);
    setCreatingWork(false);
    setCreationError(null);
    setCreatingAgent(true);
  }

  function newWork(): void {
    setCreatingAgent(false);
    setCreatingWork(true);
    setActiveId(null);
    selectWork(null);
    setWorkSnapshot(null);
  }

  async function createWork(input: { name: string; kind?: "room" | "work" }): Promise<void> {
    const created = await window.nuum.host.request(HostMethods.workCreate, {
      ...input
    }) as WorkProfile;
    await refreshWorks();
    await openWork(created.id);
  }

  async function createAgent(profile: {
    name: string;
    description: string;
    avatarColor: string;
    avatarShape: string;
    avatarMaterial: string;
  }): Promise<void> {
    setCreationError(null);
    try {
      const created = await window.nuum.host.request(HostMethods.agentCreate, profile) as AgentView;
      setAgents((current) => upsert(current, created));
      setCreatingAgent(false);
      await openAgent(created.profile.id);
    } catch (error) {
      setCreationError(error instanceof Error ? error.message : String(error));
    }
  }

  function cancelCreate(): void {
    const fallback = agents[0];
    if (fallback) void openAgent(fallback.profile.id);
  }

  async function send(): Promise<void> {
    const id = activeId;
    if (!id) return;
    await sendAgent(id);
  }

  async function sendAgent(id: string): Promise<void> {
    const targetPane = panes[id] ?? emptyPane;
    if (targetPane.sending || (!targetPane.draft.trim() && !targetPane.attachments.length)) return;
    const content = targetPane.draft;
    try {
      patchPane(id, { sending: true, notice: null });
      await window.nuum.host.request(HostMethods.agentSend, { id, content, attachments: targetPane.attachments });
      patchPane(id, { draft: "", attachments: [], sending: false });
    } catch (error) {
      if (id) {
        patchPane(id, { sending: false, notice: error instanceof Error ? error.message : String(error) });
      }
    }
  }

  async function approve(resolution: ToolResolution): Promise<void> {
    if (!activeId) return;
    await approveAgent(activeId, resolution);
  }

  async function answerWidgetAgent(id: string, messageId: string, value: string): Promise<void> {
    try {
      await window.nuum.host.request(HostMethods.agentAnswerWidget, { id, messageId, value });
    } catch (error) {
      patchPane(id, { notice: error instanceof Error ? error.message : String(error) });
    }
  }

  function answerWidget(messageId: string, value: string): void {
    if (!activeId) return;
    void answerWidgetAgent(activeId, messageId, value);
  }

  async function approveAgent(id: string, resolution: ToolResolution): Promise<void> {
    const pendingTool = (panes[id] ?? emptyPane).pendingTool;
    if (!pendingTool) return;
    const method = resolution === "deny" ? HostMethods.agentDenyTool : HostMethods.agentApproveTool;
    await window.nuum.host.request(method, {
      id,
      toolCallId: pendingTool.toolCallId,
      resolution
    });
    patchPane(id, { pendingTool: null });
  }

  async function refreshActiveWork(): Promise<void> {
    if (activeWorkId) await loadWork(activeWorkId);
  }

  async function runWorkMutation(work: () => Promise<unknown>): Promise<boolean> {
    setWorkNotice(null);
    try {
      await work();
      const [agentList, workList] = await Promise.all([
        window.nuum.host.request(HostMethods.agentList) as Promise<AgentView[]>,
        window.nuum.host.request(HostMethods.workList) as Promise<WorkListItem[]>
      ]);
      setAgents(agentList);
      setWorks(workList);
      await refreshActiveWork();
      return true;
    } catch (error) {
      setWorkNotice(error instanceof Error ? error.message : String(error));
      return false;
    }
  }

  function moveAgentToWork(agentId: string, workId: string, role: "worker" | "coordinator" | "observer" = "worker"): void {
    const target = agents.find((agent) => agent.profile.id === agentId);
    if (!target) return;
    const membership = target.roomMemberships?.[workId] ?? { revision: 0, binding: null };
    if (membership.binding) return;
    void runWorkMutation(() => window.nuum.host.request(HostMethods.workMemberAttach, {
      workId, agentId, role, expectedRevision: membership.revision
    }));
  }

  const secretSaveQueue = useRef(Promise.resolve());
  function saveApiKey(field: "openaiApiKey" | "anthropicApiKey" | "deepseekApiKey", value: string): void {
    // Serialize read/merge/write so consecutive blurs cannot overwrite another key.
    secretSaveQueue.current = secretSaveQueue.current.then(async () => {
      const secrets = await window.nuum.desktop.getSecrets();
      await window.nuum.desktop.setSecrets({ ...secrets, [field]: value || undefined });
      const next = await window.nuum.host.request(HostMethods.settingsSet, {
        [field]: value || null
      }) as PublicSettings;
      setSettings((current) => current ? {
        ...current,
        hasOpenaiKey: next.hasOpenaiKey,
        hasAnthropicKey: next.hasAnthropicKey,
        hasDeepseekKey: next.hasDeepseekKey
      } : next);
    }).catch(() => {
      // Keep diagnostics out of the form and never log secret values.
      console.warn("Could not persist API key settings.");
    });
  }


  return (
    <div className="sand-app">
      <div className="sand-cover-drag" />
      <ConversationSidebar
        agents={agents}
        organization={settings?.sidebar}
        onEditAgent={(id) => void openAgent(id, true)}
        onOrganizationChange={(sidebar: SidebarOrganization) => {
          const save = sidebarSave.current.then(async () => {
            const next = await window.nuum.host.request(HostMethods.settingsSet, { sidebar }) as PublicSettings;
            setSettings((current) => current ? { ...current, sidebar: next.sidebar } : next);
          });
          sidebarSave.current = save.catch(() => {});
          return save;
        }}
        previews={previews}
        works={works}
        activeId={activeId}
        activeWorkId={activeWorkId}
        layout={sidebarLayout}
        onLayoutChange={(next) => {
          setSidebarLayout(next);
          if (!next.isDragging) writeSidebarLayout(next);
        }}
        onNewAgent={newAgent}
        onNewWork={newWork}
        onOpen={(id) => void openAgent(id)}
        onOpenWork={(id) => void openWork(id)}
        onMoveAgentToWork={moveAgentToWork}
        onOpenSettings={() => setSettingsOpen(true)}
      />
      <div className="sand-workspace">
        {creatingWork ? (
          <WorkCreation
            canCancel={agents.length > 0 || works.length > 0}
            onCancel={() => works[0] ? void openWork(works[0].id) : cancelCreate()}
            onCreate={(input) => void createWork(input)}
          />
        ) : activeWorkId && workSnapshot ? (
          <WorkBoard
            key={activeWorkId}
            onMoveAgentToWork={moveAgentToWork}
            onPickDirectory={() => window.nuum.desktop.pickWorkspace()}
            agents={agents}
            snapshot={workSnapshot}
            approvals={Object.entries(panes).flatMap(([agentId, pane]) => pane.pendingTool?.workId === activeWorkId ? [{ ...pane.pendingTool, agentId, agentName: agents.find(agent => agent.profile.id === agentId)?.profile.name ?? "Nunu" }] : [])}
            onApproveTool={(agentId, resolution) => approveAgent(agentId, resolution)}
            onUpdateWork={(patch) => void runWorkMutation(() => window.nuum.host.request(HostMethods.workUpdate, {
              id: activeWorkId,
              ...patch
            }))}
            onContinue={(eventId, inputAfterSeq) => void runWorkMutation(() => window.nuum.host.request(HostMethods.workContinue, { workId: activeWorkId, eventId, inputAfterSeq }))}
            onStopDiscussion={() => void runWorkMutation(() => window.nuum.host.request(HostMethods.workStopDiscussion, { id: activeWorkId }))}
            onPostMessage={(body) => void runWorkMutation(() => window.nuum.host.request(HostMethods.workPostMessage, {
              workId: activeWorkId,
              body,
              clientEventId: crypto.randomUUID(),
              mentionedAgentIds: []
            }))}
            onCreateTask={({ title, assigneeIds }) => void runWorkMutation(() => window.nuum.host.request(HostMethods.workTaskCreate, {
              workId: activeWorkId,
              title,
              description: "",
              acceptanceCriteria: [],
              assigneeIds,
              dependencyIds: [],
              priority: "normal"
            }))}
            onTransitionTask={(taskId, to, expectedRevision, blockerReason) => void runWorkMutation(() =>
              window.nuum.host.request(HostMethods.workTaskTransition, {
                workId: activeWorkId,
                taskId,
                to,
                expectedRevision,
                ...(blockerReason ? { blocker: { reason: blockerReason } } : {})
              })
            )}
            onReadTaskTrace={async (taskId, sessionId, beforeSeq) => window.nuum.host.request(HostMethods.workTaskTranscript, { workId: activeWorkId, taskId, sessionId, beforeSeq }) as Promise<{ sessions: { id: string; agentId: string }[]; sessionId?: string; entries: import("@nuum/protocol").TranscriptEvent[]; beforeSeq?: number }>}
            onDispatchTask={(agentId, taskId, instruction) => void runWorkMutation(() =>
              window.nuum.host.request(HostMethods.workDispatch, {
                workId: activeWorkId,
                agentId,
                taskId,
                instruction
              })
            )}
            onDetachAgent={(agentId, expectedRevision) => void runWorkMutation(() =>
              window.nuum.host.request(HostMethods.workMemberDetach, {
                workId: activeWorkId,
                agentId,
                expectedRevision
              })
            )}
            onAddCatalogEntry={(entry: WorkCatalogAddParams["entry"]) => runWorkMutation(() =>
              window.nuum.host.request(HostMethods.workCatalogAdd, {
                workId: activeWorkId,
                expectedRevision: workSnapshot.catalog.revision,
                entry
              })
            )}
            onRemoveCatalogEntry={(entryId) => void runWorkMutation(() =>
              window.nuum.host.request(HostMethods.workCatalogRemove, {
                workId: activeWorkId,
                entryId,
                expectedRevision: workSnapshot.catalog.revision
              })
            )}
          />
        ) : (
          <ConversationWorkspace
            agent={active}
            agents={agents}
            blocks={blocks}
            blockTimestamps={blockTimestamps}
            creatingAgent={creatingAgent}
            canCancelCreate={agents.length > 0}
            creationError={creationError}
            pendingTool={pane.pendingTool?.workId ? null : pane.pendingTool}
            draft={draft}
            attachments={pane.attachments}
            sending={pane.sending}
            inputModel={inputModel}
            onAttachmentsChange={files => { if (activeId) patchPane(activeId, { attachments: files }); }}
            onOpenAttachment={file => { void window.nuum.desktop.openPath(file); }}
            notice={pane.notice}
            onDraftChange={(value) => {
              if (activeId) patchPane(activeId, { draft: value });
            }}
            onSubmit={() => void send()}
            onCancel={() => activeId && void window.nuum.host.request(HostMethods.agentCancel, { id: activeId })}
            onCancelCreate={cancelCreate}
            onCreateAgent={(profile) => void createAgent(profile)}
            onApprove={(resolution) => approve(resolution)}
            onAnswerWidget={answerWidget}
            onOpenProfile={() => active && setProfileEditorId((current) => current === active.profile.id ? null : active.profile.id)}
          />
        )}
        {workNotice ? <div className="sand-work-notice" role="alert">{t(workNotice)}</div> : null}

      </div>
      {active && profileEditorId === active.profile.id && !creatingAgent && !activeWorkId && !creatingWork ? (
        <AgentProfilePanel key={active.profile.id} profile={active.profile} settings={active.settings}
          workspaceNames={Object.fromEntries(works.filter(work => work.workspaceId).map(work => [work.workspaceId!, work.name]))}
          onOpenWorkspace={() => { if (active.settings.workspace?.projectRoot) void window.nuum.desktop.openPath(active.settings.workspace.projectRoot); }}
          onSaveExecution={async execution => {
            const updated = await window.nuum.host.request(HostMethods.agentUpdate, { id: active.profile.id, execution }) as AgentView;
            setAgents(items => upsert(items, updated));
          }} onClose={() => setProfileEditorId(null)} onSave={(patch) => {
          const id = active.profile.id;
          const save = profileSave.current.then(async () => {
            const updated = await window.nuum.host.request(HostMethods.agentUpdate, { id, ...patch }) as AgentView;
            setAgents((items) => upsert(items, updated));
          });
          profileSave.current = save.catch(() => {});
          return save;
        }} />
      ) : null}
      <SettingsOverlay
        open={settingsOpen}
        section={settingsSection}
        onSection={setSettingsSection}
        onClose={() => setSettingsOpen(false)}
      >
        {settingsSection === "general" ? (
          <div className="sand-settings-stack">
            <section className="sand-settings-group"><h3>{t("Appearance")}</h3><div className="sand-settings-group__surface">
            <div className="sand-settings-row">
              <div className="sand-settings-copy"><span>{t("Language")}</span><small>{t("Choose the language used throughout Nuum.")}</small></div>
              <div className="sand-settings-control">
                <SettingsSelect aria-label={t("Language")} value={language} disabled={languageSaving} onChange={async (event) => {
                  const next = event.target.value as Language;
                  setLanguageSaving(true); setLanguageError("");
                  try {
                    await window.nuum.host.request(HostMethods.settingsSet, { language: next });
                    setSettings((current) => current ? { ...current, language: next } : current);
                    setLanguage(next);
                  } catch { setLanguageError("Could not change language. Please try again."); }
                  finally { setLanguageSaving(false); }
                }}><option value="zh-CN" lang="zh-CN">中文</option><option value="en" lang="en">English</option></SettingsSelect>
                {languageError ? <small role="alert">{t(languageError)}</small> : null}
              </div>
            </div>
            <div className="sand-settings-row">
              <div className="sand-settings-copy">
                <span>{t("Theme")}</span>
                <small>{t("Keep the current dark shell, or switch to the light palette.")}</small>
              </div>
              <div className="sand-settings-control">
                <SettingsSelect aria-label={t("Theme")} value={themePref} onChange={(event) => {
                  const next = event.target.value as ThemePreference;
                  setThemePref(next);
                  void window.nuum.host.request(HostMethods.settingsSet, { theme: next }).then((value) => setSettings(value as PublicSettings));
                }}>
                  <option value="system">{t("Follow system")}</option>
                  <option value="light">{t("Light")}</option>
                  <option value="dark">{t("Dark")}</option>
                </SettingsSelect>
              </div>
            </div>
            </div></section>
            <section className="sand-settings-group"><h3>Proactive mode</h3><div className="sand-settings-group__surface">
              <div className="sand-settings-row"><div className="sand-settings-copy"><span>Nunu</span><small>{t("Manage your proactive companion from the menu bar.")}</small></div>
                <div className="sand-settings-control"><button className="sand-kit-button" type="button" onClick={() => void window.nuum.desktop.showProactive()}>{t("Open menu bar panel")}</button></div>
              </div>
            </div></section>
          </div>
        ) : (
          <div className="sand-settings-stack">
            <section className="sand-settings-group"><h3>{t("Model preferences")}</h3><div className="sand-settings-group__surface">
            <div className="sand-settings-row">
              <div className="sand-settings-copy">
                <span>{t("Default provider")}</span>
                <small>{t("Used for new chats until you change the session model.")}</small>
              </div>
              <div className="sand-settings-control">
                <SettingsSelect aria-label={t("Default provider")}
                  value={settings?.defaultModel.provider ?? "deepseek"}
                  onChange={async (event) => {
                    const provider = event.target.value as ProviderId;
                    const next = await window.nuum.host.request(HostMethods.settingsSet, {
                      defaultModel: { provider, model: DEFAULT_MODEL_ID[provider] }
                    }) as PublicSettings;
                    setSettings(next);
                  }}
                >
                  <option value="deepseek">DeepSeek</option>
                  <option value="openai">OpenAI</option>
                  <option value="anthropic">Anthropic</option>
                </SettingsSelect>
              </div>
            </div>
            {settings?.defaultModel.provider === "deepseek" ? (
              <div className="sand-settings-row">
                <div className="sand-settings-copy">
                  <span>{t("DeepSeek model")}</span>
                  <small>{t("deepseek-chat for everyday use. deepseek-reasoner for longer reasoning.")}</small>
                </div>
                <div className="sand-settings-control">
                  <SettingsSelect aria-label={t("DeepSeek model")}
                    value={settings.defaultModel.model}
                    onChange={async (event) => {
                      const next = await window.nuum.host.request(HostMethods.settingsSet, {
                        defaultModel: { provider: "deepseek", model: event.target.value }
                      }) as PublicSettings;
                      setSettings(next);
                    }}
                  >
                    <option value="deepseek-chat">deepseek-chat</option>
                    <option value="deepseek-reasoner">deepseek-reasoner</option>
                  </SettingsSelect>
                </div>
              </div>
            ) : null}
            </div></section>
            <section className="sand-settings-group"><h3>{t("API keys")}</h3><div className="sand-settings-group__surface">
            <div className="sand-settings-row">
              <div className="sand-settings-copy">
                <span>{t("DeepSeek API key")}</span>
                <small>{t("Stored in the OS keychain and injected into Host memory only.")}</small>
              </div>
              <div className="sand-settings-control">
                <input onBlur={(event) => saveApiKey("deepseekApiKey", event.currentTarget.value)} onChange={(event) => setDeepseekKey(event.target.value)} type="password" value={deepseekKey} />
              </div>
            </div>
            <div className="sand-settings-row">
              <div className="sand-settings-copy">
                <span>{t("OpenAI API key")}</span>
                <small>{t("Optional. Used when the default provider is OpenAI.")}</small>
              </div>
              <div className="sand-settings-control">
                <input onBlur={(event) => saveApiKey("openaiApiKey", event.currentTarget.value)} onChange={(event) => setOpenaiKey(event.target.value)} type="password" value={openaiKey} />
              </div>
            </div>
            <div className="sand-settings-row">
              <div className="sand-settings-copy">
                <span>{t("Anthropic API key")}</span>
                <small>{t("Optional. Used when the default provider is Anthropic.")}</small>
              </div>
              <div className="sand-settings-control">
                <input onBlur={(event) => saveApiKey("anthropicApiKey", event.currentTarget.value)} onChange={(event) => setAnthropicKey(event.target.value)} type="password" value={anthropicKey} />
              </div>
            </div>
            </div></section>
          </div>
        )}
      </SettingsOverlay>
    </div>
  );
}

function upsert(list: AgentView[], agent: AgentView): AgentView[] {
  return [agent, ...list.filter((item) => item.profile.id !== agent.profile.id)].sort(
    (a, b) => b.runtime.lastActivityAt - a.runtime.lastActivityAt
  );
}

function extractPreviewText(blocks: readonly ViewBlock[]): string | undefined {
  for (let index = blocks.length - 1; index >= 0; index -= 1) {
    const block = blocks[index]!;
    if (block.type === "user" || block.type === "peer") return block.text;
    if (block.type === "message" && block.payload.type === "text") return block.payload.content;
  }
  return undefined;
}
