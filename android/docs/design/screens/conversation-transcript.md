# 有转录的会话

Mac：`packages/ui/src/conversation/workspace.tsx`，分组规则 `activity-groups.ts`。

内容列底色 `--nuum-bg-editor`。用户气泡颜色来自当前 Nunu 的 `chat` 色素，文字 `--sand-text-on-color`。

## 顶栏

高度与安全区见 [layout.md](../layout.md)。

身份按钮：头像 28dp，状态来自运行投影（`idle / thinking / working / waiting / error / sending / receiving`）。名字 `--nuum-font-size-base`，字重 600。`running` 时名字旁小字：

| 头像状态 | key |
| --- | --- |
| `waiting` | `Waiting for approval` |
| `thinking` | `思考中` |
| 其他 running | `Working` |

`aria-label` key `Open {name} profile`。点击打开 [profile.md](./profile.md)。没有资料回调时按钮不可用，Mac 用 `disabled={!onOpenProfile}`。

手机起始边另有抽屉按钮，key `Agents`。

## 转录

`role="log"`，`aria-label` key `Conversation transcript`。内边距上 `--nuum-spacing-12`（48px），左右 `--nuum-spacing-4` 加 2dp（Mac 18px），下 `--nuum-spacing-7`（28px）。顶部用 `--sand-gradient-bg1-fade` 做 46dp 淡出，盖住滚到顶栏下的文字。

行间距 `--nuum-spacing-4`。新内容出现时，若用户已经贴着底部，则滚到底。用户向上滚动后，不要抢滚动。reduced motion 时滚动不使用平滑动画。

时间分隔：相邻块间隔超过 5 分钟才插入。当天 key `Today {time}`，昨天 key `Yesterday {time}`，更早用系统短日期。胶囊底 `--nuum-bg-elevated`，字 `--nuum-text-tertiary`，`--nuum-font-size-sm`，圆角 `--nuum-radius-full`，左右 padding `--nuum-spacing-2` 加 `--nuum-spacing-0-5`。

块种类：

| `ViewBlock.type` | 画法 |
| --- | --- |
| `user` | 末端对齐。气泡圆角 `--nuum-radius-4xl`，padding `8dp 12dp`，最大宽度见布局文档。正文 `--nuum-font-size-lg`，行高 `--nuum-line-height-lg`。附件芯片见 [attachments.md](./attachments.md) |
| `message` | 可见的 `SendMessage`。文本用助手气泡，底 `--sand-fill-bubble-agent`，字 `--nuum-text-primary`，起始对齐，最大 `min(88%, 640dp)`。`attachment` 载荷画附件芯片。`widget` 见 [widget.md](./widget.md) |
| `notice` | 居中胶囊，同时间分隔的颜色。`kind === "profile"` 且原文匹配 `This agent changed name to "(.*)".` 时用 key `This Nunu changed name to "{name}".`，否则 key `This Nunu changed its profile.`。`kind === "wake"` 且原文以 `Participated in room: ` 开头时用 key `Participated in room: {name}`。压缩类原文若能对上 key `Earlier conversation was summarized.` 或 `Earlier messages were summarized to fit the context window. The originals are still on disk.` 就用该 key |
| `peer` | 一行按钮。头像 20dp，状态发出为 `sending`、收到为 `receiving`。名字。`priority` 为真时加 key `Priority`。点击打开 peer 抽屉 |
| `assistant` | 活动组，不是用户能读的自由文本。见下节 |

用户看不见模型的自由文本。`assistant` 块只承载 thinking 状态和工具。`groupToolActivity` 把相邻活动并成一组。

### 活动组

- 没有工具且 `live`：一行 key `思考中`，颜色 `--nuum-text-tertiary`，字号 `--nuum-font-size-sm`。可带 `--sand-gradient-text-shimmer`。默认不展开思考原文。
- 一条工具：折叠的 `details`。摘要是工具标签 + 状态。
- 多条工具：摘要 key `{count} tool calls`，再加中间点与状态。展开后里面仍是单条工具。

状态 key：进行中 `执行中`，失败 `失败`，成功 `已完成`。

工具标签 key：

| 工具名 | key |
| --- | --- |
| `bash`、`shell` | `Bash` |
| `external_operation` | `Local operation` |
| `request_network` | `Network access` |
| `read` | `Read` |
| `ls` | `List` |
| `write` | `Write` |
| 其他 | 把 camelCase 拆成英文单词，不发明中文 |

