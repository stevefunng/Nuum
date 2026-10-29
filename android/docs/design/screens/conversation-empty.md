# 空会话

Mac：`workspace.tsx` 在 `agent == null` 或 `blocks.length === 0` 时渲染 `.sand-empty--welcome`。输入框仍然在。

这一屏是内容列的空态，不是另一条导航。有转录之后换成 [conversation-transcript.md](./conversation-transcript.md)。输入框、附件、停止的规则以那两份规格为准，空态不另做一套输入框。

## 结构

顶栏：

- 手机起始边是打开抽屉的按钮，`aria-label` key `Agents`。≥ 840dp 没有这个按钮。
- 没有选中 Nunu 时，中间是空的，不写假名字。
- 选中了 Nunu 但转录为空：中间是资料按钮，头像 28dp，名字用 `profile.name`，`aria-label` key `Open {name} profile`。`running` 才在名字旁显示状态小字；空会话通常不是 running。

中部，垂直水平居中，最小高度约为内容列的 42%：

| 元素 | 规格 |
| --- | --- |
| 字标 | 文本 `Nuum`。字号 28dp，字重 600，字距 `-0.04em`，颜色 `--nuum-text-primary`。这是字标，不是 i18n key |
| 说明 | key `Ask anything, or drop a file.`。颜色 `--nuum-text-tertiary`，字号 `--nuum-font-size-base`，与字标间距 `--nuum-spacing-2` 加 2dp（Mac `gap: 10px`，用 `--nuum-spacing-2` + `--nuum-spacing-0-5`） |

底栏是输入框。没有选中 Nunu 时占位也是 key `Ask anything, or drop a file.`。选中了则占位 key `Message {name}`。

没有选中 Nunu 时：附件按钮不可用，发送不可用。拖进文件没有落点，不读取。

选中了 Nunu 且转录仍为空：可以输入、加附件、发送。发送成功后这一屏被转录屏替换，空态不保留。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 上面的字标加 key `Ask anything, or drop a file.`。这就是空态本身 |
| 加载 | 正在读该 Nunu 的转录尾部、还不知道是不是空：中部留白，不显示字标，也不借用 key `思考中`。顶栏名字可以先出现。读完若块数为 0 再显示字标 |
| 流式 | 空转录不会流式。一旦收到 delta 或可见 `message`，离开这一屏 |
| 错误 | 发送失败的句子放在输入框上方，规则同转录屏的 `notice`。空态字标保留 |
| 无 key | 用户发送后 Host 返回 2004：输入框上方 `role="alert"` 显示异常的 `message`。不显示 key 字符，不显示数字码墙。草稿和附件留在输入框里 |
| 权限被拒 | 空会话还没有审批条。若发送前选文件被系统拒绝，走 [attachments.md](./attachments.md) 的读取失败 key `Could not read attachment.` |
| 讨论中断 | 此表面不出现 |

从侧栏点一个已有转录的 Nunu，不要先闪这一屏。转录读完再决定画空态还是转录。
