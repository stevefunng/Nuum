import { ExecutionApproval } from "./execution-approval";
import { t } from "../i18n";
import type { AgentView, ViewBlock } from "@nuum/protocol";
import { Fragment, useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { SandIcon, SandIconButton } from "../kit/sand-kit-primitives";
import { AutoTextarea } from "../kit/auto-textarea";
import { AGENT_AVATAR_MATERIAL_HIDDEN, AgentAvatar, rollAgentAvatar } from "./agent-avatar";
import { nunuActivityState } from "./nunu-state";
import { AGENT_ROLE_TEMPLATES } from "./agent-templates";

export interface PendingTool {
  toolCallId: string;
  name: string;
  arguments: Record<string, unknown>;
  action: "read-file" | "list-directory" | "write-file" | "run-command" | "network";
  target: string;
  justification?: string; allowAlways?: boolean; details?: string;
}

export interface ConversationWorkspaceProps {
  agent: AgentView | null;
  agents?: readonly AgentView[];
  blocks: readonly ViewBlock[];
  blockTimestamps?: Readonly<Record<string, number>>;
  autoFocusInput?: boolean;
  creatingAgent?: boolean;
  canCancelCreate?: boolean;
  creationError?: string | null;
  pendingTool?: PendingTool | null;
  draft: string;
  onDraftChange(value: string): void;
  onSubmit(): void;
  onCancel(): void;
  onCancelCreate(): void;
  onCreateAgent(profile: {
    name: string;
    description: string;
    avatarColor: string;
    avatarShape: string;
    avatarMaterial: string;
  }): void;
  onApprove(resolution: "always" | "once" | "deny" | "never"): void | Promise<void>;
  /** 回答提问卡片：选项值原样成为一条用户消息并唤醒对方。 */
  onAnswerWidget?(messageId: string, value: string): void;
  onOpenProfile?(): void;
  notice?: string | null;
}

function toolLabel(name: string): string {
  const normalized = name.toLowerCase();
  if (normalized === "bash" || normalized === "shell") return t("Bash");
  if (normalized === "external_operation") return t("Local operation");
  if (normalized === "request_network") return t("Network access");
  if (normalized === "read") return t("Read");
  if (normalized === "ls") return t("List");
  if (normalized === "write") return t("Write");
  return name.replace(/([a-z])([A-Z])/g, "$1 $2");
}

function toolStatus(status: "pending" | "ok" | "error"): string {
  if (status === "pending") return t("执行中");
  if (status === "error") return t("失败");
  return t("已完成");
}

function ToolActivity({ tool }: { tool: Extract<ViewBlock, { type: "assistant" }>["tools"][number] }) {
  return (
    <details className="sand-tool-activity" data-status={tool.status}>
      <summary>
        <span className="sand-tool-activity__pulse" />
        <span>{toolLabel(tool.name)} {toolStatus(tool.status)}</span>
        <span className="sand-tool-activity__chevron" />
      </summary>
      <div className="sand-tool-activity__detail">
        <section>
          <span>{t("Arguments")}</span>
          <pre>{JSON.stringify(tool.arguments, null, 2)}</pre>
        </section>
        {tool.output !== undefined ? (
          <section>
            <span>{t("Output")}</span>
            <pre>{tool.output || t("(no output)")}</pre>
          </section>
        ) : null}
      </div>
    </details>
  );
}

/** 主对话只显示工作状态；thinking 原文和工具详情都不主动展开。 */
function AssistantBlock({ block }: { block: Extract<ViewBlock, { type: "assistant" }> }) {
  if (!block.live && block.tools.length === 0) return null;
  return (
    <article className="sand-transcript-row sand-transcript-row--activity">
      <div className="sand-assistant-stack">
        {block.live && block.tools.length === 0 ? (
          <div className="sand-thinking-status">
            <span className="sand-thinking-status__pulse" />
            <span>{t("思考中")}</span>
          </div>
        ) : null}
        {block.tools.map((tool) => <ToolActivity key={tool.id} tool={tool} />)}
      </div>
    </article>
  );
}

/** SendMessage 产出的真正助手气泡。 */
function MessageBlock({
  block,
  answered,
  onAnswer
}: {
  block: Extract<ViewBlock, { type: "message" }>;
  answered: string | null;
  onAnswer?(value: string): void;
}) {
  const { payload } = block;
  // widget 新旧两种载荷共用 type:"widget"，TS 分不清 —— 在这里一次收窄。
  const legacyWidget = payload.type === "widget" && typeof payload.widget === "string"
    ? { name: payload.widget, props: "props" in payload ? payload.props ?? {} : {} }
    : null;
  const widgetCard = payload.type === "widget" && typeof payload.widget !== "string" ? payload.widget : null;
  return (
    <article className="sand-transcript-row">
      <div className="sand-message sand-message--assistant">
        <div className="sand-message-prose">
          {payload.type === "text" ? (
            <>
              <ReactMarkdown remarkPlugins={[remarkGfm]}>{payload.content}</ReactMarkdown>
              {payload.images?.map((image) => (
                <img
                  alt={image.alt ?? ""}
                  className="sand-message-image"
                  key={image.path}
                  src={`file://${image.path}`}
                />
              ))}
            </>
          ) : payload.type === "attachment" ? (
            <>
              <a href={`file://${payload.path}`}>{payload.path}</a>
              {payload.caption ? <p>{payload.caption}</p> : null}
            </>
          ) : legacyWidget ? (
            // 旧版 widget 是 name+props 透传；真实渲染仍是下版的事。
            <pre>{`${legacyWidget.name} ${JSON.stringify(legacyWidget.props)}`}</pre>
          ) : widgetCard ? (
            <WidgetCard
              answered={answered}
              blockId={block.id}
              onAnswer={onAnswer}
              widget={widgetCard}
            />
          ) : null}
        </div>
      </div>
    </article>
  );
}

/** 提问卡片：选项点选后原样成为一条用户消息；已回答的卡片定格在选中项上。 */
function WidgetCard({
  blockId,
  widget,
  answered,
  onAnswer
}: {
  blockId: string;
  widget: { prompt: string; helpText?: string; options: { label: string; value?: string; description?: string; style?: "default" | "primary" | "danger" }[]; allowCustom?: boolean };
  answered: string | null;
  onAnswer?(value: string): void;
}) {
  const [custom, setCustom] = useState("");
  const resolved = answered != null;
  const pick = (option: { label: string; value?: string }): void => onAnswer?.(option.value ?? option.label);
  return (
    <div className="sand-widget-card" data-resolved={resolved || undefined} key={blockId}>
      <p className="sand-widget-card__prompt">{widget.prompt}</p>
      {widget.helpText ? <p className="sand-widget-card__help">{widget.helpText}</p> : null}
      <div className="sand-widget-card__options">
        {widget.options.map((option) => {
          const value = option.value ?? option.label;
          const chosen = resolved && answered === value;
          return (
            <button
              className="sand-widget-card__option"
              data-style={option.style}
              data-chosen={chosen || undefined}
              disabled={resolved || !onAnswer}
              key={value}
              onClick={() => pick(option)}
              type="button"
            >
              <span>{option.label}</span>
              {option.description ? <small>{option.description}</small> : null}
            </button>
          );
        })}
      </div>
      {widget.allowCustom && !resolved ? (
        <form
          className="sand-widget-card__custom"
          onSubmit={(event) => {
            event.preventDefault();
            if (custom.trim()) onAnswer?.(custom.trim());
          }}
        >
          <input
            onChange={(event) => setCustom(event.target.value)}
            placeholder={t("Or type your own answer…")}
            value={custom}
          />
          <button disabled={!custom.trim()} type="submit">{t("Send")}</button>
        </form>
      ) : null}
      {resolved ? <p className="sand-widget-card__resolved">{t("Your answer: {answer}", { answer: answered })}</p> : null}
    </div>
  );
}

/** 系统条：别的 agent 的唤醒、自改人格、上文已压缩。 */
function NoticeBlock({ block }: { block: Extract<ViewBlock, { type: "notice" }> }) {
  return (
    <article className="sand-transcript-row">
      <div className="sand-transcript-notice" data-kind={block.kind}>
        {block.kind === "profile" ? (() => {
          const renamed = /^This agent changed name to "(.*)"\.$/.exec(block.text);
          return renamed ? t('This Nunu changed name to "{name}".', { name: renamed[1] }) : t("This Nunu changed its profile.");
        })() : block.kind === "wake" && block.text.startsWith("Participated in room: ")
          ? t("Participated in room: {name}", { name: block.text.slice("Participated in room: ".length) }) : t(block.text)}
      </div>
    </article>
  );
}

const TIME_GROUP_GAP = 5 * 60 * 1000;

function formatTranscriptTime(timestamp: number): string {
  const date = new Date(timestamp);
  const now = new Date();
  const time = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(date);
  const day = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  if (day === today) return t("Today {time}", { time });
  if (day === today - 86_400_000) return t("Yesterday {time}", { time });
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(date);
}

function showTimeBefore(ids: readonly string[], index: number, timestamps: Readonly<Record<string, number>>): number | null {
  const timestamp = timestamps[ids[index] ?? ""];
  if (typeof timestamp !== "number" || !Number.isFinite(timestamp)) return null;
  if (index === 0) return timestamp;
  const previous = timestamps[ids[index - 1] ?? ""];
  if (typeof previous !== "number" || !Number.isFinite(previous) || timestamp - previous >= TIME_GROUP_GAP || new Date(timestamp).toDateString() !== new Date(previous).toDateString()) return timestamp;
  return null;
}

function TranscriptTimeSeparator({ timestamp }: { timestamp: number }) {
  return <div className="sand-transcript-time-separator" role="separator">{formatTranscriptTime(timestamp)}</div>;
}

function PeerBlock({ block, peer, onOpen }: {
  block: Extract<ViewBlock, { type: "peer" }>;
  peer: AgentView | null;
  onOpen(): void;
}) {
  const outbound = block.direction === "outbound";
  const peerName = peer?.profile.name ?? block.agentName;
  return (
    <article className="sand-transcript-row sand-transcript-row--peer" data-direction={block.direction}>
      <button className="sand-peer-summary" onClick={onOpen} type="button">
        <span>{outbound ? t("Sent a message to") : t("Message from")}</span>
        <AgentAvatar agentId={block.agentId} color={peer?.profile.avatarColor} shape={peer?.profile.avatarShape} material={peer?.profile.avatarMaterial} size={20} state={outbound ? "sending" : "receiving"} />
        <strong>{peerName}</strong>
        {block.priority ? <span className="sand-peer-message__priority">{t("Priority")}</span> : null}
        <SandIcon name="chevron-right" size={12} />
      </button>
    </article>
  );
}

function PeerConversation({ agent, peer, blocks, timestamps, onClose }: {
  agent: AgentView;
  peer: AgentView | null;
  blocks: readonly Extract<ViewBlock, { type: "peer" }>[];
  timestamps: Readonly<Record<string, number>>;
  onClose(): void;
}) {
  const peerId = blocks[0]?.agentId ?? peer?.profile.id ?? "peer";
  const peerName = peer?.profile.name ?? blocks[0]?.agentName ?? t("Agent");
  const blockIds = blocks.map((block) => block.id);

  const timeline = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (timeline.current) timeline.current.scrollTop = timeline.current.scrollHeight;
  }, [blocks.length]);
  return (
    <div className="sand-peer-sheet" role="dialog" aria-modal="true" aria-label={t("Conversation between {first} and {second}", { first: agent.profile.name, second: peerName })} onClick={onClose}>
      <div className="sand-peer-sheet__surface" onClick={(event) => event.stopPropagation()}>
        <header>
          <div className="sand-peer-sheet__pair">
            <AgentAvatar agentId={agent.profile.id} color={agent.profile.avatarColor} shape={agent.profile.avatarShape} material={agent.profile.avatarMaterial} size={30} />
            <strong>{agent.profile.name}</strong>
            <span aria-hidden="true">⇄</span>
            <AgentAvatar agentId={peerId} color={peer?.profile.avatarColor} shape={peer?.profile.avatarShape} material={peer?.profile.avatarMaterial} size={30} />
            <strong>{peerName}</strong>
          </div>
        </header>
        <div className="sand-peer-sheet__timeline" ref={timeline} role="log">
          {blocks.map((block, index) => {
            const outbound = block.direction === "outbound";
            const speaker = outbound ? agent : peer;
            const speakerId = outbound ? agent.profile.id : peerId;
            const speakerName = outbound ? agent.profile.name : peerName;
            const timestamp = showTimeBefore(blockIds, index, timestamps);
            return <Fragment key={block.id}>
              {timestamp == null ? null : <TranscriptTimeSeparator timestamp={timestamp} />}
              <article className="sand-peer-turn">
                <AgentAvatar agentId={speakerId} color={speaker?.profile.avatarColor} shape={speaker?.profile.avatarShape} material={speaker?.profile.avatarMaterial} size={28} />
                <div>
                  <span>{speakerName}</span>
                  <div className="sand-message sand-message--assistant"><div className="sand-message-prose"><p>{block.text}</p></div></div>
                </div>
              </article>
            </Fragment>;
          })}
        </div>
        <footer><button onClick={onClose} type="button">{t("Close chat")}</button></footer>
      </div>
    </div>
  );
}

