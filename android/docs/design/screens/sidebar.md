# 侧栏

Mac：`packages/ui/src/conversation/sidebar.tsx`、`sidebar-menu.tsx`、`sidebar-organization.ts`、`sidebar-resize.tsx`。

容器在 [layout.md](../layout.md)：手机是抽屉，≥ 840dp 是左侧分栏。下面的行、菜单、搜索在两种容器里相同。

`aria-label`：key `Agents`。列表 `aria-label`：key `Agent list`。

## 结构

自上而下：

1. 顶栏。展开时靠末端放两个圆形图标按钮，图形盒 `--nuum-height-sm`，热区 48dp，间距 `--nuum-spacing-2`。
   - 搜索：图标 `search`。`aria-label` 与 `title` 都是 key `Search`。`aria-expanded` 跟搜索框开关走。
   - 新建：图标 `plus`。`aria-label` key `New`。`title` key `New agent`。`aria-haspopup="menu"`。
2. 搜索框。仅当搜索开着或已经有查询词，且侧栏未折叠。左边图标 `search` 16dp。输入框占位 key `Search`，单行，底边 `--sand-border-subtle`，文字 `--nuum-text-primary`。
3. 置顶投放带。默认隐藏；拖着一个 Nunu 时出现。文案 key `拖到此处置顶`。底 `--sand-fill-secondary`，圆角 `--nuum-radius-lg`。
4. 列表，可滚动，底 `--nuum-bg-chrome`。
   - 置顶区 `aria-label` key `Pinned Agents`。有置顶才渲染。
   - 每个分组一节。标题行：chevron 10dp + 组名 + 人数。chevron 在折叠时指向行尾方向，展开时旋转 90°。末端 `···`，`aria-label` key `Actions for {name}`。
   - 组内没有人且未折叠：key `Drag an Agent here`，字号 `--nuum-font-size-xs`，颜色 `--nuum-text-tertiary`。
   - 未分组区。仅当已经有分组且这一区有行时，显示标签 key `Unassigned` 和计数。
5. 底栏。设置：图标 `sliders`，`aria-label` key `Settings`。折叠轨里新建按钮移到底栏，设置仍在。

折叠（仅 ≥ 840dp，宽 88dp）时隐藏顶栏两个按钮以外的文字、隐藏搜索框、隐藏分组标题。头像用 40dp。

## 一行

Nunu 与 work 共用 `.sand-agent-item` 的节奏。

| 元素 | 规格 |
| --- | --- |
| 行高 | 最小 56dp。内边距左右 `--nuum-spacing-3`（12px），上下 `--nuum-spacing-2` |
| 头像 | 展开 34dp；置顶 52dp；折叠 40dp。矢量，见 [design-system.md](../design-system.md) §7 |
| 运行点 | `runtime.status === "running"` 时叠在头像右下，8dp，`--sand-fill-accent` |
| 名字 | `--nuum-font-size-base`，字重 500，单行省略 |
| 预览 | 转录最后一句，否则 `description`，否则 key `New Agent`。work 用 `preview`，否则 `description`，否则 key `New Work`。颜色 `--nuum-text-secondary` |
| 时间 | key `now` / `{count}m` / `{count}h` / `{count}d`。颜色 `--nuum-text-tertiary`，字号 `--nuum-font-size-xs` |
| 运行文案 | 仅 Nunu 且 running：key `Working` |
| 选中 | 底 `--sand-fill-ghost-selected`。当前 `activeId` 或 `activeWorkId` |
| work 无成员 | 方标，取名字首字母大写，34dp（折叠 40dp），圆角 11dp，底 `--nuum-bg-secondary`，边 `--sand-border-subtle` |
| work 有成员 | `WorkGroupAvatar`：最多四个成员头像拼在同一外框 |

未分组的 Nunu 与 work 按 `lastActivityAt` 降序混排。置顶不进这条混排。`hiddenFromSidebar == true` 的 Nunu 不出现。没有开关可以把它设为 true。

搜索只过滤，不建索引。Nunu 匹配名字、描述、标签。work 匹配名字、描述、`preview`。有查询词时，空分组不渲染，折叠的分组强制展开。

## 菜单

