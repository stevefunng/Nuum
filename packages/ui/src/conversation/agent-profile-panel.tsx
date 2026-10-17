import { t } from "../i18n";
import type { AgentProfile, AgentUpdateParams } from "@nuum/protocol";
import { useEffect, useId, useRef, useState } from "react";
import { AgentAvatar } from "./agent-avatar";
import { NunuPortrait } from "./nunu-portrait";
import { AGENT_ROLE_TEMPLATES, hasEditedIdentity, markIdentityEdited } from "./agent-templates";
import { SandIconButton } from "../kit/sand-kit-primitives";
import { WorkDialog } from "../workbar/work-dialog";
import "./agent-profile-panel.css";
import { AutoTextarea } from "../kit/auto-textarea";

export type AgentProfilePatch = Pick<AgentUpdateParams, "name" | "tags" | "description">;

// 在不旋转的外层测量指针，避免卡面倾斜改变命中坐标而产生抖动。
function NunuBadge({ profile, onEdit }: { profile: AgentProfile; onEdit(): void }) {
  const ref = useRef<HTMLDivElement>(null);
  const ringId = useId();
  const [reaction, setReaction] = useState(0);
  const frame = useRef(0);
  const reduced = useRef(false);
  const motion = useRef({ x: 0, y: 0, targetX: 0, targetY: 0, sealX: 0, sealY: 0, time: 0 });
  const animate = (time: number) => {
    const node = ref.current;
    if (!node) return;
    const state = motion.current;
    const blend = 1 - Math.exp(-Math.min(time - state.time || 16, 64) / 85);
    const sealBlend = 1 - Math.exp(-Math.min(time - state.time || 16, 64) / 420);
    state.time = time;
    state.sealX += (state.targetX - state.sealX) * sealBlend;
    state.sealY += (state.targetY - state.sealY) * sealBlend;
    node.style.setProperty("--seal-rx", `${-state.sealY * 0.6}deg`);
    node.style.setProperty("--seal-ry", `${state.sealX * 0.6}deg`);
    node.style.setProperty("--seal-angle", `${115 + state.sealX * 2}deg`);
    state.x += (state.targetX - state.x) * blend;
    state.y += (state.targetY - state.y) * blend;
    node.style.setProperty("--badge-rx", `${-state.y * 9}deg`);
    node.style.setProperty("--badge-ry", `${state.x * 9}deg`);
    node.style.setProperty("--badge-gx", `${50 + state.x * 45}%`);
    node.style.setProperty("--badge-gy", `${40 + state.y * 40}%`);
    node.style.setProperty("--badge-sweep", `${50 + state.x * 35 + state.y * 15}%`);
    node.style.setProperty("--badge-angle", `${115 + state.x * 20 - state.y * 12}deg`);
    frame.current = 0;
    if (Math.abs(state.targetX - state.x) + Math.abs(state.targetY - state.y) + Math.abs(state.targetX - state.sealX) + Math.abs(state.targetY - state.sealY) > 0.001) {
      frame.current = requestAnimationFrame(animate);
    }
  };
  const move = (x: number, y: number) => {
    motion.current.targetX = x;
    motion.current.targetY = y;
    if (!frame.current) { motion.current.time = 0; frame.current = requestAnimationFrame(animate); }
  };
  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => {
      reduced.current = query.matches;
      if (query.matches) {
        cancelAnimationFrame(frame.current);
        frame.current = 0;
        motion.current = { x: 0, y: 0, targetX: 0, targetY: 0, sealX: 0, sealY: 0, time: 0 };
        ref.current?.removeAttribute("style");
      }
    };
    sync();
    query.addEventListener("change", sync);
    return () => { query.removeEventListener("change", sync); cancelAnimationFrame(frame.current); };
  }, []);
  const tilt = (event: React.PointerEvent<HTMLDivElement>) => {
    if (reduced.current || event.pointerType === "touch") return;
    const box = event.currentTarget.getBoundingClientRect();
    move(Math.max(-1, Math.min(1, (event.clientX - box.left) / box.width * 2 - 1)),
      Math.max(-1, Math.min(1, (event.clientY - box.top) / box.height * 2 - 1)));
  };
  const reset = () => { if (!reduced.current) move(0, 0); };
  const tags = profile.tags ?? [];
  const created = new Date(profile.createdAt);
  const createdDate = `${created.getFullYear()}/${String(created.getMonth() + 1).padStart(2, "0")}/${String(created.getDate()).padStart(2, "0")}`;
  return <div ref={ref} className="sand-nunu-badge-stage" onPointerMove={tilt} onPointerLeave={reset} onPointerCancel={reset}>
    <div className="sand-nunu-badge">
      <button type="button" className="sand-nunu-badge__edit-surface" aria-label={t("Click to edit profile")} onClick={onEdit} />
      <span className="sand-nunu-badge__seal-space" aria-hidden="true" />
      <strong className="sand-nunu-badge__name">{profile.name}</strong>
      {tags.length > 0 ? <span className="sand-nunu-badge__tags">{tags.map((tag) => <span key={tag}>{tag}</span>)}</span> : null}
      <span className="sand-nunu-badge__desc" data-empty={!profile.description || undefined}>{profile.description || t("What should this Agent do?")}</span>
      <span className="sand-nunu-badge__footer">
        <span className="sand-nunu-badge__created"><span>{t("Created on")}</span><time dateTime={created.toISOString()}>{createdDate}</time></span>
        <svg className="sand-nunu-badge__signature" viewBox="0 0 112 40" role="img" aria-label="Nuum">
          <path d="M5 29 V13 H10 L24 29 V13 M34 13 V23 Q34 30 42 30 Q50 30 50 23 V13 M60 13 V23 Q60 30 68 30 Q76 30 76 23 V13 M86 29 V13 L96 23 L106 13 V29" />
        </svg>
      </span>
      <span className="sand-nunu-badge__glare" aria-hidden="true" />
    </div>
      <span className="sand-nunu-badge__seal">
        <svg className="sand-nunu-badge__ring" viewBox="0 0 200 200" aria-hidden="true">
          <defs><path id={ringId} d="M 100,100 m -89,0 a 89,89 0 1,1 178,0 a 89,89 0 1,1 -178,0" /></defs>
          <text><textPath href={`#${ringId}`} textLength="554" lengthAdjust="spacing">NUUM · A MIND OF YOUR OWN · NUUM · ALWAYS WITH YOU · </textPath></text>
          <circle cx="100" cy="100" r="76" />
        </svg>
        <button type="button" className="sand-nunu-badge__avatar" aria-label={t("Greet {name}", { name: profile.name })}
          onClick={(event) => { event.stopPropagation(); setReaction(value => value + 1); }}>
          <NunuPortrait agentId={profile.id} color={profile.avatarColor} shape={profile.avatarShape} material={profile.avatarMaterial} reaction={reaction} />
        </button>
      </span>
  </div>;
}