function AgentCreation({
  canCancel,
  error,
  onCancel,
  onCreate
}: {
  canCancel: boolean;
  error?: string | null;
  onCancel(): void;
  onCreate(profile: { name: string; description: string; avatarColor: string; avatarShape: string; avatarMaterial: string }): void;
}) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  // 形象在创建时随机定下（换一个可重摇），提交后写进 profile 永久绑定。
  const [avatar, setAvatar] = useState(rollAgentAvatar);
  const submit = () => {
    if (!name.trim()) return;
    onCreate({
      name: name.trim(),
      description: description.trim(),
      avatarColor: avatar.color,
      avatarShape: avatar.shape,
      avatarMaterial: avatar.material
    });
  };
  return (
    <div className="sand-agent-create">
      <div className="sand-agent-create__hero">
        <div className="sand-agent-create__preview">
          <AgentAvatar
            agentId={name || "new-agent"}
            color={avatar.color}
            shape={avatar.shape}
            material={avatar.material}
            size={112}
            fullBody
            state="happy"
          />
          {avatar.material === AGENT_AVATAR_MATERIAL_HIDDEN ? <span className="sand-agent-create__hidden">{t("Hidden edition")}</span> : null}
        </div>
        <div>
          <span className="sand-agent-create__eyebrow">{t("A teammate with its own context")}</span>
          <h1>{t("Create an Agent")}</h1>
          <p>{t("Give it an ongoing job. It gets its own conversation, memory, and workspace.")}</p>
          <button className="sand-agent-create__shuffle" onClick={() => setAvatar(rollAgentAvatar())} type="button">
            <SandIcon name="shuffle" size={14} />
            {t("Shuffle")}
          </button>
        </div>
      </div>
      <div className="sand-agent-create__editor">
        <label>
          <span>{t("Name")}</span>
          <input autoFocus onChange={(event) => setName(event.target.value)} placeholder={t("e.g. Release scout")} value={name} />
        </label>
        <label>
          <span>{t("What should this Agent do?")}</span>
          <AutoTextarea
            onChange={(event) => setDescription(event.target.value)}
            placeholder={t("A standing role helps other Agents know when to message it.")}
            value={description}
          />
        </label>
      </div>
      <div className="sand-agent-create__suggestions">
        <span>{t("Or start with a role")}</span>
        <div>
          {AGENT_ROLE_TEMPLATES.map((template) => (
            <button
              key={t(template.name)}
              onClick={() => {
                setName(t(template.name));
                setDescription(t(template.description));
              }}
              type="button"
            >
              <strong>{t(template.name)}</strong>
              <span>{t(template.description)}</span>
            </button>
          ))}
        </div>
      </div>
      <div className="sand-agent-create__actions">
        {error ? <span className="sand-agent-create__error">{t(error)}</span> : null}
        {canCancel ? <button className="sand-agent-create__cancel" onClick={onCancel} type="button">{t("Cancel")}</button> : null}
        <button className="sand-agent-create__submit" disabled={!name.trim()} onClick={submit} type="button">{t("Create Agent")}</button>
      </div>
    </div>
  );
}

