import { t } from "../i18n";
import { useState } from "react";
import type { AgentSettings, ExecutionPreferences } from "@nuum/protocol";

export function ExecutionWidget({ settings, workspaceNames, onSave, onOpen }: {
  settings: AgentSettings;
  workspaceNames: Record<string, string>;
  onSave(value: ExecutionPreferences): Promise<void>;
  onOpen(): void;
}) {
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const execution = settings.execution;
  if (!execution) return null;
  const save = async (value: ExecutionPreferences) => {
    setSaving(true); setError(null);
    try { await onSave(value); } catch (error) { setError(error instanceof Error ? error.message : String(error)); }
    finally { setSaving(false); }
  };
  return <section className="sand-execution-widget" aria-label={t("Workspace and permissions")}>
    <header>{t("Workspace and permissions")}</header>
    <div className="sand-execution-widget__row"><span>{t("Personal workspace")}</span><button type="button" onClick={onOpen}>{t("Open folder")}</button></div>
    <p className="sand-execution-widget__path">{settings.workspace?.projectRoot}</p>
    <p>{t("Room tasks use the shared room workspace.")}</p>
    <label className="sand-execution-widget__row"><span>{t("Command execution")}</span>
      <select disabled={saving} value={execution.commands === "never" ? "never" : "ask"} onChange={event => void save({ ...execution, commands: event.target.value as ExecutionPreferences["commands"] })}>
        <option value="ask">{t("Allow inside sandbox")}</option><option value="never">{t("Deny")}</option>
      </select>
    </label>
    {(execution.externalGrants ?? []).length ? <details><summary>{t("Local computer permissions")}</summary><ul>
      {(execution.externalGrants ?? []).map((grant, index) => <li key={index}><div><span>{t({ read: "Read file", import: "Import file", export: "Export file", shell: "Run command" }[grant.operation])}: {grant.destination ?? grant.source ?? (grant.command?.kind === "exact" ? grant.command.command : grant.command?.kind === "prefix" ? grant.command.argv.join(" ") : t("Compound command"))}</span><small>{[...(grant.readPaths ?? []), ...(grant.writePaths ?? []), ...(grant.networkTargets ?? [])].join(" · ")}</small></div>
        <button disabled={saving} type="button" onClick={() => void save({ ...execution, externalGrants: execution.externalGrants?.filter((_, i) => i !== index) })}>{t("Revoke")}</button></li>)}
    </ul></details> : null}
    {execution.commandGrants.length ? <details><summary>{t("Remembered commands ({count})", { count: execution.commandGrants.length })}</summary><ul>
      {execution.commandGrants.map(grant => <li key={`${grant.workspaceId}:${grant.command}`}>
        <div><span>{grant.command}</span><small>{grant.workspaceId === execution.workspaceId ? t("Personal workspace") : workspaceNames[grant.workspaceId] ?? t("Former room")}</small></div>
        <button disabled={saving} type="button" onClick={() => void save({ ...execution, commandGrants: execution.commandGrants.filter(item => item !== grant) })}>{t("Revoke")}</button>
      </li>)}
    </ul></details> : null}
    <div className="sand-execution-widget__row"><span>{t("Tool network")}</span><span>{t("Denied by default")}</span></div>
    {execution.networkGrants.length === 0 ? <p>{t("Network access requires your approval.")}</p> : <ul>
      {execution.networkGrants.map(grant => <li key={`${grant.workspaceId}:${grant.target}`}>
        <div><span>{grant.target}</span><small>{grant.workspaceId === execution.workspaceId ? t("Personal workspace") : workspaceNames[grant.workspaceId] ?? t("Former room")}</small></div>
        <button disabled={saving} type="button" onClick={() => void save({ ...execution, networkGrants: execution.networkGrants.filter(item => item !== grant) })}>{t("Revoke")}</button>
      </li>)}
    </ul>}
    {error ? <p role="alert">{error}</p> : null}
  </section>;
}
