import { useId, type CSSProperties } from "react";
import type { AgentView } from "@nuum/protocol";
import "./nunu-avatar.css";

import { SHAPES, resolveAgentAvatarColor, resolveAgentAvatarShape, resolveAgentAvatarMaterial, type AgentAvatarState } from "./nunu-appearance";
import { NunuPortrait } from "./nunu-portrait";
export * from "./nunu-appearance";
export function AgentAvatar({ agentId, color, shape, material, size = 34, state = "idle", className = "", fullBody = false }: {
  agentId: string; color?: string | null; shape?: string | null; material?: string | null;
  size?: number; state?: AgentAvatarState; className?: string; fullBody?: boolean;
}) {
  const uid = `nunu-${useId().replace(/:/g, "")}`;
  const ink = resolveAgentAvatarColor(agentId, color);
  const body = SHAPES[resolveAgentAvatarShape(agentId, shape)];
  const surface = resolveAgentAvatarMaterial(agentId, material);
  const textured = size >= 48 && (surface === "plush" || surface === "felt");
  const happy = ["happy", "receiving", "wave"].includes(state);
  if (fullBody) {
    return <span aria-hidden="true" className={`sand-agent-avatar nunu-avatar ${className}`} data-state={state} data-material={surface} data-full="true" style={{ "--sand-avatar-size": `${size}px` } as CSSProperties}>
      <NunuPortrait agentId={agentId} color={color} shape={shape} material={material} reaction={0} />
    </span>;
  }
  return <span aria-hidden="true" className={`sand-agent-avatar nunu-avatar ${className}`} data-state={state} data-material={surface} data-full={fullBody} style={{ "--sand-avatar-size": `${size}px` } as CSSProperties}>
    <svg width={size} height={size} viewBox={fullBody ? "0 0 232 232" : "18 8 196 196"} xmlns="http://www.w3.org/2000/svg">
      <defs>
        <radialGradient id={`${uid}-body`} cx="32%" cy="24%" r="83%"><stop stopColor="#fffaf1" stopOpacity=".95"/><stop offset=".36" stopColor={ink.value}/><stop offset="1" stopColor={ink.dark}/></radialGradient>
        <radialGradient id={`${uid}-eye`} cx="32%" cy="22%"><stop stopColor="#806b60"/><stop offset=".4" stopColor="#40312b"/><stop offset="1" stopColor="#241e1b"/></radialGradient>
        <linearGradient id={`${uid}-glass`} x2=".8" y2="1"><stop stopColor="white" stopOpacity=".8"/><stop offset=".45" stopColor="white" stopOpacity="0"/><stop offset="1" stopColor="white" stopOpacity=".4"/></linearGradient>
        <clipPath id={`${uid}-clip`}><path d={body}/></clipPath>
        {textured ? <filter id={`${uid}-texture`} x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency={surface === "felt" ? ".65" : ".32"} numOctaves="3" seed="8"/><feColorMatrix type="saturate" values="0"/><feComposite in2="SourceGraphic" operator="in"/><feBlend in="SourceGraphic" mode="soft-light"/></filter> : null}
      </defs>
      {fullBody ? <ellipse cx="116" cy="218" rx="64" ry="7" fill={ink.dark} opacity=".16"/> : null}
      <g className="nunu-avatar__body">
        {fullBody ? <g fill={`url(#${uid}-body)`}><ellipse cx="86" cy="202" rx="22" ry="13"/><ellipse cx="146" cy="202" rx="22" ry="13"/></g> : null}
        <path d={body} fill={`url(#${uid}-body)`} stroke={ink.dark} strokeOpacity=".3" strokeWidth="1"/>
        {textured ? <path d={body} fill={ink.value} filter={`url(#${uid}-texture)`} opacity={surface === "felt" ? ".36" : ".25"}/> : null}
        {surface === "glass" || surface === "aurora" ? <g clipPath={`url(#${uid}-clip)`}><path d={body} fill={`url(#${uid}-glass)`}/><path d="M57 89Q58 40 84 40" fill="none" stroke="white" strokeWidth="9" strokeLinecap="round" opacity=".5"/><ellipse cx="173" cy="159" rx="10" ry="22" fill="white" opacity=".18"/></g> : null}
        {fullBody ? <g fill={`url(#${uid}-body)`} stroke={ink.dark} strokeOpacity=".2"><ellipse cx="40" cy="148" rx="15" ry="25" transform="rotate(20 40 148)"/><g className="nunu-avatar__arm"><ellipse cx="191" cy="143" rx="15" ry="25" transform="rotate(-24 191 143)"/></g></g> : null}
        <g className="nunu-avatar__face">
          {size >= 48 ? <g fill="#db9a8d" opacity=".22"><ellipse cx="70" cy="147" rx="13" ry="8"/><ellipse cx="161" cy="147" rx="13" ry="8"/></g> : null}
          {[82, 149].map(x => <g key={x} className="nunu-avatar__eye">{happy ? <path d={`M${x-7} 129Q${x} 119 ${x+7} 129`} fill="none" stroke="#392c27" strokeWidth="4" strokeLinecap="round"/> : <><ellipse cx={x} cy="128" rx="8" ry="10" fill={`url(#${uid}-eye)`}/><circle cx={x-2} cy="124" r="2.1" fill="white" opacity=".9"/></>}</g>)}
          <path d={state === "error" ? "M108 150Q116 144 124 150" : "M108 146Q116 154 124 146"} fill="none" stroke="#49362b" strokeWidth="3.5" strokeLinecap="round"/>
        </g>
        {state === "waiting" && fullBody ? <circle cx="200" cy="91" r="5" fill={ink.dark}/> : null}
      </g>
    </svg>
  </span>;
}

