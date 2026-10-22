import { useState } from "react";
import type { LocalToolAction, ToolResolution } from "@nuum/protocol";
import { t } from "../i18n";

export function ExecutionApproval({ action, target, justification, details, allowAlways = true, agentName, onDecide }: {
  action: LocalToolAction; target: string; justification?: string; allowAlways?: boolean; details?: string; agentName?: string;
  onDecide(resolution: ToolResolution): Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const decide = async (resolution: ToolResolution) => {
    setBusy(true); setError(null);
    try { await onDecide(resolution); } catch (error) { setError(error instanceof Error ? error.message : String(error)); }
    finally { setBusy(false); }
  };
  return <div className="sand-permission-dock">
    <div><strong>{agentName ? `${agentName} · ` : ""}{justification || t("Allow {action}?", { action: t(action) })}</strong>
      {action !== "run-command" ? <div className="sand-permission-dock__preview">{target.split("\n")[0]}</div> : null}
      <details><summary>{t("Execution details")}</summary><div className="sand-permission-dock__preview">{details ?? target}</div></details>
    </div>
    <div className="sand-permission-dock__actions">
      <button disabled={busy} className="sand-permission-dock__btn sand-permission-dock__btn--deny" type="button" onClick={() => void decide("deny")}>{t("Deny")}</button>
      <button disabled={busy} className="sand-permission-dock__btn sand-permission-dock__btn--once" type="button" onClick={() => void decide("once")}>{t("Allow once")}</button>
      <button disabled={busy || !allowAlways} title={!allowAlways ? t("Dynamic commands require one-time approval") : undefined} className="sand-permission-dock__btn sand-permission-dock__btn--always" type="button" onClick={() => void decide("always")}>{t("Always allow")}</button>
    </div>
    {error ? <p role="alert">{error}</p> : null}
  </div>;
}