/**
 * 「Nunu 身份」编辑弹窗：显式保存 / 取消（取消或关闭一律不落盘），
 * 与工牌的失焦自动保存不同——模板预填需要能整体反悔。
 */
function IdentityDialog({ profile, onSave, onClose }: {
  profile: AgentProfile; onSave(patch: AgentProfilePatch): Promise<void>; onClose(): void;
}) {
  const [name, setName] = useState(profile.name);
  const [tags, setTags] = useState((profile.tags ?? []).join(", "));
  const [description, setDescription] = useState(profile.description);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  // 模板只在第一次修改前出现；首次保存成功即记账，之后不再显示。
  const [showTemplates] = useState(() => !hasEditedIdentity(profile.id));
  const save = async () => {
    const finalName = name.trim();
    if (!finalName) { setError(t("Name cannot be empty.")); return; }
    setBusy(true); setError("");
    try {
      const parsedTags = [...new Set(tags.split(/[,，、\n]/).map((tag) => tag.trim()).filter(Boolean))];
      await onSave({ name: finalName, tags: parsedTags, description: description.trim() });
      markIdentityEdited(profile.id);
      onClose();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : t("Could not save. Please try again."));
    } finally {
      setBusy(false);
    }
  };
  return <WorkDialog title={t("Nunu identity")} className="sand-identity-dialog" onClose={onClose}>
    <div className="sand-identity-form">
      <label className="sand-identity-field">
        <span>{t("Name")}</span>
        <input autoFocus value={name} disabled={busy} onChange={(event) => setName(event.target.value)} />
      </label>
      <label className="sand-identity-field">
        <span>{t("Tags (optional)")}</span>
        <input value={tags} disabled={busy} placeholder={t("Research, design, operations")} onChange={(event) => setTags(event.target.value)} />
      </label>
      <label className="sand-identity-field">
        <span>{t("Description")}</span>
        <AutoTextarea value={description} disabled={busy} placeholder={t("What should this Agent do?")} onChange={(event) => setDescription(event.target.value)} />
      </label>
      {showTemplates ? <div className="sand-identity-templates">
        <span>{t("Recommended templates")}</span>
        <div>
          {AGENT_ROLE_TEMPLATES.map((template) => (
            <button key={template.key} type="button" disabled={busy} className="sand-identity-template"
              onClick={() => {
                setName(t(template.name));
                setTags(t(template.tags));
                setDescription(t(template.description));
              }}>
              <span className="sand-identity-template__head">
                {/* 模板的颜色由迷你头像承载——按钮本身保持中性，头像同时预览套用后的形象。 */}
                <AgentAvatar agentId={template.key} color={template.colorId} shape={template.shape} material="matte" size={18} />
                <strong>{t(template.name)}</strong>
              </span>
              <small>{t(template.description)}</small>
            </button>
          ))}
        </div>
      </div> : null}
      {error ? <p className="sand-identity-error" role="alert">{error}</p> : null}
      <div className="sand-identity-actions">
        <button type="button" disabled={busy} onClick={onClose}>{t("Cancel")}</button>
        <button type="button" className="sand-work-primary" disabled={busy} onClick={() => void save()}>{busy ? t("Saving…") : t("Finish")}</button>
      </div>
    </div>
  </WorkDialog>;
}

export function AgentProfilePanel({ profile, onSave, onClose }: {
  profile: AgentProfile; onSave(patch: AgentProfilePatch): Promise<void>; onClose(): void;
}) {
  const [editing, setEditing] = useState(false);
  return <aside className="sand-agent-profile-panel" aria-label={t("Nunu identity")}>
    <header><span>{t("Nunu identity")}</span><SandIconButton icon="chevron-right" label={t("Close profile")} aria-label={t("Close profile")} onClick={onClose} size="sm" /></header>
    <div className="sand-agent-profile-panel__body">
      <NunuBadge profile={profile} onEdit={() => setEditing(true)} />
    </div>
    {editing ? <IdentityDialog profile={profile} onSave={onSave} onClose={() => setEditing(false)} /> : null}
  </aside>;
}
