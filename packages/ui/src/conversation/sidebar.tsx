import { t } from "../i18n";
import type { AgentView, WorkListItem, SidebarOrganization } from "@nuum/protocol";
import { useEffect, useMemo, useRef, useState, type MouseEvent } from "react";
import { SandIcon, SandIconButton } from "../kit/sand-kit-primitives";
import { useAgentDrag } from "../workbar/agent-drag";
import { EMPTY_SIDEBAR, UNASSIGNED_SECTION, PINNED_SECTION, assignSidebarAgent, projectSidebarAgents, toggleSidebarPin, removeSidebarSection, reorderSidebarPin } from "./sidebar-organization";
import { SidebarMenu, SidebarNameDialog, SidebarNewMenu, type SidebarMenuItem } from "./sidebar-menu";
import "./sidebar-organization.css";
import { AgentAvatar, WorkGroupAvatar } from "./agent-avatar";
import {
  SidebarResizeHandle,
  applySidebarDrag,
  projectResponsiveSidebar,
  settleSidebarLayout,
  type SidebarLayoutState
} from "./sidebar-resize";

export interface ConversationSidebarProps {
  agents: readonly AgentView[];
  organization?: SidebarOrganization;
  onOrganizationChange(next: SidebarOrganization): Promise<void>;
  onEditAgent(id: string): void;
  /** 最近一句话（UI 层经 projectAgent 投影取自转录尾部），subtitle 优先展示它。 */
  previews: Readonly<Record<string, string>>;
  works: readonly WorkListItem[];
  activeId: string | null;
  activeWorkId: string | null;
  layout: SidebarLayoutState;
  onLayoutChange(next: SidebarLayoutState): void;
  onNewAgent(): void;
  onNewWork(): void;
  onOpen(id: string): void;
  onOpenWork(id: string): void;
  onMoveAgentToWork(agentId: string, workId: string): void;
  onOpenSettings(): void;
}

function relativeTime(updatedAt: number): string {
  const seconds = Math.max(0, Math.round((Date.now() - updatedAt) / 1000));
  if (seconds < 60) return t("now");
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return t("{count}m", { count: minutes });
  const hours = Math.round(minutes / 60);
  return hours < 24 ? t("{count}h", { count: hours }) : t("{count}d", { count: Math.round(hours / 24) });
}

export function agentAccent(id: string): string {
  const hues = [210, 32, 152, 98, 268, 18];
  let hash = 0;
  for (let i = 0; i < id.length; i += 1) hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
  return `hsl(${hues[hash % hues.length]} 48% 48%)`;
}

