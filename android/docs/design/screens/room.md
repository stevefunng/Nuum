# Room

Mac：`WorkCreation` 选择 `room`，以及 `WorkBoard` 在 `snapshot.profile.kind === "room"`。升级后的界面是 [nunubar-lanes.md](./nunubar-lanes.md)。

产品名保持 `Room` 与 key 里的「本地群聊」。升级按钮把 kind 设为 `work`，成员和历史保留。升级后的工作区叫 `NunuBar`。

## 创建

侧栏 key `Create NunuBar` 打开创建页（Mac 的菜单项叫创建 NunuBar，页内仍可选 Room）。内容列替换，不是小弹窗。

卡片水平居中，最大宽 520dp，padding `--nuum-spacing-6`。

| 元素 | key |
| --- | --- |
| 眉题 | `A place for the job, not another chat` |
| 标题 | `Create a Work` |
| 说明 | `Keep tasks, shared discussion, Agents, capabilities, and deliverables together.` |
| 种类 | `Local room` 与文字 `NunuBar`。`aria-pressed` 标出当前。默认 Mac 是 `work`；从「新建」进来时同样默认 `work`，用户点 `Local room` 改成 room |
| 名字标签 | `Name` |
| 占位 | `e.g. Product launch` |
| 取消 | `Cancel`。仅当可以返回已有内容时显示 |
| 创建 | `Create Work`。名字空白则不可用 |

提交 `{ name: trim, kind: "room" | "work" }`。选 `work` 时创建完成后进入 NunuBar，不经过 Room。选 `room` 时进入下面的 Room 页。

不在创建页收集目标字段。key `Goal` 与 `What should this Work accomplish?` 是 Mac 文案表里的句子；当前 `WorkCreation` 没有这个输入。Android 同样不画。

## Room 页

顶栏标题是 `workDisplayTitle(name)`：去掉前缀 `work bar` 或 `nunubar` 加分隔符，去不掉就用原名。手机起始边有抽屉按钮。

标题下一行：起始边 key `Local room`，末端按钮 key `Enable task board`。点击 `work.update { kind: "work" }`。没有确认对话框，与 Mac 相同。

`discussionRunning` 时顶栏末端还有 key `Stop discussion`。

成员审批条在标题下面，规则见 [approval-bar.md](./approval-bar.md)。Room 上的 pending 画在这里，不画进成员的一对一。

中断区在聊天上方，`role="status"`。每条：

- 有 `agentId` 时前缀该成员名字加冒号
- 正文用 `t(item.error)`。已知 key 包括 `Discussion interrupted. Continue starts a new bounded discussion.`、`Execution interrupted. Check tools and published results before continuing.`、`Execution failed. Check the result before continuing.`、`Previous room history is preserved. Continue only if this discussion still needs a response.`、`Room context is too large. No new room input was consumed; narrow the history range before continuing.`、`A room response failed. Check the model settings and dispatch again.`
- 按钮 key `Continue`，调用 `work.continue`
- 没有 `taskId` 的讨论条可以展开 key `Use less room history`。里面标签 key `Only include the most recent messages`，数字框最小 1、最大为当前聊天条数。按钮 key `Continue with this history`

共享聊天在 Room 里默认展开，占内容列剩余高度。规格：

| 元素 | key 或规则 |
| --- | --- |
| 标题 | `Shared room` 加条数 |
| 关闭 | Room 里展开是 `expanded`，关闭按钮仍在，`aria-label` key `Close shared room`。Room 下一次聚焦输入框会再打开，与 Mac `expanded || opened` 相同 |
| 列表 | `role="log"`，`aria-label` key `Shared room messages` |
| 空 | key `No messages yet.` |
| 用户消息 | 末端，气泡用 `--sand-fill-bubble-user`，字 `--sand-text-on-color`。不写 key `You`，Mac 的用户行也没有作者名 |
| 成员消息 | 起始，作者名是成员 `profile.name`，找不到用 key `Agent`。正文 GFM |
| 输入 | `aria-label` key `Message the Work`，占位 key `Message the Work…` |
| 发送 | `aria-label` key `Post message`。空白不可用 |

没有 @ 选择器。用户在正文里自己打 `@名字`。Host 解析 @。不新做提及菜单。

没有附件按钮。

右侧或手机上的下一段是成员与能力，见 [capability-catalog.md](./capability-catalog.md) 与下面的成员区。≥ 840dp 时它们在尾部检查器里。默认宽 250dp（`nuum.ui.workInspector.v1`），夹在 184dp 与 `min(380dp, 列宽 - 440dp)` 之间，可拖，`aria-label` key `Resize Work inspector`。检查器底 `--nuum-bg-editor`，左边 1dp 用 `--nuum-text-primary` 的 9%。手机上检查器改成聊天下面的全宽两节，不保留 184dp 窄列。

成员节标题 key `Agents` 加人数。每一行：头像 34dp，名字，移除按钮 `aria-label` key `Remove {name}`。点击头像打开状态气泡，再点关闭。气泡 `aria-label` key `Status of {name}`。气泡文案：

| 活动 | key |
| --- | --- |
| 卡片 | `Working on card`，有标题则后面加全角冒号和标题 |
| idle | `Idle` |
| error | `Run failed` |
| discussion | `Discussing` |
| elsewhere | `Working in another session` |

空成员时投放说明 key `拖到此处以添加Nunu到当前NunuBar`。拖入时 key `Release to add Agent`。拖出时 key `Drop outside to remove`。长按侧栏里的 Nunu 落到这一区即加入。长按成员拖出即离开，用当前 `revision`。

Room 不显示任务泳道，不显示 `Tasks` / `产物` 切换。那些在升级之后出现。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 聊天空用 key `No messages yet.`。成员空用投放说明。没有「新建任务」空态，因为 Room 没有泳道 |
| 加载 | snapshot 未到：顶栏可以显示侧栏点过的名字，中部空白，升级按钮先不可用 |
| 流式 | `discussionRunning` 时显示 key `Stop discussion`。成员头像可为 `working`。聊天按 `work.event.appended` 追加。不在这一页画模型自由文本，只画已经 `PostToWork` / `chat.posted` 的句子 |
| 错误 | 创建或升级或发言失败：内容列顶部 `role="alert"` 用异常 message。Mac 的 `workNotice` 用同样的条 |
| 无 key | 发言后若某个应答者没有 key，中断或错误句子用 Host message / key `A room response failed. Check the model settings and dispatch again.`。不把 key 写进聊天 |
| 权限被拒 | 成员审批条点 `Deny`。条的规则在审批规格。Room 页本身不另做拒绝页 |
| 讨论中断 | 中断区可见，主按钮 key `Continue`。上下文过长时必须能改「最近消息数」再继续 |

不提供用户建卡按钮。key `New task`、`Create task`、`A new task` 不出现在 Room。