Mac 用右键。Android 用长按同一行，或点分组的 `···`。菜单从触点弹出，底 `--nuum-bg-elevated`，边 `--sand-border-subtle`，阴影 `--nuum-box-shadow-md`，圆角 `--nuum-radius-xl`。`aria-label` key `Sidebar actions`。点外面或系统返回关闭，焦点回到触发行。

Nunu 行：

| 顺序 | key | 图标 | 行为 |
| --- | --- | --- | --- |
| 1 | `Pin` 或 `Unpin` | `pin` | `toggleSidebarPin`。已在 `pinnedAgentIds` 里用 `Unpin` |
| 2 | 已有分组时 `Move to group`，否则 `Move to new group` | `folder` | 有分组则换成分组子菜单；没有则直接打开新建分组 |
| 3 | `Edit profile` | `edit` | 打开该 Nunu 的资料，分隔线在这项之上 |
| 4 | `Copy Agent ID` | `copy` | 复制 `profile.id`。失败时列表下显示 key `Could not copy Agent ID.` |

分组子菜单第一项 key `Back`，图标 `chevron-left`。然后每个分组名，图标 `folder`。然后 key `Unassigned`，图标 `sidebar`。最后一项之上有分隔线，key `New group…`，图标 `plus`。

分组标题菜单：

| key | 图标 | 何时不可用 |
| --- | --- | --- |
| `Rename group…` | `edit` | 保存中 |
| `Move up` | `arrow-up` | 已经是第一个 |
| `Move down` | `arrow-down` | 已经是最后一个 |
| `Ungroup agents` | `ungroup` | 保存中。分隔线在这项之上。成员回到未分组，组删除 |

新建菜单锚在新建按钮下，宽 `min(max(侧栏宽 - 24dp, 208dp), 300dp)`。`aria-label` key `New`。两项：

| key | 图标 | 去向 |
| --- | --- | --- |
| `Create new Nunu` | `plus` | [create-nunu.md](./create-nunu.md) |
| `Create NunuBar` | `people` | [room.md](./room.md) 的创建页，kind 初始仍由创建页自己决定 |

分组名对话框：标题 key `New group` 或 `Rename group`。关闭按钮 `aria-label` key `Close group dialog`。输入 `aria-label` 与占位都是 key `Group name`，最长 80。按钮 key `Cancel`、`Save`。保存中按钮文案 key `Saving…`。空名字不能保存。重名被协议拒绝时，对话框内 `role="alert"` 使用 Host 返回的英文句子；侧栏自己的保存失败用 key `Could not save sidebar changes. Please try again.`

## 拖拽

长按约 300ms 后拖动，对应 Mac `holdToDrag: true`。拖动中行不触发点击。

| 落下的地方 | 结果 |
| --- | --- |
| 另一条置顶 Nunu | `reorderSidebarPin` |
| 分组或置顶投放带 | `assignSidebarAgent` |
| 未分组区 | 移出分组 |
| work 行 | `onMoveAgentToWork`。这是成员关系，不是侧栏分组 |

work 行本身不能被拖去改序。系统返回或放下到空白：取消，列表回到拖动前。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 没有任何可见 Nunu 且没有任何 work：列表区 key `No agents yet`。查询无结果：key `No matching agents`。二者都用 `--nuum-text-tertiary`，`--nuum-font-size-xs` |
| 加载 | 列表投影还没从本地读出：行位置放三个高 56dp 的条，底 `--sand-fill-secondary`，没有闪烁动画（避免和流式 shimmer 混）。顶栏新建和设置可点 |
| 流式 | 此表面不追加 delta。某个 Nunu `running` 时该行显示状态点和 key `Working` |
| 错误 | 组织保存失败：key `Could not save sidebar changes. Please try again.`，`role="alert"`，颜色 `--sand-text-danger`。复制失败用 `Could not copy Agent ID.` |
| 无 key | 此表面不出现。发送失败在 [conversation-transcript.md](./conversation-transcript.md) |
| 权限被拒 | 此表面不出现。审批在 [approval-bar.md](./approval-bar.md) |
| 讨论中断 | 此表面不出现。中断条在 [room.md](./room.md) |

冷启动没有 `running`。进程被杀后重新打开，侧栏上不得留着状态点。