const WORK_GROUP_MAX_MEMBERS = 4;

function workGroupSlots(count: number, frame: number): Array<{ x: number; y: number; size: number }> {
  if (count <= 1) return [{ x: 0, y: 0, size: frame }];
  if (count === 2) {
    const size = frame * 2 / 3;
    return [{ x: 0, y: 0, size }, { x: frame - size, y: frame - size, size }];
  }
  const size = frame * 5 / 9;
  const offset = frame - size;
  return count === 3
    ? [{ x: offset / 2, y: 0, size }, { x: 0, y: offset, size }, { x: offset, y: offset, size }]
    : [{ x: 0, y: 0, size }, { x: offset, y: 0, size }, { x: 0, y: offset, size }, { x: offset, y: offset, size }];
}

/**
 * Work bar 的群头像：成员的 Nunu 头像拼进一个圆角方块，样式取自 Grok Bot
 * 的群聊头像（2 人错位叠放，3–4 人紧凑拼贴）。成员 id 就够了 —— 头像色可由 id 哈希推出，
 * agents 只用来尊重用户自定义的头像色与形状。
 */
export function WorkGroupAvatar({
  memberIds,
  agents,
  size = 34,
  className = ""
}: {
  memberIds: readonly string[];
  agents?: readonly AgentView[];
  size?: number;
  className?: string;
}) {
  if (memberIds.length === 0) return null;
  const profileOf = (id: string) => agents?.find((agent) => agent.profile.id === id);
  if (memberIds.length === 1) {
    const agent = profileOf(memberIds[0]!);
    return <AgentAvatar agentId={memberIds[0]!} color={agent?.profile.avatarColor} shape={agent?.profile.avatarShape} material={agent?.profile.avatarMaterial} state={agent?.runtime.status === "running" ? "working" : agent?.runtime.status === "error" ? "error" : "idle"} size={size} className={className} />;
  }
  const shown = memberIds.slice(0, WORK_GROUP_MAX_MEMBERS);
  const slots = workGroupSlots(shown.length, size);
  return (
    <span
      aria-hidden="true"
      className={["sand-work-avatar", className].filter(Boolean).join(" ")}
      data-count={shown.length}
      style={{ width: size, height: size } as CSSProperties}
    >
      {shown.map((id, index) => {
        const agent = profileOf(id);
        const slot = slots[index]!;
        return (
          <span key={id} className="sand-work-avatar__cell" style={{ left: slot.x, top: slot.y, width: slot.size, height: slot.size }}>
            <AgentAvatar agentId={id} color={agent?.profile.avatarColor} shape={agent?.profile.avatarShape} material={agent?.profile.avatarMaterial} size={slot.size} state={agent?.runtime.status === "running" ? "working" : "idle"} />
          </span>
        );
      })}
    </span>
  );
}
