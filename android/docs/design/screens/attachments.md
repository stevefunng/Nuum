# 附件

Mac：`workspace.tsx` 的输入框附件，读取在 `attachment-files.ts`，限额在 `packages/protocol/src/attachments.ts`。

限额：最多 5 个，单个 10MiB，合计 20MiB。图片 MIME 只接受 jpeg / png / gif / webp。图片字节只活在这一轮，不写进转录 JSONL。点历史附件在 Mac 上是 `shell.openPath`；Android 用 `DesktopPort` 打开，失败则分享。

## 选择

入口在输入框加号菜单，key `Add attachment`，图标 `attach`。系统文件选择器多选。Mac 还支持把文件拖进 `.sand-prompt-shell`。Android 在输入框上接受系统拖放；没有拖放时选择器是完整路径。

读文件期间，输入框上方 `role="status"`：key `Reading attachments…`。此时发送和加号不可用。

失败句子，`role="alert"`，颜色 `--sand-text-danger`：

| 条件 | key |
| --- | --- |
| 读失败或重新选择 | `Could not read attachment.` |
| 总数将超过 5 | `At most 5 attachments per message.` |
| 单个超过 10MiB | `Each attachment must be 10 MB or smaller.` |
| 合计超过 20MiB | `Attachments must total 20 MB or less.` |

超过限额时不调用 `send`。已在列表里的合法附件保留。

当前模型不确认支持图片时，列表里有图片就显示 `role="status"`：key `This model has no confirmed image input support. Images will be saved as files for tools; use a vision model to view them.` DeepSeek 走这条。图片仍可作为文件交给工具，不上传给 DeepSeek。

## 待发送芯片

容器 `aria-label` key `Attachments`。横向换行，间距 `--nuum-spacing-1-5`。

单芯片最大宽 210dp，高约 48dp，padding 与 Mac 一致，底 `--nuum-bg-tertiary`，边 `--sand-border-default`，圆角 `--nuum-radius-lg`。

| 元素 | 规格 |
| --- | --- |
| 图片 | 32dp 缩略图，圆角 `--nuum-radius-sm`。非图片用图标 `attach` 18dp |
| 文件名 | `--nuum-font-size-xs`，单行省略 |
| 大小 | 至少 1KB 的显示，颜色 `--nuum-text-tertiary` |
| 移除 | 图标 `close` 14dp。`aria-label` key `Remove {name}`。`sending` 或读取中不可用 |

发送时附件随草稿交给 `AgentPort.send`。成功后芯片清空。

## 转录里的附件

用户气泡里，文本下方。每个文件一个按钮：图标 `attach` 16dp + 文件名。`title` 是路径，给辅助技术可及的长按说明可以用路径，不新写文案。点击调用 `DesktopPort` 打开。

助手 `message` 且 `payload.type === "attachment"` 时，同样的芯片放在助手列，最大宽 `min(560dp, 100%)`，圆角 `--nuum-radius-lg`。图片在气泡内最大高度 320dp，`object-fit` 保持比例，圆角 `--nuum-radius-lg`。不自动播放视频。PoC 不嵌视频播放器；非图片统一走打开动作。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 没有待发送附件：不渲染芯片容器。转录里没有附件块则不留空位 |
| 加载 | 读取中显示 key `Reading attachments…` |
| 流式 | `sending` 或 `running` 时不能加、不能移除。已发出的附件留在转录里 |
| 错误 | 上表的限额和读取 key |
| 无 key | 附件可以选好。发送时若 2004，芯片保留，alert 在输入框上方，规则同转录屏 |
| 权限被拒 | 系统选择器取消：静默，不显示错误。已授予又被收回导致打不开历史附件：alert 用 `DesktopPort` 的失败 message，不新写 key。工作区路径无权是资料页的事 |
| 讨论中断 | 此表面不出现。Room 聊天 Mac 没有附件按钮，Android 也不在共享聊天里加附件 |
