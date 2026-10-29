import { t } from "../i18n";
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { SandIcon } from "../kit/sand-kit-primitives";
import type { SandIconName } from "../kit/sand-icon-registry";

export interface SidebarMenuItem { label: string; icon?: SandIconName; disabled?: boolean; separator?: boolean; onSelect(): void }

export function SidebarMenu({ point, items, onClose }: {
  point: { x: number; y: number }; items: SidebarMenuItem[]; onClose(): void;
}) {
  const menu = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState(point);
  useLayoutEffect(() => {
    const element = menu.current;
    if (!element) return;
    setPosition({ x: Math.max(8, Math.min(point.x, window.innerWidth - element.offsetWidth - 8)), y: Math.max(8, Math.min(point.y, window.innerHeight - element.offsetHeight - 8)) });
    element.querySelector<HTMLButtonElement>("button:not(:disabled)")?.focus();
  }, [point, items.length]);
  useEffect(() => {
    const outside = (event: PointerEvent) => { if (!menu.current?.contains(event.target as Node)) onClose(); };
    document.addEventListener("pointerdown", outside, true);
    window.addEventListener("blur", onClose);
    window.addEventListener("resize", onClose);
    return () => { document.removeEventListener("pointerdown", outside, true); window.removeEventListener("blur", onClose); window.removeEventListener("resize", onClose); };
  }, [onClose]);
  return createPortal(<div ref={menu} className="sand-sidebar-menu" role="menu" aria-label={t("Sidebar actions")} style={{ left: position.x, top: position.y }} onContextMenu={(event) => event.preventDefault()}
    onKeyDown={(event) => {
      if (event.key === "Escape" || event.key === "Tab") { event.preventDefault(); onClose(); return; }
      if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      const buttons = [...event.currentTarget.querySelectorAll<HTMLButtonElement>("button:not(:disabled)")];
      const current = buttons.indexOf(document.activeElement as HTMLButtonElement);
      const next = event.key === "Home" ? 0 : event.key === "End" ? buttons.length - 1 : (current + (event.key === "ArrowDown" ? 1 : -1) + buttons.length) % buttons.length;
      buttons[next]?.focus();
    }}>
    {items.map((item, index) => <div key={`${item.label}-${index}`}>{item.separator ? <div role="separator" /> : null}<button role="menuitem" type="button" disabled={item.disabled} onClick={item.onSelect}>
      {item.icon ? <SandIcon name={item.icon} size={14} /> : <span className="sand-sidebar-menu__icon-space" />}<span>{item.label}</span>
    </button></div>)}
  </div>, document.body);
}

export function SidebarNewMenu({ anchor, onNewAgent, onNewWork, onClose }: {
  anchor: { left: number; top: number; width: number };
  onNewAgent(): void;
  onNewWork(): void;
  onClose(): void;
}) {
  const menu = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState({ x: anchor.left, y: anchor.top, width: anchor.width });
  useLayoutEffect(() => {
    const element = menu.current;
    if (!element) return;
    setPosition({
      x: Math.max(8, Math.min(anchor.left, window.innerWidth - element.offsetWidth - 8)),
      y: Math.max(8, Math.min(anchor.top, window.innerHeight - element.offsetHeight - 8)),
      width: anchor.width
    });
    element.querySelector<HTMLButtonElement>("button:not(:disabled)")?.focus();
  }, [anchor.left, anchor.top, anchor.width]);
  useEffect(() => {
    const outside = (event: PointerEvent) => {
      const target = event.target as Element | null;
      // 点击触发按钮本身交给按钮的 toggle 逻辑，避免“关了又立刻开”。
      if (menu.current?.contains(event.target as Node) || target?.closest?.("[data-new-menu-toggle]")) return;
      onClose();
    };
    document.addEventListener("pointerdown", outside, true);
    window.addEventListener("blur", onClose);
    window.addEventListener("resize", onClose);
    return () => { document.removeEventListener("pointerdown", outside, true); window.removeEventListener("blur", onClose); window.removeEventListener("resize", onClose); };
  }, [onClose]);
  const rows: { key: string; label: string; icon: SandIconName; onSelect(): void }[] = [
    { key: "new-nunu", label: t("Create new Nunu"), icon: "plus", onSelect: onNewAgent },
    { key: "new-work", label: t("Create NunuBar"), icon: "people", onSelect: onNewWork }
  ];
  return createPortal(<div ref={menu} className="sand-new-menu" role="menu" aria-label={t("New")} style={{ left: position.x, top: position.y, width: position.width }} onContextMenu={(event) => event.preventDefault()}
    onKeyDown={(event) => {
      if (event.key === "Escape" || event.key === "Tab") { event.preventDefault(); onClose(); return; }
      if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      const buttons = [...event.currentTarget.querySelectorAll<HTMLButtonElement>("button:not(:disabled)")];
      const current = buttons.indexOf(document.activeElement as HTMLButtonElement);
      const next = event.key === "Home" ? 0 : event.key === "End" ? buttons.length - 1 : (current + (event.key === "ArrowDown" ? 1 : -1) + buttons.length) % buttons.length;
      buttons[next]?.focus();
    }}>
    {rows.map((row) => <button key={row.key} role="menuitem" type="button" className="sand-new-menu__row" onClick={() => { onClose(); row.onSelect(); }}>
      <span className="sand-new-menu__chip"><SandIcon name={row.icon} size={12} /></span>
      <span className="sand-new-menu__label">{row.label}</span>
    </button>)}
  </div>, document.body);
}

export function SidebarNameDialog({ title, initialValue, busy, error, onSave, onClose }: {
  title: string; initialValue: string; busy: boolean; error: ReactNode;
  onSave(name: string): void; onClose(): void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [name, setName] = useState(initialValue);
  useEffect(() => {
    dialog.current?.showModal();
    dialog.current?.querySelector("input")?.select();
  }, []);
  return createPortal(<dialog ref={dialog} className="sand-sidebar-dialog" onCancel={(event) => { event.preventDefault(); if (!busy) onClose(); }}
    onClick={(event) => { if (event.target === event.currentTarget && !busy) { const rect = event.currentTarget.getBoundingClientRect(); if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) onClose(); } }}>
    <form onSubmit={(event) => { event.preventDefault(); if (name.trim() && !busy) onSave(name.trim()); }}>
      <header><h2>{title}</h2><button aria-label={t("Close group dialog")} type="button" disabled={busy} onClick={onClose}><SandIcon name="close" /></button></header>
      <input aria-label={t("Group name")} autoFocus maxLength={80} placeholder={t("Group name")} value={name} onChange={(event) => setName(event.target.value)} />
      {error ? <p role="alert">{error}</p> : null}
      <footer><button type="button" disabled={busy} onClick={onClose}>{t("Cancel")}</button><button type="submit" disabled={busy || !name.trim()}>{busy ? t("Saving…") : t("Save")}</button></footer>
    </form>
  </dialog>, document.body);
}
