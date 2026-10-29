import { useEffect, useRef, useState, type CSSProperties } from "react";
import { createPortal } from "react-dom";
import { t } from "../i18n";
import { SandIcon } from "../kit/sand-kit-primitives";
import { AGENT_AVATAR_COLORS, rollAgentAvatar } from "./agent-avatar";
import "./agent-creation.css";
import { NunuUnboxing } from "./nunu-unboxing";

const COLOR_NAMES: Record<string, string> = {
  cream: "Cream", green: "Sage", orange: "Peach", violet: "Lilac",
  blue: "Mist blue", magenta: "Rose", honey: "Honey"
};

export function AgentCreation({ error, onCancel, onCreate }: {
  error?: string | null;
  onCancel(): void;
  onCreate(profile: { name: string; description: string; avatarColor: string; avatarShape: string; avatarMaterial: string }): Promise<void>;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const submitting = useRef(false);
  const [busy, setBusy] = useState(false);
  const [name, setName] = useState("");
  // One draw per opening. Picking a pigment never changes the revealed identity.
  const [avatar, setAvatar] = useState(rollAgentAvatar);
  useEffect(() => {
    const previous = document.querySelector<HTMLElement>("[data-new-menu-toggle]") ?? document.activeElement as HTMLElement | null;
    const element = dialog.current;
    element?.showModal();
    element?.querySelector("input")?.focus();
    return () => { element?.close(); previous?.focus(); };
  }, []);

  return createPortal(<dialog ref={dialog} className="sand-agent-create" aria-labelledby="nunu-create-heading"
    onCancel={event => { event.preventDefault(); if (!submitting.current) onCancel(); }}
    onClick={event => {
      if (event.target !== event.currentTarget || submitting.current) return;
      const box = event.currentTarget.getBoundingClientRect();
      if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) onCancel();
    }}>
    <form onSubmit={async event => {
      event.preventDefault();
      if (!name.trim() || submitting.current) return;
      submitting.current = true;
      setBusy(true);
      try {
        await onCreate({ name: name.trim(), description: "", avatarColor: avatar.color, avatarShape: avatar.shape, avatarMaterial: avatar.material });
      } finally {
        submitting.current = false;
        setBusy(false);
      }
    }}>
      <header className="sand-agent-create__header">
        <h2 id="nunu-create-heading">{t("Create new Nunu")}</h2>
        <button className="sand-agent-create__close" aria-label={t("Close dialog")} disabled={busy} onClick={onCancel} type="button"><SandIcon name="close" size={18} /></button>
      </header>
      <div className="sand-agent-create__body">
        <NunuUnboxing color={avatar.color} shape={avatar.shape} material={avatar.material} />
        <input className="sand-agent-create__name" aria-label={t("Nunu name")} placeholder={t("Give your Nunu a name")} maxLength={80} autoComplete="off" disabled={busy} value={name} onChange={event => setName(event.target.value)} />
        <fieldset className="sand-agent-create__palette" aria-label={t("Nunu color")} disabled={busy}>
          <div>{AGENT_AVATAR_COLORS.map(color => <button key={color.id} type="button" aria-label={t(COLOR_NAMES[color.id]!)} title={t(COLOR_NAMES[color.id]!)} aria-pressed={avatar.color === color.id} style={{ "--swatch": color.value } as CSSProperties} onClick={() => setAvatar(current => ({ ...current, color: color.id }))} />)}</div>
        </fieldset>
        {error ? <p className="sand-agent-create__error" role="alert">{t(error)}</p> : null}
      </div>
      <footer className="sand-agent-create__actions">
        <button className="sand-agent-create__cancel" disabled={busy} onClick={onCancel} type="button">{t("Cancel")}</button>
        <button className="sand-agent-create__submit" disabled={busy || !name.trim()} type="submit">{busy ? t("Creating…") : t("Create")}</button>
      </footer>
    </form>
  </dialog>, document.body);
}
