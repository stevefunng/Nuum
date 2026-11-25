# 资料

Mac：`agent-profile-panel.tsx`、`execution-widget.tsx`、身份弹窗。侧栏 key `Edit profile` 与会话顶栏 key `Open {name} profile` 都打开这一页。

compact 盖住内容列。regular 贴在内容列尾部，宽度 `clamp(300 pt, 33%, 420 pt)`，左边 1 pt `--sand-border-subtle`。进入时长 `--nuum-duration-slow`；`accessibilityReduceMotion` 为真时直接出现。不把 Mac 的三栏在 compact 上挤成三列。

accessibility label key `Nunu identity`。

## 页头

起始边文字 key `Nunu identity`。末端图标按钮 `chevron-right`（指向关闭方向），accessibility label key `Close profile`。compact 的返回同样关闭。Mac：关闭资料栏。

## 工牌

整张可点，accessibility label key `Click to edit profile`，打开身份弹窗。Mac：点工牌编辑身份。

Mac 工牌有倾斜和扫光。触控与 `accessibilityReduceMotion` 都不倾斜，iOS 始终正对。

内容自上而下，padding `28 pt 24 pt 16 pt`，最小高度约 390 pt。圆角 12 pt，等于 Mac `.sand-nunu-badge` 的 `border-radius: 12px`，介于 `--nuum-radius-lg`（10 px）与 `--nuum-radius-xl`（14 px）之间，不新命名 token。

工牌底是 Mac 的浅色纸，不是 sand 表面：`linear-gradient(125deg, #fafbf9, #e9ece9 55%, #f7f8f5)`，上面再加一道 `#858d8910` 的横线，间距 2.5 px。字色是 `.sand-nunu-badge-stage` 的 `--badge-ink` `#303432`，次级 `--badge-muted` `#6c716e`。深色模式仍用这张浅色纸和这两色，不改成 `--sand-bg-base`。焦点环 2 pt `--nuum-text-secondary`，offset 4 pt，与 `.sand-nunu-badge:focus-visible` 相同。

| 元素 | 规格 |
| --- | --- |
| 印章 | 水平居中，宽约为工牌内容宽的 88%，圆形金属环。环上的字是装饰 `NUUM · A MIND OF YOUR OWN · NUUM · ALWAYS WITH YOU · `，不进入 i18n。Mac：同一圈装饰字 |
| 肖像按钮 | 在印章中心。accessibility label key `Greet {name}`。点击只增加本地反应计数，不发送消息。矢量全身，`accessibilityReduceMotion` 为真时不缩放。Mac：打招呼不发消息 |
| 名字 | 24 pt，字重 600，字距 `-0.7 px`，单行省略 |
| 标签 | 有才显示，胶囊 |
| 描述 | 空时 key `What should this Agent do?`，并标成空 |
| 页脚 | key `Created on` 加 `YYYY/MM/DD`。右侧 Nuum 签名矢量，accessibility label 为 `Nuum` |

## 身份弹窗

标题 key `Nunu identity`。关闭 key `Close dialog`。取消或关闭都不落盘。Mac：取消不保存。

| 字段 | 标签 key | 占位 key |
| --- | --- | --- |
| 名字 | `Name` | 无。空则警告 key `Name cannot be empty.` |
| 标签 | `Tags (optional)` | `Research, design, operations`。按逗号、顿号、换行拆开，去重 |
| 描述 | `Description` | `What should this Agent do?` |

模板区只在 `nuum-identity-edited` 里还没有这个 id 时出现。标题 key `Recommended templates`。三个按钮只填文字，不改 `avatarColor` / `shape` / `material`。按钮上的 18 pt 头像用模板自己的 `colorId` 和 `shape`，材质 `matte`，仅作识别。Mac：模板不改已经掷出的外观。

| 按钮标题 key | 描述 key | 点下去填入的标签 key |
| --- | --- | --- |
| `Researcher` | `Track a topic, read sources, and bring back concise findings.` | `Research, sources` |
| `Project partner` | `Stay with one project, remember decisions, and help move it forward.` | `Projects, follow-ups` |
| `Daily operator` | `Handle recurring local tasks and keep an eye on follow-ups.` | `Daily tasks, reminders` |

按钮：key `Cancel`；主按钮 key `Finish`，保存中 key `Saving…`。成功后写入「已编辑」标记并关闭。失败警告：`NuumError.message`，或 key `Could not save. Please try again.`

工牌上的名字、标签、描述在身份保存成功后更新。创建页已经写过的形状和颜色不动。

「已编辑」标记放在 UserDefaults suite `nuum-ui`，对应 Mac 记在本地的身份模板是否编辑过。不是秘密。

## 工作区与权限

节标题 key `Workspace and permissions`。放在工牌下面，左右与页边距 `--nuum-spacing-4`。

| 行 | 规格 |
| --- | --- |
| 个人工作区 | 标签 key `Personal workspace`。按钮 key `Open folder`。路径用 `workspace.projectRoot` 的可显示字符串，等宽，可断行。Mac：`Open folder` |
| 没有路径 | 路径位置改显示 key `No workspace selected`。按钮仍是 `Open folder`，点击走 `fileImporter` 或容器内托管目录 |
| 房间说明 | key `Room tasks use the shared room workspace.` |
| 命令 | 标签 key `Command execution`。选项两个：`ask` 显示 key `Allow inside sandbox`；`never` 显示 key `Deny`。改动立即 `AgentPort` 保存。Mac：`ExecutionWidget` |
| 本机授权 | 有 `externalGrants` 才出现折叠，摘要 key `Local computer permissions`。每条一个 key `Revoke` |
| 记住的命令 | 有 `commandGrants` 才出现。摘要 key `Remembered commands ({count})`。每条 key `Revoke` |
| 网络 | 标签 key `Tool network`，右侧固定 key `Denied by default`。没有 grant 时说明 key `Network access requires your approval.`。有则列出，每条 key `Revoke` |

说明 key `Permission applies only to this Nunu and workspace.` 可以放在命令行下面，`--nuum-text-tertiary`，`--nuum-font-size-sm`。

保存中相关控件禁用。失败警告用 `NuumError.message`。

`Open folder` 在已有托管目录时打开系统查看；在用户选过 bookmark 树时用该 bookmark，使用前 `startAccessingSecurityScopedResource()`。系统已经收回授权：路径行显示 key `No workspace selected`，再点 `Open folder` 重新选择。这对应 `NO_WORKSPACE`（2003）之后的修复路径，不新写句子。

不在这一页放 shell 窗口。命令策略只是 `ask | never` 的保存。Mac 的 `ExecutionWidget` 保存的就是这两档。

删除 Nunu、从侧栏隐藏、会话内换模型：Mac 上没有，iOS 也不做。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 描述为空时工牌用 key `What should this Agent do?`。授权列表为空则不渲染那些折叠 |
| 加载 | profile 未到：页头仍在，工牌区空白。不显示别的 Nunu 的缓存 |
| 流式 | 此页不收集 delta。头像可以是 `working`，打招呼仍只动本地 |
| 错误 | 身份或执行偏好保存失败的警告 |
| 无 key | 此页不发送消息，不出现 2004 |
| 权限被拒 | bookmark 失效时路径回到 key `No workspace selected`。命令选了 `Deny` 是用户的策略，不是一条错误 |
| 讨论中断 | 此表面不出现。中断条在 [room.md](./room.md) |
