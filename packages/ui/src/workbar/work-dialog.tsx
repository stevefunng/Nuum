import { t } from "../i18n";
import type { WorkCatalogAddParams } from "@nuum/protocol";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { SandIcon } from "../kit/sand-kit-primitives";

export function WorkDialog({ title, subtitle, className, children, onClose }: {
  title: string; subtitle?: string; className?: string; children: ReactNode; onClose(): void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const dialog = ref.current;
    dialog?.showModal();
    dialog?.querySelector<HTMLElement>("[data-autofocus]")?.focus();
    return () => { dialog?.close(); previous?.focus(); };
  }, []);
  return <dialog className={["sand-work-dialog", className].filter(Boolean).join(" ")} ref={ref} aria-label={title} onCancel={onClose} onClick={(event) => {
    if (event.target !== event.currentTarget) return;
    const box = event.currentTarget.getBoundingClientRect();
    if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) onClose();
  }}>
    <header><div><h2>{title}</h2>{subtitle ? <p>{subtitle}</p> : null}</div><button className="sand-work-icon-button" aria-label={t("Close dialog")} onClick={onClose} type="button"><SandIcon name="close" size={16} /></button></header>
    {children}
  </dialog>;
}

const KINDS = ["skill", "cli", "knowledge", "local-tool"] as const;
type Kind = typeof KINDS[number];
const LABELS: Record<Kind, string> = { skill: "Skill", cli: "CLI", knowledge: "Knowledge", "local-tool": "Local tools" };

export function WorkCapabilityDialog({ onClose, onAdd, onPickDirectory }: {
  onClose(): void;
  onAdd(entry: WorkCatalogAddParams["entry"]): Promise<boolean>;
  onPickDirectory(): Promise<string | null>;
}) {
  const [tab, setTab] = useState<"discover" | "local">("discover");
  const [kind, setKind] = useState<Kind>("skill");
  const [name, setName] = useState("");
  const [path, setPath] = useState("");
  const [commands, setCommands] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  return <WorkDialog title={t("Capabilities")} subtitle={t("Skills, tools and knowledge for this Work.")} onClose={onClose}>
    <div className="sand-work-store-tabs" aria-label={t("Capability source")}>
      <button aria-pressed={tab === "discover"} onClick={() => setTab("discover")} type="button">{t("Discover")}</button>
      <button aria-pressed={tab === "local"} onClick={() => setTab("local")} type="button">{t("Import local")}</button>
    </div>
    {tab === "discover" ? <div className="sand-work-store">
      <div className="sand-work-store__heading"><span>{t("THE COLLECTION")}</span><small>{t("Coming soon")}</small></div>
      <div className="sand-work-store__grid">
        <article className="sand-work-store-card" data-kind="skill"><span className="sand-work-store-card__symbol"><SandIcon name="sliders" size={24} /></span><small>{t("KNOW-HOW")}</small><h3>{t("Skills")}</h3><p>{t("Thoughtful workflows.")}<br />{t("Ready for your next task.")}</p><span className="sand-work-store-card__soon">{t("Presets on the way")}</span></article>
        <article className="sand-work-store-card" data-kind="cli"><span className="sand-work-store-card__symbol"><SandIcon name="attach" size={24} /></span><small>{t("HANDS-ON")}</small><h3>{t("CLI tools")}</h3><p>{t("Familiar tools.")}<br />{t("A little more possibility.")}</p><span className="sand-work-store-card__soon">{t("Presets on the way")}</span></article>
      </div>
      <button className="sand-work-store__import" onClick={() => setTab("local")} type="button"><span><strong>{t("Already have something in mind?")}</strong><small>{t("Bring a local Skill, CLI or knowledge folder.")}</small></span><span>{t("Import local")}{" "}<SandIcon name="plus" size={12} /></span></button>
    </div> : <form className="sand-work-dialog-form" onSubmit={async (event) => {
      event.preventDefault();
      if (!name.trim() || !path.trim() || busy) return;
      const base = { name: name.trim(), description: "" };
      const entry: WorkCatalogAddParams["entry"] = kind === "skill" ? { ...base, kind, manifestPath: path.trim() }
        : kind === "cli" ? { ...base, kind, executable: path.trim(), allowedSubcommands: commands.split(/[,\s]+/).filter(Boolean) }
        : kind === "knowledge" ? { ...base, kind, roots: [path.trim()], readOnly: true }
        : { ...base, kind, toolNames: path.split(",").map((item) => item.trim()).filter(Boolean) };
      if (entry.kind === "local-tool" && entry.toolNames.length === 0) { setError(t("Enter at least one tool name.")); return; }
      setBusy(true); setError("");
      try { if (await onAdd(entry)) onClose(); else setError(t("Could not import. Check the path and try again.")); }
      catch (error) { setError(error instanceof Error ? error.message : String(error)); }
      finally { setBusy(false); }
    }}>
      <div className="sand-work-kind-picker">{KINDS.map((item) => <button disabled={busy} aria-pressed={kind === item} key={item} onClick={() => { setKind(item); setPath(""); setError(""); }} type="button">{t(LABELS[item])}</button>)}</div>
      <label>{t("Name")}<input required disabled={busy} value={name} onChange={(event) => setName(event.target.value)} placeholder={kind === "skill" ? t("e.g. Design review") : t("A short, recognizable name")} /></label>
      <label>{kind === "skill" ? t("Skill manifest") : kind === "cli" ? t("Executable") : kind === "knowledge" ? t("Knowledge folder") : t("Tool names")}
        <div className="sand-work-path-input"><input required disabled={busy} value={path} onChange={(event) => setPath(event.target.value)} placeholder={kind === "skill" ? "/path/to/skill/SKILL.md" : kind === "cli" ? "/path/to/executable" : kind === "knowledge" ? "/path/to/knowledge" : t("Tool names, separated by commas")} />{kind === "skill" || kind === "knowledge" ? <button disabled={busy} type="button" onClick={async () => { const directory = await onPickDirectory(); if (directory) { setPath(kind === "skill" ? `${directory.replace(/[\\/]$/, "")}/SKILL.md` : directory); if (!name) setName(directory.split(/[\\/]/).pop() ?? ""); } }}>{t("Browse")}</button> : null}</div>
      </label>
      {kind === "cli" ? <label>{t("Allowed subcommands")}<input disabled={busy} value={commands} onChange={(event) => setCommands(event.target.value)} placeholder={t("e.g. status, diff, log")} /></label> : null}
      <p className="sand-work-import-note">{kind === "knowledge" ? t("Agents can read this folder. The source files stay in place.") : kind === "skill" ? t("Choose the folder containing SKILL.md, or enter its full path.") : kind === "cli" ? t("Use an installed executable. List the subcommands this Work can use.") : t("Add tools already registered in Nuum.")}</p>
      {error ? <p className="sand-work-form-error" role="alert">{t(error)}</p> : null}
      <button className="sand-work-primary" disabled={busy || !name.trim() || !path.trim()} type="submit">{busy ? t("Importing…") : t("Add to Work")}</button>
    </form>}
  </WorkDialog>;
}
