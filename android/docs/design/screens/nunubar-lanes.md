# NunuBar 泳道

Mac：`WorkBoard` 在 `kind === "work"`，泳道与交付物在 `work-content.tsx`。Room 升级按钮或创建时 kind 为 `work` 进入这一页。共享聊天、成员、审批、中断的结构与 [room.md](./room.md) 相同，差别是聊天默认收起，以及中部换成任务 / 产物。

没有「新建任务」按钮。`onCreateTask` 在 Mac 的 `WorkBoard` 里没有被调用。卡片来自模型 `CreateTask`。key `New task` 不渲染。

## 顶栏

标题是 `workDisplayTitle(name)`：去掉前缀 `work bar` 或 `nunubar` 加分隔符，去不掉就用原名（`work-layout.ts`）。`discussionRunning` 时有 key `Stop discussion`。存在 `blocked` 卡时显示计数加 key `Blocked`，颜色 `--sand-text-warning`。

审批条在顶栏下。中断条在泳道和聊天之间，规则同 Room。执行类句子还包含 key `Card execution ended without a handoff. Continue or cancel the card.`、`Legacy execution requires confirmation before continuing.`、`This card is paused until you confirm how to proceed.`（最后这句在卡片详情里）。

## 任务 / 产物切换

一行按钮，`aria-label` 随当前页变化：在任务页时 key `切换到产物`，在产物页时 key `切换到 Tasks`。可见文字是当前页的强调加另一页的弱化：

| 当前 | 强调 key | 弱化 key |
| --- | --- | --- |
| 任务 | `Tasks` | `产物` |
| 产物 | `产物` | `Tasks` |

两页叠在同一区域，非当前页 `aria-hidden`，不可聚焦。切换没有 3D 翻转。减弱动态效果时直接换页；否则可用 `--nuum-duration-normal` 的透明度。

## 泳道

七列，顺序固定：

| `data-state` | 标题 key |
| --- | --- |
| `proposed` | `Proposed` |
| `ready` | `Ready` |
| `in_progress` | `In progress` |
| `blocked` | `Blocked` |
| `review` | `Review` |
| `done` | `Done` |
| `cancelled` | `Cancelled` |

每列 `aria-label` key `{state} tasks`，`{state}` 是上表标题译好的句子。列头：6dp 状态点、标题、计数。点的颜色跟 `work-board.css`：

| 状态 | 点 |
| --- | --- |
| `in_progress` | 填充并描边 `--nuum-text-blue-primary` |
| `blocked` | 填充并描边 `--nuum-text-orange-primary` |
| `done` | 填充并描边 `--nuum-text-green-primary` |
| `review` | 只改描边为 `--nuum-text-magenta-primary`，不填色 |
| 其余 | 描边 `--nuum-text-tertiary`，不填色 |

列的轨道是横向滚动。每列 `minmax(200dp, 1fr)`，列间距 18dp，左右 padding `--nuum-spacing-6`。手机上七列超出内容列，可以横滑，不要把列宽压到 200dp 以下。底栏状态点：未选中 4dp、`--nuum-text-tertiary`、不透明度 0.4；选中改为 `--nuum-text-secondary` 并放到 1.3 倍。减弱动态效果时不缩放。

滚动与点按：

- 点的 `aria-label` 是「标题: 计数」
- 上方的文字导航在点按时展开，按钮 `aria-pressed` 标出当前列
- 导航 `aria-label` key `Task states`
- 点按把该列滚进视口。减弱动态效果时立即跳转

空列：key `No tasks`，`--nuum-text-tertiary`。

卡片按钮，`aria-label` key `Open task: {title}`。最小高度 112dp，padding 15dp，圆角 `--nuum-radius-lg`（10px），底 `--nuum-bg-elevated`，边是 `--nuum-text-primary` 的 9%（Mac 局部变量 `--work-edge`，不新起名字）。阴影用同一文件里的 `--work-relief`：`0 1px 2px` 的 6% `--nuum-text-primary`，再加 `0 5px 12px -4px` 的 10%。标题 12dp，等于 `--nuum-font-size-sm`。描述最多两行，10dp，颜色 `--nuum-text-secondary`。10dp 不在字阶上，与 Mac `.sand-work-task-card p` 一致，不四舍五入成新 token。

