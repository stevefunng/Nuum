# 审批条

Mac：`packages/ui/src/conversation/execution-approval.tsx`，样式 `.sand-permission-dock`。

同一条用在两处：

- 一对一输入框上方。`pending` 带 `workId` 时这里不画，改到 NunuBar。
- NunuBar 顶栏下方，该成员自己的条。可以有多条，按 `agentId:toolCallId` 分开。

`ToolResolution` 的 `never` 不出现在这条上。key `Never`、`Only this time`、`Always this action` 不用于这三个按钮。

## 结构

整条横向，窄屏改为纵向：说明在上，按钮行在下并靠末端。≥ 840dp 保持横向，按钮不换行。

| 区域 | 规格 |
| --- | --- |
| 容器 | 底 `--nuum-bg-elevated`，边 1dp `--sand-border-subtle`，圆角 `--nuum-radius-2xl`，padding `12dp 14dp`，间距 `--nuum-spacing-4` |
| 标题 | 字重 600，`--nuum-font-size-base`。有 `agentName` 时前缀 `名字 · `。有 `justification` 用它；否则 key `Allow {action}?`。`action` 先经 i18n：`read-file`、`list-directory`、`write-file`、`run-command`、`network` |
| 预览 | `action !== "run-command"` 时显示 `target` 的第一行。等宽 `--nuum-font-size-sm`，颜色 `--nuum-text-tertiary`，可断行 |
| 详情 | 折叠。摘要 key `Execution details`。展开后是 `details`，缺省则整段 `target`。等宽 |
| 按钮行 | 间距 `--nuum-spacing-1`。视觉高度 `--nuum-height-base`，热区 48dp，字号 `--nuum-font-size-sm`，字重 500，圆角 `--nuum-radius-lg` |

三个按钮从左到右，回调参数就是这三个字符串：

| 按钮 | key | 回调 | 外观 |
| --- | --- | --- | --- |
| 拒绝 | `Deny` | `deny` | 透明底，字 `--nuum-text-secondary`。按下时字 `--sand-text-danger`，底 `--sand-fill-danger-subtle` |
| 一次 | `Allow once` | `once` | 底 `--sand-fill-secondary`，字 `--nuum-text-primary` |
| 始终 | `Always allow` | `always` | 底 `--sand-fill-primary`，字 `--sand-text-on-primary`。按下底 `--sand-fill-primary-hover` |

`allowAlways === false` 时「始终」仍在，但是 `disabled`。`title` 用 key `Dynamic commands require one-time approval`。不可用时不要改成隐藏，Mac 也是禁用。

请求进行中三个按钮都 `disabled`。失败时条还在，下面一段 `role="alert"`，颜色 `--sand-text-danger`，文字是异常 message。成功后整条卸载。

一对一不传 `agentName`。NunuBar 要传，这样多条同时出现时能看出是谁。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 没有 pending：不渲染容器，不留空白占位 |
| 加载 | 此表面不单独加载。pending 事件到达才出现 |
| 流式 | 等待决定时，会话侧的头像状态是 `waiting`，顶栏小字 key `Waiting for approval`。条本身不流式追加文字 |
| 错误 | `onDecide` 抛错：条内 alert，按钮恢复可点 |
| 无 key | 此表面不出现。没有 key 时工具循环不会开始，发送失败在转录屏 |
| 权限被拒 | 用户点 `Deny` 且调用成功：条消失。这就是拒绝。不另画「已拒绝」按钮。活动组随后的失败用 key `失败` |
| 讨论中断 | 此表面不出现 |

记住的允许或拒绝写入该 Nunu 的 `tool-approvals.json`，由 Host 完成。这条 UI 不提供「查看已记住的授权」列表；撤销在 [profile.md](./profile.md)。

`always` 也不能读 secrets。若模型仍请求那些路径，Host 直接拒绝，不弹出可以点「始终允许」的条。那种拒绝不使用本组件，工具结果进入活动组。
