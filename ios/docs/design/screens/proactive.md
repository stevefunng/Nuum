# Proactive 面板

Mac：`packages/ui/src/proactive/proactive-panel.tsx`，由菜单栏窗口 `?surface=proactive` 打开。设置按钮 key `Open menu bar panel` 在 Mac 上调用 `showProactive()`。

iOS 从设置 General 的同一按钮进入，key 仍是 `Open menu bar panel`。不要求菜单栏常驻。没有托盘，没有常驻通知，没有第二扇窗口，不渲染 key `Quit`。

打开这一页时现算 snapshot。不移植每秒 tick，也不在后台跑模型。不声明 `UIBackgroundModes`。

compact 从设置推入，占满内容列。regular 时侧栏留着，这一页占内容列。底 `--nuum-bg-elevated`，内边距 `--nuum-spacing-5`（20 px），可滚动。返回回到设置的 General，不退出应用。

字标行：左边文本 `Nuum`，17 pt，字重 650，字距 `-0.5 px`，颜色 `--nuum-text-primary`。右边文本 `Proactive mode`，`--nuum-font-size-xs`，`--nuum-text-secondary`。二者都是产品名，不另译。Mac：同一字标行。

## 状态卡

圆角 `--nuum-radius-2xl`（Mac `.nuum-proactive-status` 的 `16px`），padding `17 pt 16 pt 0`，底是 `--nuum-text-primary` 的 4% 混合在透明上（Mac `color-mix`）。点 6 pt。

标题用当前 agent 的 `name`，没有则文本 `Nunu`。字号 23 pt，字重 600。

说明：`paused` 用 key `Your companion will resume after this break.`，其他状态用 key `A quieter kind of help, at the right moment.`

开关行顶边 `--nuum-stroke-tertiary`，最小高 `--nuum-spacing-12`。Mac `.nuum-proactive-toggle-row` 用的就是这个变量。标签 key `Proactive mode`。开关 accessibility label key `Enable proactive mode`。开的时候轨道用 `--nuum-text-primary`，钮用 `--sand-text-on-primary`。关的时候轨道用 `--sand-fill-control-track`。点按发送 `enabled` 取反，并把 `pausedUntil` 置空。Mac：同一开关。

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

`#80856b`、`#aa8a52`、`#bd615a` 是 Mac `.nuum-proactive-status` 写死的点色，不在 sand 表里。沿用这三个点色，以免把「暂停 / 就绪 / 出错」收成同一种 `--sand-fill-*`。其余界面仍只用 sand 变量。

## 操作

两个控件横排，间距 `--nuum-spacing-2`，各占一半。视觉高度约 36 pt，热区 `--nuum-spacing-11`，圆角 `--nuum-radius-lg`，边 `--sand-border-subtle`。

| 条件 | 控件 |
| --- | --- |
| `paused` | 按钮 key `Resume now`。把 `pausedUntil` 清空。Mac：`Resume now` |
| 其他 | 选择器 accessibility label key `Pause proactive mode`。当前显示 key `Pause…`。选项 key `For 30 minutes`（值 1800000）、`For 1 hour`（值 3600000）。选中后 `pausedUntil = now + 毫秒`。未开启时整个选择器不可用。Mac：同一暂停选项 |
| 始终 | 按钮 key `Check setup`。未开启、暂停中、`checking` 或没有 snapshot 时不可用。Mac：`Check setup` |

暂停中且有 `pausedUntil`：居中 key `Resumes at {time}`，时间用应用语言的时分。

`Check setup` 不发起需要模型的 turn。没有 source 时 `check` 记下 `waiting-context`。不在后台跑这次检查。

## 连接

accessibility label key `Connections`。两行，左边标签，右边状态：

| 标签 key | 右侧 |
| --- | --- |
| `Context sources` | `availableSourceIds` 非空则 key `Available`，否则 key `Not connected` |
| `Agent actions` | 永远 key `Not connected`。来自 snapshot 的 `actionsAvailable === false`，界面不写死一个可切换的开关 |

段落下 key `Setup is ready. Context collection and autonomous actions are not enabled in this version.`，颜色 `--nuum-text-tertiary`。

`actionsAvailable` 保持 false。不要加「启用行动」开关。Mac 这一版的面板也把行动显示成未连接。

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

右边是本地时分。Mac：同一活动表，最多 3 条。

## 失败与页脚

更新失败：警告，颜色 `#b85850`（Mac `.nuum-proactive-error`），句子 key `Could not update proactive mode.`，按钮 key `Retry`。Retry 再发上一次的 configure 或 check。

页脚顶边 `--nuum-stroke-tertiary`，与 Mac `.nuum-proactive-footer` 相同。只有起始边一个按钮：

| 条件 | key | 行为 |
| --- | --- | --- |
| 有默认 agent | `Open Nunu` | 关掉这一页，打开该 Nunu 的会话。Mac：`Open Nunu` |
| 没有 | `Open Nuum` | 关掉这一页，回到未选中的壳；compact 上回到侧栏列。Mac：`Open Nuum` |

不渲染 key `Quit`。Mac 的菜单栏窗口有 `Quit`，因为进程留在托盘里。iOS 不要求菜单栏常驻，页脚没有退出进程的按钮。

配置调用要带 `agentId` 与 `expectedRevision`。冲突时警告用上面的失败 key，不覆盖用户刚看的开关直到重试成功。Mac：带 revision 的 configure。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 活动列表空：key `Activity will appear here when you turn it on.`。没有 agent 时标题是 `Nunu`，开关不可用 |
| 加载 | snapshot 还没有：句子 key `Connecting to Nuum…`，开关与两个按钮不可用 |
| 流式 | `checking` 时句子 key `Checking context`，`Check setup` 不可用。这次 check 不跑模型，只把状态写成 `waiting-context` 或表里的其他 kind |
| 错误 | 状态 `error` 用 key `Check needs attention`。写入失败用 key `Could not update proactive mode.` 加 `Retry` |
| 无 key | 此页不发起需要 key 的 turn。不出现 2004 |
| 权限被拒 | 此表面不审批工具。审批在 [approval-bar.md](./approval-bar.md) |
| 讨论中断 | 此表面不出现。中断条在 [room.md](./room.md) |

登录，以及把 Proactive 同步到另一台设备的开关：Mac 上没有，iOS 也不做。