| 行 | 内容 |
| --- | --- |
| 标题 | `task.title`，字重 600 |
| 描述 | 有则显示，最多两行，`--nuum-text-secondary` |
| 脚 | 最多三个 20dp 头像。名字用 `, ` 连接；没有负责人则 key `Unassigned` |
| 文件 | 有交付物时 key `{count} files` |

点击打开详情，不在列上直接改状态。

## 产物页

没有已完成卡：图标 `attach` 22dp，标题 key `暂无产物`，说明 key `Agent 团队交付的文件会汇集在这里。`

每张已完成卡：标题、状态 key、负责人或 key `Unassigned`。点标题打开同一张详情。

每个文件一行：文件名、`mimeType` 或 key `File`、日期。按钮在未复制时 key `复制路径`，成功后 key `已复制`。失败 key `无法复制，请选择上方路径手动复制。` 路径用等宽显示在文件名下，用户可以自己选择。

有已完成卡但没有任何文件：key `该任务还没有交付文件。`

## 卡片详情

对话框标题是任务标题，副标题是状态 key。关闭 key `Close dialog`。手机可全屏。

按有无渲染：

| 块 | 规格 |
| --- | --- |
| 描述 | 有则一段 |
| 负责人 | 标签 key `Card owner` |
| 执行成员 | 标签 key `Workers`。头像 24dp 加名字。空则 key `Unassigned` |
| 优先级 | 标签 key `Priority`。值 key `Low` / `Normal` / `High` / `Urgent` |
| 验收 | 标题 key `Acceptance criteria`，列表 |
| 阻塞 | key `Blocked:` 加原因 |
| 产物 | 标题 key `产物`，文件名与 URI |
| `blocked` | 说明 key `This card is paused until you confirm how to proceed.`。按钮 key `Confirm and resume`（迁到 `in_progress`）、`Cancel task`（迁到 `cancelled`）。带上 `revision` |
| `review` | key `Request changes`（`in_progress`）、`Accept delivery`（`done`） |
| 执行记录 | 按钮 key `Execution history`。空 key `No execution history yet.`。会话选择器 `aria-label` 同 key。更早 key `Load earlier`。记录是折叠的 seq 与 type，正文等宽。这不是 shell |
| `ready` 或 `in_progress` | 选择器 `aria-label` key `Choose worker`，占位同 key。只列出 `canManageOwnTasks` 的成员。输入占位 key `Instruction for the Agent`。按钮 key `Run`。缺人或指令空白则不可用。调用 dispatch |

用户不能在详情里把状态改成任意值。只有上表这些按钮。blocked 的迁移要带 reason 的契约由 Host 用卡片上已有的 blocker 完成；这一页不新做原因输入，除非 Host 拒绝缺少 reason。若拒绝，alert 用异常 message，并保留按钮。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 每列 key `No tasks`。产物页 key `暂无产物`。执行记录空 key `No execution history yet.` |
| 加载 | snapshot 未到：切换按钮不可用，泳道不显示假列 |
| 流式 | 成员 `running` 时头像为 `working`。泳道上的卡要等 `CreateTask` / 状态事件落到 snapshot 才出现，不本地插一张临时卡。讨论进行中仍有 key `Stop discussion` |
| 错误 | 迁移、派发、读记录失败：详情内 `role="alert"`。页级失败用 Room 同一条顶部 alert |
| 无 key | 派发后模型没有 key：中断或 alert 使用 Host message，不写入 key 字符 |
| 权限被拒 | 成员审批在本页顶部的审批条。点 `Deny` 后该条消失 |
| 讨论中断 | 与 Room 相同的中断区。带 `taskId` 的条不展开「缩短历史」，只保留 key `Continue` |

进程重启后不得把卡显示成「正在跑」，除非内存里真有 run。卡的 `in_progress` 状态可以还在，那是任务状态，不是 `AgentRuntime.status`。