export function ConversationWorkspace({
  agent,
  agents = [],
  blocks,
  blockTimestamps = {},
  autoFocusInput = false,
  creatingAgent = false,
  canCancelCreate = false,
  creationError,
  pendingTool,
  draft,
  onDraftChange,
  onSubmit,
  onCancel,
  onCancelCreate,
  onCreateAgent,
  onApprove,
  onAnswerWidget,
  onOpenProfile,
  notice
}: ConversationWorkspaceProps) {
  const empty = agent == null || blocks.length === 0;
  // 提问卡片的已回答状态：user 块的 widgetAnswerTo 指回被回答的 message 块。
  const widgetAnswers = new Map(
    blocks
      .filter((block): block is Extract<ViewBlock, { type: "user" }> =>
        block.type === "user" && block.widgetAnswerTo != null)
      .map((block) => [block.widgetAnswerTo as string, block.text])
  );
  const transcriptRef = useRef<HTMLDivElement>(null);
  const promptRef = useRef<HTMLTextAreaElement>(null);
  const composingRef = useRef(false);
  const [peerSheetAgentId, setPeerSheetAgentId] = useState<string | null>(null);
  const peerBlocks = peerSheetAgentId == null ? [] : blocks.filter(
    (block): block is Extract<ViewBlock, { type: "peer" }> => block.type === "peer" && block.agentId === peerSheetAgentId
  );
  const peerAgent = agents.find((item) => item.profile.id === peerSheetAgentId) ?? null;
  const blockIds = blocks.map((block) => block.id);
  const liveTools = blocks.some(block => block.type === "assistant" && block.live && block.tools.some(tool => tool.status === "pending"));
  const avatarState = nunuActivityState(agent?.runtime.status, Boolean(pendingTool), liveTools);
  const activityLabel = avatarState === "waiting" ? t("Waiting for approval") : avatarState === "thinking" ? t("思考中") : t("Working");

  useEffect(() => setPeerSheetAgentId(null), [agent?.profile.id]);

  useEffect(() => {
    const field = promptRef.current;
    if (!field) return;
    field.style.height = "auto";
    field.style.height = `${Math.min(96, field.scrollHeight)}px`;
  }, [draft, creatingAgent]);

  useEffect(() => {
    if (creatingAgent) return;
    const transcript = transcriptRef.current;
    if (!transcript) return;
    transcript.scrollTo({ top: transcript.scrollHeight, behavior: "smooth" });
  }, [blocks.length, creatingAgent]);

  useEffect(() => {
    if (autoFocusInput) promptRef.current?.focus();
  }, [agent?.profile.id, autoFocusInput]);

  return (
    <section className="sand-chat-stage">
      <header className="sand-chat-header">
        {agent ? (
          <button className="sand-chat-header__identity" disabled={!onOpenProfile} onClick={onOpenProfile} type="button" aria-label={t("Open {name} profile", { name: agent.profile.name })}>
            <span className="sand-chat-header__avatar">
              <AgentAvatar
                agentId={agent.profile.id}
                color={agent.profile.avatarColor}
                shape={agent.profile.avatarShape}
                material={agent.profile.avatarMaterial}
                size={28}
                state={avatarState}
              />
            </span>
            <span id="sand-conversation-heading">{agent.profile.name}</span>
            {agent.runtime.status === "running" ? <small>{activityLabel}</small> : null}
          </button>
        ) : (
          <div className="sand-chat-header__identity sand-chat-header__identity--blank" />
        )}
      </header>
      {creatingAgent ? (
        <AgentCreation canCancel={canCancelCreate} error={creationError} onCancel={onCancelCreate} onCreate={onCreateAgent} />
      ) : <>
      <div aria-label={t("Conversation transcript")} className="sand-virtual-transcript" ref={transcriptRef} role="log">
        {empty ? (
          <div className="sand-empty sand-empty--welcome">
            <strong className="sand-empty__mark">Nuum</strong>
            <span>{t("Ask anything, or drop a file.")}</span>
          </div>
        ) : null}
        {blocks.map((block, index) => {
          const timestamp = showTimeBefore(blockIds, index, blockTimestamps);
          return <Fragment key={block.id}>
          {timestamp == null ? null : <TranscriptTimeSeparator timestamp={timestamp} />}
          {block.type === "user" ? (
            <article className="sand-transcript-row">
              <div className="sand-message sand-message--user">
                <div className="sand-message-prose">
                  <p>{block.text}</p>
                </div>
              </div>
            </article>
          ) : block.type === "message" ? (
            <MessageBlock
              answered={widgetAnswers.get(block.id) ?? null}
              block={block}
              onAnswer={onAnswerWidget ? (value) => onAnswerWidget(block.id, value) : undefined}
            />
          ) : block.type === "notice" ? (
            <NoticeBlock block={block} />
          ) : block.type === "peer" ? (
            <PeerBlock block={block} peer={agents.find((item) => item.profile.id === block.agentId) ?? null} onOpen={() => setPeerSheetAgentId(block.agentId)} />
          ) : (
            <AssistantBlock block={block} />
          )}
          </Fragment>;
        })}
      </div>
      <div className="sand-chat-input-dock">
        {agent && agent.runtime.status === "running" ? (
          <div className="sand-chat-working" role="status">
            <AgentAvatar
              agentId={agent.profile.id}
              color={agent.profile.avatarColor}
              shape={agent.profile.avatarShape}
              material={agent.profile.avatarMaterial}
              size={40}
              fullBody
              state={avatarState}
            />
            <span className="sand-chat-working__label">{activityLabel}</span>
          </div>
        ) : null}
        {pendingTool ? <ExecutionApproval action={pendingTool.action} justification={pendingTool.justification} allowAlways={pendingTool.allowAlways} details={pendingTool.details} target={pendingTool.target} onDecide={async resolution => { await onApprove(resolution); }} /> : null}
        {notice ? <div className="sand-prompt-attachment-notice">{t(notice)}</div> : null}
        <form
          className="sand-prompt-form"
          onSubmit={(event: FormEvent) => {
            event.preventDefault();
            onSubmit();
          }}
        >
          <div className="sand-prompt-shell">
            <textarea
              className="sand-prompt-field"
              rows={1}
              ref={promptRef}
              onChange={(event) => onDraftChange(event.target.value)}
              onCompositionEnd={() => {
                composingRef.current = false;
              }}
              onCompositionStart={() => {
                composingRef.current = true;
              }}
              onKeyDown={(event) => {
                if (event.key === "Enter" && !event.shiftKey) {
                  // Electron/Chromium 在输入法确认候选时也会发 Enter keydown。
                  // ref 覆盖 React composition 生命周期，isComposing / 229 覆盖浏览器原生状态。
                  const nativeEvent = event.nativeEvent;
                  if (composingRef.current || nativeEvent.isComposing || nativeEvent.keyCode === 229) return;
                  event.preventDefault();
                  onSubmit();
                }
              }}
              placeholder={agent ? t("Message {name}", { name: agent.profile.name }) : t("Ask anything, or drop a file.")}
              value={draft}
            />
            <div className="sand-prompt-actions-row">
              <button className="sand-prompt-attach" disabled type="button" aria-label={t("Attach file")}>
                <SandIcon name="attach" size={16} />
              </button>
              {agent?.runtime.status === "running" ? (
                <button className="sand-prompt-send" onClick={onCancel} type="button" aria-label={t("Stop")}>
                  <SandIcon name="stop" />
                </button>
              ) : (
                <button className="sand-prompt-send" disabled={!draft.trim()} type="submit" aria-label={t("Send message")}>
                  <SandIcon name="arrow-up" size={16} />
                </button>
              )}
            </div>
          </div>
        </form>
      </div>
      {agent && peerSheetAgentId && peerBlocks.length ? (
        <PeerConversation agent={agent} peer={peerAgent} blocks={peerBlocks} timestamps={blockTimestamps} onClose={() => setPeerSheetAgentId(null)} />
      ) : null}
      </>}
    </section>
  );
}

