# Nuum iOS 设计规格（WP-D）

工程师按本目录实现 `NuumFeatureShell`、`NuumFeatureConversation`、`NuumFeatureWork`、`NuumFeatureSettings`。本目录只有规格，没有 Swift，不改 Xcode 工程。

对照事实：

- 架构与范围：[IOS_ARCHITECTURE.md](../IOS_ARCHITECTURE.md) 第 12 节
- 对齐分析：[NUUM_IOS_ANALYSIS.md](../NUUM_IOS_ANALYSIS.md)
- 工作包：[WORK_BREAKDOWN.md](../WORK_BREAKDOWN.md) § WP-D
- 同一组屏幕的 Android 规格：`android/docs/design/screens/`。行为对齐那一组和 Mac；容器用水平 size class，见 [layout.md](./layout.md)
- 文案真源：`packages/ui/src/i18n/messages.ts`。规格写 key。中文是该 key 的 `zh-CN`，用来核对，不是另一套产品名
- 颜色、字号、间距真源：`packages/ui/src/theme/runtime-theme-token-installer.ts`。完整表在 [tokens.md](./tokens.md)

标识符保持英语：`Nuum`、`Nunu`、`Room`、`NunuBar`、`Proactive mode`、`SendMessage`、`widget`、`runId`。

产品里的 widget 是转录里的卡片，最多 6 个选项。它不是 WidgetKit。本期不加主屏幕小组件、Live Activity、App Intent。见 [screens/widget.md](./screens/widget.md)。

## 阅读顺序

1. [design-system.md](./design-system.md) 与 [tokens.md](./tokens.md)
2. [layout.md](./layout.md)：compact 与 regular。侧栏是一列，不是把 1200×800 缩小
3. [motion.md](./motion.md)、[assets.md](./assets.md)
4. [out-of-scope.md](./out-of-scope.md)
5. `screens/` 里每一张屏幕规格

## 屏幕清单

| 规格 | Mac 上的现成表面 | 以后的 package |
| --- | --- | --- |
| [screens/sidebar.md](./screens/sidebar.md) | `packages/ui/src/conversation/sidebar.tsx` | `NuumFeatureShell` |
| [screens/conversation-empty.md](./screens/conversation-empty.md) | `workspace.tsx` 的 `.sand-empty--welcome` | `NuumFeatureConversation` |
| [screens/conversation-transcript.md](./screens/conversation-transcript.md) | `workspace.tsx` 转录、输入框、peer 抽屉、工具活动组 | `NuumFeatureConversation` |
| [screens/approval-bar.md](./screens/approval-bar.md) | `execution-approval.tsx` | `NuumFeatureConversation`，NunuBar 上的条在 `NuumFeatureWork` |
| [screens/widget.md](./screens/widget.md) | `workspace.tsx` 的 `WidgetCard` | `NuumFeatureConversation` |
| [screens/attachments.md](./screens/attachments.md) | `workspace.tsx` 输入框附件 + `attachment-files.ts` | `NuumFeatureConversation` |
| [screens/create-nunu.md](./screens/create-nunu.md) | `agent-creation.tsx` | `NuumFeatureShell` |
| [screens/unboxing-2d.md](./screens/unboxing-2d.md) | `nunu-unboxing.tsx` 的终态；iOS 用 2D | `NuumFeatureShell` |
| [screens/profile.md](./screens/profile.md) | `agent-profile-panel.tsx`、`execution-widget.tsx` | `NuumFeatureShell` |
| [screens/settings.md](./screens/settings.md) | `SettingsOverlay` + `App.tsx` 的 General / Models | `NuumFeatureSettings` |
| [screens/room.md](./screens/room.md) | `WorkCreation` 的 room，以及 `WorkBoard` 在 `kind === "room"` | `NuumFeatureWork` |
| [screens/nunubar-lanes.md](./screens/nunubar-lanes.md) | `work-content.tsx` 的 `TaskLanes` 与交付物 | `NuumFeatureWork` |
| [screens/capability-catalog.md](./screens/capability-catalog.md) | `work-dialog.tsx` 的 `WorkCapabilityDialog` | `NuumFeatureWork` |
| [screens/proactive.md](./screens/proactive.md) | `proactive-panel.tsx`。入口在设置里，不要求菜单栏常驻 | `NuumFeatureSettings` |

## 每屏都要列出的七个状态

每张屏幕规格都有一张状态表。某个状态在该表面不会发生时，写明「此表面不出现」，并指出它出现在哪一张规格上。不要为了填满七行而新做控件。

| 状态 | 含义 |
| --- | --- |
| 空 | 该表面还没有主内容 |
| 加载 | 本地投影或第一份 snapshot 还没到，主内容不可操作 |
| 流式 | 正在追加 `agent.message.delta`，或头像 / 活动条文案表示这一轮还没结束 |
| 错误 | 展示 `NuumError.message` 或现有 i18n key。句子里不得出现 API key |
| 无 key | Host `NO_API_KEY`（2004）。发送被拒绝，转录里没有 key 字样 |
| 权限被拒 | 用户选择 `deny`，或路径落在授权根之外（含 security-scoped bookmark 已失效） |
| 讨论中断 | Room / NunuBar 的 `interruptions`。文案用现有 key，例如 `Discussion interrupted. Continue starts a new bounded discussion.` |

## 文案规则

- 界面向 String Catalog 的 `en` 与 `zh-CN` 填入 `messages.ts` 的同名列。查找键是 `messages.ts` 的对象键，通常就是英文句子。
- 带 `{name}`、`{count}`、`{time}`、`{state}`、`{action}`、`{answer}`、`{first}`、`{second}` 的句子保持占位符。
- `DEFAULT_SETTINGS.language` 是 `zh-CN`，`theme` 是 `dark`。设置尚未读到时用这两个默认。设置里的语言覆盖系统语言。`Follow system` 只属于主题，不属于语言。
- 不新造产品名，不把 `Nunu` 译成别的词。`messages.ts` 里 `Agent` 的 `zh-CN` 已经是「Nunu」。

## 交互规则

每个可点的控件都指回 Mac 上已经存在的行为，文件写在各屏开头。Mac 界面上没有的入口，写明「Mac 上没有，iOS 也不做」。

不要求菜单栏常驻、登录、同步、后台模型。这四项的依据在 [out-of-scope.md](./out-of-scope.md)。
