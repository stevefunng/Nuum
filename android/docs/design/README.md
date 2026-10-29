# Nuum Android PoC 设计规格（WP-D）

工程师按本目录实现 `:feature:shell`、`:feature:conversation`、`:feature:work`、`:feature:settings`。本目录只有规格，没有 Kotlin，没有 Android 资源 XML。

对照事实：

- 架构与范围：[ANDROID_ARCHITECTURE.md](../ANDROID_ARCHITECTURE.md)
- Mac 行为：[NUUM_MACOS_ANALYSIS.md](../NUUM_MACOS_ANALYSIS.md)
- 工作包：[WORK_BREAKDOWN.md](../WORK_BREAKDOWN.md) § WP-D
- 文案真源：`packages/ui/src/i18n/messages.ts`。规格写 key。中文是该 key 的 `zh-CN`，用来核对，不是另一套产品名。
- 颜色真源：`packages/ui/src/theme/runtime-theme-token-installer.ts`。完整表在 [tokens.md](./tokens.md)。

标识符保持英语：`Nuum`、`Nunu`、`Room`、`NunuBar`、`Proactive mode`、`SendMessage`、`widget`、`runId`。

## 阅读顺序

1. [design-system.md](./design-system.md) 与 [tokens.md](./tokens.md)
2. [layout.md](./layout.md)：手机宽度与 `≥ 840dp` 分栏，抽屉如何替代 Mac 侧栏
3. [motion.md](./motion.md)、[assets.md](./assets.md)
4. [out-of-poc.md](./out-of-poc.md)
5. `screens/` 里每一张屏幕规格

## 屏幕清单

| 规格 | Mac 上的现成表面 |
| --- | --- |
| [screens/sidebar.md](./screens/sidebar.md) | `packages/ui/src/conversation/sidebar.tsx` |
| [screens/conversation-empty.md](./screens/conversation-empty.md) | `workspace.tsx` 的 `.sand-empty--welcome` |
| [screens/conversation-transcript.md](./screens/conversation-transcript.md) | `workspace.tsx` 转录、输入框、peer 抽屉、工具活动组 |
| [screens/approval-bar.md](./screens/approval-bar.md) | `execution-approval.tsx` |
| [screens/widget.md](./screens/widget.md) | `workspace.tsx` 的 `WidgetCard` |
| [screens/attachments.md](./screens/attachments.md) | `workspace.tsx` 输入框附件 + `attachment-files.ts` |
| [screens/create-nunu.md](./screens/create-nunu.md) | `agent-creation.tsx` |
| [screens/unboxing-2d.md](./screens/unboxing-2d.md) | `nunu-unboxing.tsx` 的终态；PoC 用 2D |
| [screens/profile.md](./screens/profile.md) | `agent-profile-panel.tsx`、`execution-widget.tsx` |
| [screens/settings.md](./screens/settings.md) | `SettingsOverlay` + `App.tsx` 的 General / Models |
| [screens/room.md](./screens/room.md) | `WorkCreation` 的 room，以及 `WorkBoard` 在 `kind === "room"` |
| [screens/nunubar-lanes.md](./screens/nunubar-lanes.md) | `work-content.tsx` 的 `TaskLanes` 与交付物 |
| [screens/capability-catalog.md](./screens/capability-catalog.md) | `work-dialog.tsx` 的 `WorkCapabilityDialog` |
| [screens/proactive.md](./screens/proactive.md) | `proactive-panel.tsx`，入口改到设置里 |

## 每屏都要列出的七个状态

每张屏幕规格都有一张状态表。某个状态在该表面不会发生时，写明「此表面不出现」，并指出它出现在哪一张规格上。不要为了填满七行而新做控件。

| 状态 | 含义 |
| --- | --- |
| 空 | 该表面还没有主内容 |
| 加载 | 本地投影或第一份 snapshot 还没到，主内容不可操作 |
| 流式 | 正在追加 `agent.message.delta`，或头像 / 活动条文案表示这一轮还没结束 |
| 错误 | 展示 `NuumException.message` 或现有 i18n key。句子里不得出现 API key |
| 无 key | Host `NO_API_KEY`（2004）。发送被拒绝，转录里没有 key 字样 |
| 权限被拒 | 用户选择 `deny`，或路径落在授权根之外（含 SAF 权限已失效） |
| 讨论中断 | Room / NunuBar 的 `interruptions`。文案用现有 key，例如 `Discussion interrupted. Continue starts a new bounded discussion.` |

## 文案规则

- 界面向 `values/strings.xml` 与 `values-zh-rCN/strings.xml` 填入 `messages.ts` 的 `en` 与 `zh-CN`。key 用英文原文当查找键。
- 带 `{name}`、`{count}`、`{time}`、`{state}`、`{action}`、`{answer}`、`{first}`、`{second}` 的句子保持占位符。
- 缺省语言跟随系统。应用内仍可强制 `zh-CN` 或 `en`，和 `Language` 枚举一致。`messages.ts` 在运行时把缺省当中文；Android 资源默认串用 `en`，`values-zh-rCN` 用 `zh-CN`。设置里的语言覆盖两者。
- 不新造产品名，不把 `Nunu` 译成别的词。`messages.ts` 里 `Agent` 的 `zh-CN` 已经是「Nunu」。