展开后两段：key `Arguments`，等宽 JSON；有输出时 key `Output`，空字符串用 key `(no output)`。等宽用 `--nuum-font-family-mono`。这里不是终端：没有光标，没有命令输入。`shell` 的输出若是「PoC 未实现」的英文句子，原样放在 `Output` 里。

工具卡外观：padding `10dp 12dp`，边 `--sand-border-subtle`，圆角 12dp，底 `--nuum-bg-elevated`。

### 运行中的身体

`running` 时，输入框上方一行：全身头像 40dp，旁边 key 与顶栏小字相同（`Waiting for approval` / `思考中` / `Working`）。审批条若出现，放在这一行和输入框之间。一对一里，pending 带 `workId` 时不画审批条，改到 NunuBar 该成员的条上。见 [approval-bar.md](./approval-bar.md)。

## 输入框

停在内容列底部，底色 `--nuum-bg-editor`，左右 `--nuum-spacing-3`，下边加导航栏安全区。

壳层圆角 `--nuum-radius-3xl`，边 `--sand-border-default`，底 `--nuum-bg-input`。

| 控件 | 规格 |
| --- | --- |
| 文本 | 多行，最高约 120dp 后内部滚动。占位 key `Message {name}`。`sending` 时不可编辑 |
| 加号 | `aria-label` key `Composer actions`。打开菜单，菜单里只有一项：图标 `attach`，key `Add attachment`。没有 Nunu、正在读文件或 `sending` 时不可用 |
| 发送 | `running` 时换成停止：图标 `stop`，`aria-label` key `Stop`，调用 `agent.cancel`。否则图标 `arrow-up` 16dp，`aria-label` key `Send message`。草稿空白且没有附件时不可用。读文件中不可用 |
| Enter | 软键盘的发送动作等价于点击发送。换行仍可用。输入法组字期间不发送 |

发送走 `AgentPort.send`。停止走 `agent.cancel`。取消成功时输入框上方可以出现 key `Stopped.`（Mac 在 `turn.ended` status `cancelled` 时写入 notice）。不要把取消画成错误红条。

`notice` 出现在输入框上方，颜色 `--nuum-text-tertiary`，字号 `--nuum-font-size-xs`。若是失败，改成 `role="alert"`，颜色 `--sand-text-danger`。

Markdown：助手可见消息用与 Mac 相同的 GFM 子集（段落、列表、代码、链接）。链接色 `--nuum-text-link`。代码块底 `--nuum-bg-elevated`，等宽。不渲染 mermaid 执行、不渲染 KaTeX 字体包；公式以等宽原文显示。这是 PoC 的阅读降级，避免把桌面字体打进 APK。

## peer 抽屉

Mac：`PeerConversation`。标题 key `Conversation between {first} and {second}`。关闭 key `Close agent conversation`。

手机：底部表面，最高占窗口 88%，顶圆角 `--nuum-radius-3xl`，遮罩 `--sand-bg-scrim`。≥ 840dp：内容列内的卡片，最大宽 640dp。

头部两个头像 30dp，中间不写额外产品名。时间线只包含与该 peer 的 `peer` 块。发出的气泡用当前 Nunu 的 `chat` 色，收到的用 `--sand-fill-bubble-agent`。每条可以有 key `To` / `From` 的方向已经由左右对齐表达；Mac 的摘要行用 peer 名字，抽屉里同样靠左右，不另加一套标题。

点遮罩或系统返回关闭。关闭后转录位置保持。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 有选中 Nunu 但块数为 0 时不画这一屏，画 [conversation-empty.md](./conversation-empty.md) |
| 加载 | 转录尾部未返回：列表区空白，顶栏名字已在。不显示空态字标 |
| 流式 | delta 追加到当前可见消息或活动组。`思考中` 或 `执行中` 可见。停止按钮替换发送 |
| 错误 | `agent.error` 的 `message` 放在输入框上方，`role="alert"`。兜底 key `Host error`。取消不走这条。工具失败在活动组里用 key `失败`，不弹模态 |
| 无 key | 发送被 2004 拒绝。alert 使用异常 message，草稿保留。转录不追加带 key 字样的气泡 |
| 权限被拒 | 用户在审批条点 key `Deny` 之后，条消失。随后的工具活动若以错误结束，状态用 key `失败`。`never` 不是这一屏的按钮 |
| 讨论中断 | 此表面不出现。Room 的中断不画在一对一转录里 |

进程重启后顶栏不得显示 `Working`，除非内存调度里真的有 run。