export function ConversationSidebar({
  agents,
  organization = EMPTY_SIDEBAR,
  onOrganizationChange,
  onEditAgent,
  previews,
  works,
  activeId,
  activeWorkId,
  layout,
  onLayoutChange,
  onNewAgent,
  onNewWork,
  onOpen,
  onOpenWork,
  onMoveAgentToWork,
  onOpenSettings
}: ConversationSidebarProps) {
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [menu, setMenu] = useState<{ point: { x: number; y: number }; agentId?: string; sectionId?: string; view?: "groups" } | null>(null);
  const [newMenu, setNewMenu] = useState<{ left: number; top: number; width: number } | null>(null);
  const [groupDialog, setGroupDialog] = useState<{ sectionId?: string; agentId?: string; name: string } | null>(null);
  const menuOrigin = useRef<HTMLElement | null>(null);
  const closeMenu = () => { setMenu(null); menuOrigin.current?.focus({ preventScroll: true }); };
  const commit = async (next: SidebarOrganization) => {
    if (busy) return false;
    setBusy(true); setNotice("");
    try { await onOrganizationChange(next); return true; }
    catch { setNotice(t("Could not save sidebar changes. Please try again.")); return false; }
    finally { setBusy(false); }
  };
  const agentDrag = useAgentDrag(({ agentId, workId, sectionId, beforePinnedId }) => {
    if (workId) { onMoveAgentToWork(agentId, workId); return; }
    if (beforePinnedId) { void commit(reorderSidebarPin(organization, agentId, beforePinnedId)); return; }
    if (sectionId) void commit(assignSidebarAgent(organization, agentId, sectionId));
  }, { holdToDrag: true });
  const showMenu = (event: MouseEvent<HTMLElement>, target: { agentId?: string; sectionId?: string }) => {
    event.preventDefault(); event.stopPropagation();
    menuOrigin.current = event.currentTarget;
    const rect = event.currentTarget.getBoundingClientRect();
    setMenu({ ...target, point: { x: event.clientX || rect.left + 20, y: event.clientY || rect.bottom } });
  };
  const openNewMenu = (event: MouseEvent<HTMLElement>) => {
    if (newMenu) { setNewMenu(null); return; }
    const rect = event.currentTarget.getBoundingClientRect();
    const aside = event.currentTarget.closest("aside")?.getBoundingClientRect();
    setNewMenu({
      left: aside ? aside.left + 12 : rect.left,
      top: rect.bottom + 6,
      width: Math.min(Math.max(aside ? aside.width - 24 : 248, 208), 300)
    });
  };
  const [query, setQuery] = useState("");
  const [searchOpen, setSearchOpen] = useState(false);
  const searchRef = useRef<HTMLInputElement | null>(null);
  useEffect(() => {
    if (searchOpen) searchRef.current?.focus();
  }, [searchOpen]);
  const layoutRef = useRef(layout);
  layoutRef.current = layout;
  const [viewportWidth, setViewportWidth] = useState(() => window.innerWidth);
  useEffect(() => {
    const resize = () => setViewportWidth(window.innerWidth);
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, []);
  const effectiveLayout = projectResponsiveSidebar(layout, viewportWidth);
  const collapsed = effectiveLayout.isCollapsed;
  const visible = useMemo(() => {
    const listed = agents.filter((agent) => !agent.settings.hiddenFromSidebar);
    const needle = query.trim().toLowerCase();
    if (!needle) return listed;
    return listed.filter((agent) => {
      return (
        agent.profile.name.toLowerCase().includes(needle) ||
        agent.profile.description.toLowerCase().includes(needle) ||
        agent.profile.tags?.some((tag) => tag.toLowerCase().includes(needle))
      );
    });
  }, [query, agents]);
  const visibleWorks = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return [...works];
    return works.filter((work) => {
      return (
        work.name.toLowerCase().includes(needle) ||
        work.description.toLowerCase().includes(needle) ||
        (work.preview ?? "").toLowerCase().includes(needle)
      );
    });
  }, [query, works]);
  const workMemberIds = (workId: string) => agents
    .filter((agent) => Boolean(agent.roomMemberships?.[workId]?.binding))
    .map((agent) => agent.profile.id);

  const projection = projectSidebarAgents(visible, organization);
  // Nunu 与 NunuBar 合并成一条按最近动态排序的列表（对齐 Grok Bot 的会话列表）。
  const mergedRows = useMemo(() => {
    const rows: ({ kind: "agent"; agent: AgentView } | { kind: "work"; work: WorkListItem })[] = [
      ...projection.unassigned.map((agent) => ({ kind: "agent" as const, agent })),
      ...visibleWorks.map((work) => ({ kind: "work" as const, work }))
    ];
    return rows.sort((a, b) =>
      (b.kind === "agent" ? b.agent.runtime.lastActivityAt : b.work.lastActivityAt) -
      (a.kind === "agent" ? a.agent.runtime.lastActivityAt : a.work.lastActivityAt));
  }, [projection.unassigned, visibleWorks]);
  const section = organization.sections.find((item) => item.id === menu?.sectionId);
  const select = (action: () => void) => () => { closeMenu(); action(); };
  let items: SidebarMenuItem[] = [];
  if (menu?.agentId) {
    const id = menu.agentId;
    items = menu.view === "groups" ? [
      { label: t("Back"), icon: "chevron-left", onSelect: () => setMenu({ ...menu, view: undefined }) },
      ...organization.sections.map((group) => ({ label: group.name, icon: "folder" as const, disabled: busy, onSelect: select(() => void commit(assignSidebarAgent(organization, id, group.id))) })),
      { label: t("Unassigned"), icon: "sidebar", disabled: busy, onSelect: select(() => void commit(assignSidebarAgent(organization, id, UNASSIGNED_SECTION))) },
      { label: t("New group…"), icon: "plus", separator: true, disabled: busy, onSelect: select(() => { setNotice(""); setGroupDialog({ agentId: id, name: "" }); }) }
    ] : [
      { label: organization.pinnedAgentIds.includes(id) ? t("Unpin") : t("Pin"), icon: "pin", disabled: busy, onSelect: select(() => void commit(toggleSidebarPin(organization, id))) },
      { label: organization.sections.length ? t("Move to group") : t("Move to new group"), icon: "folder", disabled: busy, onSelect: () => {
        if (organization.sections.length) setMenu({ ...menu, view: "groups" });
        else { closeMenu(); setNotice(""); setGroupDialog({ agentId: id, name: "" }); }
      } },
      { label: t("Edit profile"), icon: "edit", separator: true, onSelect: select(() => onEditAgent(id)) },
      { label: t("Copy Agent ID"), icon: "copy", onSelect: select(() => {
        void navigator.clipboard.writeText(id).catch(() => setNotice(t("Could not copy Agent ID.")));
      }) }
    ];
  } else if (section) {
    const index = organization.sections.indexOf(section);
    const move = (offset: number) => {
      const sections = [...organization.sections];
      [sections[index], sections[index + offset]] = [sections[index + offset], sections[index]];
      void commit({ ...organization, sections });
    };
    items = [
      { label: t("Rename group…"), icon: "edit", disabled: busy, onSelect: select(() => { setNotice(""); setGroupDialog({ sectionId: section.id, name: section.name }); }) },
      { label: t("Move up"), icon: "arrow-up", disabled: busy || index === 0, onSelect: select(() => move(-1)) },
      { label: t("Move down"), icon: "arrow-down", disabled: busy || index === organization.sections.length - 1, onSelect: select(() => move(1)) },
      { label: t("Ungroup agents"), icon: "ungroup", separator: true, disabled: busy, onSelect: select(() => void commit(removeSidebarSection(organization, section.id))) }
    ];
  }
  const renderAgent = ({ profile, runtime }: AgentView, pinned = false) => <button
    className={["sand-agent-item", pinned ? "is-pinned" : ""].filter(Boolean).join(" ")}
    data-active={profile.id === activeId || undefined} data-agent-drop-pin-before={pinned ? profile.id : undefined}
    onPointerDown={(event) => { if (!busy) agentDrag.start(event, profile.id); }} onClickCapture={agentDrag.onClickCapture}
    onContextMenu={(event) => showMenu(event, { agentId: profile.id })} aria-haspopup="menu"
    key={profile.id} onDragStart={(event) => event.preventDefault()} onClick={() => onOpen(profile.id)} title={profile.name} type="button">
    <span className="sand-agent-item__avatar"><AgentAvatar agentId={profile.id} color={profile.avatarColor} shape={profile.avatarShape}
      material={profile.avatarMaterial}
      size={collapsed ? 40 : pinned ? 52 : 34} state={runtime.status === "running" ? "working" : "idle"} />
      {runtime.status === "running" ? <span className="sand-status-dot" /> : null}
    </span>
    <span className="sand-agent-item__body"><strong className="sand-agent-item__name">{profile.name}</strong>
      <span className="sand-agent-item__preview">{previews[profile.id] || profile.description || t("New Agent")}</span></span>
    <span className="sand-agent-item__trailing"><span>{relativeTime(runtime.lastActivityAt)}</span>
      {runtime.status === "running" ? <span className="sand-agent-item__activity">{t("Working")}</span> : null}</span>
  </button>;

  // NunuBar 行复用 agent 行的视觉语言，头像换成成员拼贴的群头像。
  const renderWorkRow = (work: WorkListItem) => {
    const memberIds = workMemberIds(work.id);
    return <button
      className="sand-agent-item"
      data-active={work.id === activeWorkId || undefined}
      data-agent-drop-work={work.id}
      key={work.id}
      onClick={() => onOpenWork(work.id)}
      title={work.name}
      type="button"
    >
      <span className="sand-agent-item__avatar">
        {memberIds.length
          ? <WorkGroupAvatar memberIds={memberIds} agents={agents} size={collapsed ? 40 : 34} />
          : <span className="sand-work-item__mark" style={collapsed ? { width: 40, height: 40 } : undefined}>{work.name.slice(0, 1).toUpperCase()}</span>}
      </span>
      <span className="sand-agent-item__body"><strong className="sand-agent-item__name">{work.name}</strong>
        <span className="sand-agent-item__preview">{work.preview || work.description || t("New Work")}</span></span>
      <span className="sand-agent-item__trailing"><span>{relativeTime(work.lastActivityAt)}</span></span>
    </button>;
  };

  return (
    <aside
      aria-label={t("Agents")}
      className={[
        "sand-agents-sidebar",
        collapsed ? "is-collapsed" : "",
        layout.isDragging ? "is-resizing" : ""
      ].filter(Boolean).join(" ")}
      data-sidebar-collapsed={collapsed || undefined}
      style={{ width: effectiveLayout.width }}
    >
      <header className="sand-agents-sidebar__header">
        {collapsed ? null : (
          <div className="sand-agents-sidebar__new-actions">
            <SandIconButton
              aria-expanded={searchOpen || undefined}
              aria-label={t("Search")}
              className="sand-agents-sidebar__search-toggle"
              icon="search"
              label={t("Search")}
              onClick={() => setSearchOpen((open) => !open)}
              shape="circle"
              size="sm"
              title={t("Search")}
            />
            <SandIconButton
              aria-expanded={newMenu ? true : undefined}
              aria-haspopup="menu"
              aria-label={t("New")}
              className="sand-agents-sidebar__new"
              data-new-menu-toggle=""
              icon="plus"
              label={t("New")}
              onClick={openNewMenu}
              shape="circle"
              size="sm"
              title={t("New agent")}
            />
          </div>
        )}
      </header>
      {!collapsed && (searchOpen || query) ? (
        <label className="sand-agents-sidebar__search">
          <SandIcon name="search" size="sm" />
          <input
            onChange={(event) => setQuery(event.target.value)}
            placeholder={t("Search")}
            ref={searchRef}
            type="search"
            value={query}
          />
        </label>
      ) : null}
      <div className="sand-sidebar-pin-drop" data-agent-drop-section={PINNED_SECTION} aria-label={t("拖到此处置顶")} title={t("拖到此处置顶")}>
        <span>{t("拖到此处置顶")}</span>
      </div>
      <nav aria-label={t("Agent list")} className="sand-agents-list" data-sidebar-collapsed={collapsed || undefined}>
        {projection.pinned.length > 0 ? <div className="sand-agents-pinned" aria-label={t("Pinned Agents")} data-agent-drop-section={PINNED_SECTION}>
          {projection.pinned.map((agent) => renderAgent(agent, true))}
        </div> : null}
        {projection.sections.filter((group) => !query.trim() || group.agents.length > 0).map((group) => <section className="sand-sidebar-group" key={group.id} data-agent-drop-section={group.id}>
          {!collapsed ? <div className="sand-sidebar-group__heading" onContextMenu={(event) => showMenu(event, { sectionId: group.id })}>
            <button type="button" aria-expanded={!group.isCollapsed || !!query.trim()} disabled={busy} onClick={() => void commit({ ...organization, sections: organization.sections.map((item) => item.id === group.id ? { ...item, isCollapsed: !item.isCollapsed } : item) })}>
              <SandIcon name="chevron-right" size={10} /><span>{group.name}</span><small>{group.agents.length}</small>
            </button>
            <button className="sand-sidebar-group__more" type="button" aria-label={t("Actions for {name}", { name: group.name })} onClick={(event) => showMenu(event, { sectionId: group.id })}>···</button>
          </div> : null}
          {collapsed || !group.isCollapsed || !!query.trim() ? <div className="sand-agents-section__rows">{group.agents.map((agent) => renderAgent(agent))}
            {!group.agents.length && !collapsed ? <div className="sand-agents-section__empty">{t("Drag an Agent here")}</div> : null}</div> : null}
        </section>)}
        <section className="sand-sidebar-group" data-agent-drop-section={UNASSIGNED_SECTION}>
          {!collapsed && organization.sections.length > 0 && mergedRows.length > 0 ? <div className="sand-agents-list__label"><span>{t("Unassigned")}</span><span>{mergedRows.length}</span></div> : null}
          <div className="sand-agents-section__rows">
            {mergedRows.map((row) => row.kind === "agent" ? renderAgent(row.agent) : renderWorkRow(row.work))}
          </div>
        </section>
        {mergedRows.length === 0 && projection.pinned.length === 0 ? <div className="sand-agents-section__empty">{agents.length === 0 && works.length === 0 ? t("No agents yet") : t("No matching agents")}</div> : null}
        {notice && !groupDialog ? <p className="sand-sidebar-notice" role="alert">{t(notice)}</p> : null}
      </nav>
      <footer className="sand-agents-sidebar__footer">
        {collapsed ? (
          <SandIconButton
            aria-expanded={newMenu ? true : undefined}
            aria-haspopup="menu"
            aria-label={t("New")}
            className="sand-agents-sidebar__new"
            data-new-menu-toggle=""
            icon="plus"
            label={t("New")}
            onClick={openNewMenu}
            shape="circle"
            size="sm"
            title={t("New agent")}
          />
        ) : null}
        <SandIconButton
          aria-label={t("Settings")}
          className="sand-agents-sidebar__settings"
          icon="sliders"
          label={t("Settings")}
          onClick={onOpenSettings}
          shape="circle"
          size="sm"
          title={t("Settings")}
        />
      </footer>
      {menu && items.length ? <SidebarMenu point={menu.point} items={items} onClose={closeMenu} /> : null}
      {newMenu ? <SidebarNewMenu
        anchor={newMenu}
        agents={agents.filter((agent) => !agent.settings.hiddenFromSidebar)}
        works={visibleWorks.map((work) => ({ ...work, memberIds: workMemberIds(work.id) }))}
        activeId={activeId}
        activeWorkId={activeWorkId}
        onNewAgent={onNewAgent}
        onNewWork={onNewWork}
        onOpen={onOpen}
        onOpenWork={onOpenWork}
        onClose={() => setNewMenu(null)}
      /> : null}
      {groupDialog ? <SidebarNameDialog key={groupDialog.sectionId ?? "new"} title={groupDialog.sectionId ? t("Rename group") : t("New group")}
        initialValue={groupDialog.name} busy={busy} error={t(notice)} onClose={() => setGroupDialog(null)} onSave={(name) => {
          const id = groupDialog.sectionId ?? crypto.randomUUID();
          let next = groupDialog.sectionId
            ? { ...organization, sections: organization.sections.map((item) => item.id === id ? { ...item, name } : item) }
            : { ...organization, sections: [...organization.sections, { id, name, agentIds: [], isCollapsed: false }] };
          if (groupDialog.agentId) next = assignSidebarAgent(next, groupDialog.agentId, id);
          void commit(next).then((saved) => { if (saved) setGroupDialog(null); });
        }} /> : null}
      <SidebarResizeHandle
        onResize={(width) => onLayoutChange(applySidebarDrag(layoutRef.current, width))}
        onResizeEnd={() => onLayoutChange(settleSidebarLayout(layoutRef.current))}
      />
    </aside>
  );
}