export function SettingsOverlay({
  open,
  section,
  onSection,
  onClose,
  children
}: {
  open: boolean;
  section: "general" | "models";
  onSection(section: "general" | "models"): void;
  onClose(): void;
  children: ReactNode;
}): ReactNode {
  if (!open) return null;
  const headingId = `sand-settings-panel-${section}-heading`;
  return (
    <div className="sand-settings-overlay" onClick={onClose} role="presentation">
      <div
        aria-labelledby={headingId}
        className="sand-settings-dialog"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="sand-settings-layout">
          <nav aria-label={t("Settings sections")} className="sand-settings-nav">
            <button
              aria-current={section === "general" ? "page" : undefined}
              className="sand-settings-nav__item"
              data-active={section === "general" || undefined}
              onClick={() => onSection("general")}
              type="button"
            >
              <SandIcon name="settings-gear" size="sm" />
              <span>{t("General")}</span>
            </button>
            <button
              aria-current={section === "models" ? "page" : undefined}
              className="sand-settings-nav__item"
              data-active={section === "models" || undefined}
              onClick={() => onSection("models")}
              type="button"
            >
              <SandIcon name="sliders" size="sm" />
              <span>{t("Models")}</span>
            </button>
          </nav>
          <section className="sand-settings-panel">
            <SandIconButton
              aria-label={t("Close")}
              className="sand-settings-panel__close"
              icon="close"
              label={t("Close")}
              onClick={onClose}
              size="sm"
            />
            <h2 id={headingId}>{section === "general" ? t("General") : t("Models")}</h2>
            <div className="sand-settings-panel__body">{children}</div>
          </section>
        </div>
      </div>
    </div>
  );
}
