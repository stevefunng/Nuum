# Proactive 面板

Mac：`packages/ui/src/proactive/proactive-panel.tsx`，由菜单栏窗口 `?surface=proactive` 打开。Android 从设置 General 的按钮进入，key 仍是 `Open menu bar panel`。没有托盘，没有常驻通知，没有 `Quit`。

打开这一页时现算 snapshot。不移植每秒 tick，也不在后台跑模型。

手机全屏。≥ 840dp 时侧栏留着，这一页占内容列。底 `--nuum-bg-elevated`，内边距 `--nuum-spacing-5`（20px），可滚动。系统返回回到设置的 General，不退出应用。

字标行：左边文本 `Nuum`，17dp，字重 650，字距 `-0.5px`，颜色 `--nuum-text-primary`。右边文本 `Proactive mode`，11dp，`--nuum-text-secondary`。二者都是产品名，不另译。

## 状态卡

圆角 `--nuum-radius-3xl`，padding `17dp 16dp 0`，底是 `--nuum-text-primary` 的 4% 混合在透明上（Mac `color-mix`）。点 6dp。

标题用当前 agent 的 `name`，没有则文本 `Nunu`。字号 23dp，字重 600。

说明：`paused` 用 key `Your companion will resume after this break.`，其他状态用 key `A quieter kind of help, at the right moment.`

开关行顶边 `--sand-border-subtle`，最小高 48dp。标签 key `Proactive mode`。开关 `aria-label` key `Enable proactive mode`。开的时候轨道用 `--nuum-text-primary`，钮用 `--sand-text-on-primary`。关的时候轨道用 `--sand-fill-control-track`。点按发送 `enabled` 取反，并把 `pausedUntil` 置空。

状态点与状态句：

| `state` | 点的颜色 | 句子 key |
| --- | --- | --- |
| 无 snapshot | `--nuum-text-tertiary` | `Connecting to Nuum…` |
| `disabled` | `--nuum-text-tertiary` | `Proactive is off` |
| `paused` | `#aa8a52` | `Taking a pause` |
| `waiting-context` | `#80856b` | `Waiting for context` |
| `ready` | `#80856b` | `Ready to check` |
| `checking` | `--nuum-text-tertiary` | `Checking context` |
| `error` | `#bd615a` | `Check needs attention` |

`#80856b`、`#aa8a52`、`#bd615a` 是 Mac `.nuum-proactive-status` 写死的点色，不在 sand 表里。PoC 沿用这三个点色，以免把「暂停 / 就绪 / 出错」收成同一种 `--sand-fill-*`。其余界面仍只用 sand 变量。

## 操作

两个控件横排，间距 `--nuum-spacing-2`，各占一半。视觉高度约 36dp，热区 48dp，圆角 `--nuum-radius-lg`，边 `--sand-border-subtle`。

| 条件 | 控件 |
| --- | --- |
| `paused` | 按钮 key `Resume now`。把 `pausedUntil` 清空 |
| 其他 | 选择器 `aria-label` key `Pause proactive mode`。当前显示 key `Pause…`。选项 key `For 30 minutes`（值 1800000）、`For 1 hour`（值 3600000）。选中后 `pausedUntil = now + 毫秒`。未开启时整个选择器不可用 |
| 始终 | 按钮 key `Check setup`。未开启、暂停中、`checking` 或没有 snapshot 时不可用 |

暂停中且有 `pausedUntil`：居中 key `Resumes at {time}`，时间用应用语言的时分。

## 连接

`aria-label` key `Connections`。两行，左边标签，右边状态：

| 标签 key | 右侧 |
| --- | --- |
| `Context sources` | `availableSourceIds` 非空则 key `Available`，否则 key `Not connected` |
| `Agent actions` | 永远 key `Not connected`。来自 snapshot 的 `actionsAvailable === false`，界面不写死一个可切换的开关 |

段落下 key `Setup is ready. Context collection and autonomous actions are not enabled in this version.`，颜色 `--nuum-text-tertiary`。

## 最近活动

标题 key `Recent activity`。没有记录时 key `Activity will appear here when you turn it on.`

有记录时最多 3 条。句子 key：

| `kind` | key |
| --- | --- |
| `enabled` | `Proactive enabled` |
| `disabled` | `Proactive disabled` |
| `paused` | `Paused` |
| `resumed` | `Resumed` |
| `configured` | `Configuration updated` |
| `waiting-context` | `No context sources connected` |
| `context-ready` | `Context ready; actions not connected` |
| `no-change` | `No new context` |
| `error` | `Context check failed` |

右边是本地时分。

## 失败与页脚

更新失败：`role="alert"`，颜色 `#b85850`（Mac `.nuum-proactive-error`），句子 key `Could not update proactive mode.`，按钮 key `Retry`。Retry 再发上一次的 configure 或 check。

页脚顶边 `--sand-border-subtle`。只有起始边一个按钮：

| 条件 | key | 行为 |
| --- | --- | --- |
| 有默认 agent | `Open Nunu` | 关掉这一页，打开该 Nunu 的会话 |
| 没有 | `Open Nuum` | 关掉这一页，回到未选中的壳，并在手机上打开抽屉 |

不渲染 key `Quit`。不渲染第二扇窗口用的「回到主窗口」以外的进程控制。

配置调用要带 `agentId` 与 `expectedRevision`。冲突时 alert 用上面的失败 key，不覆盖用户刚看的开关直到重试成功。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 活动列表空：key `Activity will appear here when you turn it on.`。没有 agent 时标题是 `Nunu`，开关不可用 |
| 加载 | snapshot 还没有：句子 key `Connecting to Nuum…`，开关与两个按钮不可用 |
| 流式 | `checking` 时句子 key `Checking context`，`Check setup` 不可用。PoC 的 check 不跑模型，只把状态写成 `waiting-context` 或表里的其他 kind |
| 错误 | 状态 `error` 用 key `Check needs attention`。写入失败用 key `Could not update proactive mode.` 加 `Retry` |
| 无 key | 此页不发起需要 key 的 turn。不出现 2004 |
| 权限被拒 | 此表面不审批工具 |
| 讨论中断 | 此表面不出现 |

`actionsAvailable` 保持 false。不要加「启用行动」开关。
