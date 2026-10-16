/**
 * 角色模板：创建页与「Nunu 身份」弹窗共用的一套最常用角色预设。
 * colorId/shape 只是模板按钮上的迷你头像标识，不写入 profile——
 * Nunu 的形象（颜色×形状×材质）在创建时随机定下并永久绑定，模板只填文字资料。
 */
export const AGENT_ROLE_TEMPLATES = [
  {
    key: "researcher",
    name: "Researcher",
    description: "Track a topic, read sources, and bring back concise findings.",
    tags: "Research, sources",
    colorId: "blue",
    shape: "droplet"
  },
  {
    key: "partner",
    name: "Project partner",
    description: "Stay with one project, remember decisions, and help move it forward.",
    tags: "Projects, follow-ups",
    colorId: "green",
    shape: "blob"
  },
  {
    key: "operator",
    name: "Daily operator",
    description: "Handle recurring local tasks and keep an eye on follow-ups.",
    tags: "Daily tasks, reminders",
    colorId: "orange",
    shape: "tablet"
  }
] as const;

export type AgentRoleTemplate = (typeof AGENT_ROLE_TEMPLATES)[number];

// 模板只在第一次修改前出现。协议里没有"是否编辑过"字段，这笔账记在
// renderer 本地（UI 偏好，不是会话真源）：身份弹窗首次保存成功即标记。
const IDENTITY_EDITED_KEY = "nuum-identity-edited";

export function hasEditedIdentity(agentId: string): boolean {
  try {
    return JSON.parse(localStorage.getItem(IDENTITY_EDITED_KEY) ?? "{}")[agentId] === true;
  } catch {
    return false;
  }
}

export function markIdentityEdited(agentId: string): void {
  try {
    const record = JSON.parse(localStorage.getItem(IDENTITY_EDITED_KEY) ?? "{}");
    record[agentId] = true;
    localStorage.setItem(IDENTITY_EDITED_KEY, JSON.stringify(record));
  } catch {
    // localStorage 不可用时退化为每次都显示模板，无功能风险。
  }
}
