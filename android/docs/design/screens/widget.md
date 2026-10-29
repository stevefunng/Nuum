# Widget

Mac：`workspace.tsx` 的 `WidgetCard`。载荷来自 `SendMessage` 的 `widget`。选项 1 到 6 个（`transcript.ts` 的 `max(6)`）。

旧版载荷是字符串 `widget` 名加 `props`。它不画成卡片，画成等宽 `<pre>`，放在助手消息宽度里。不发明新渲染。注释与 Mac 一致：真实卡片是结构化载荷的事。

## 结构化卡片

放在转录里，起始对齐，和助手气泡同一列。最小宽 260dp，最大 380dp。手机更窄时最大为内容列减去 `--nuum-spacing-8`。

Mac 的选项写死浅色底。Android 两种主题都用 sand 变量：

| 元素 | CSS 变量 |
| --- | --- |
| 问题 | `--nuum-text-primary`，字重 600，`--nuum-font-size-lg` |
| 帮助 | `--nuum-text-secondary`，`--nuum-font-size-sm`。没有 `helpText` 则不留空行 |
| 选项 | 底 `--sand-fill-elevated`，边 `--sand-border-default`，字 `--nuum-text-primary`，圆角 12dp，padding `8dp 12dp`，选项间距 `--nuum-spacing-1-5` |
| 选项说明 | `--nuum-text-secondary`，`--nuum-font-size-sm` |
| `style=primary` | 边 `--sand-border-strong`，字重 600 |
| `style=danger` | 边 `--sand-border-danger`，字 `--sand-text-danger` |
| `style=default` 或缺省 | 上表默认 |
| 按下 | 底 `--sand-fill-ghost-hover` |
| 已选 | 边 `--sand-border-focus`，底 `--sand-fill-ghost-selected`，不透明度 1 |
| 已回答的其他项 | 不透明度 0.55，不可再点 |

点一项调用 `answerWidget(blockId, value ?? label)`，并把这句话当作下一条用户消息。已回答时卡片下显示 key `Your answer: {answer}`，颜色 `--nuum-text-secondary`。已回答的判定：后面的 user 块 `widgetAnswerTo` 指向这个 message 块。

`allowCustom` 且未回答：选项下是一行输入。占位 key `Or type your own answer…`。按钮 key `Send`。空白不可发送。发送内容是用户输入的 trim。

没有 `onAnswer` 时选项 `disabled`，外观同已回答的未选项。

自由输入和选项互斥：一旦回答，输入行去掉。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 转录里没有 widget 块：不渲染 |
| 加载 | 不单独加载 |
| 流式 | widget 一旦作为 `message` 到达就结束这一轮（Mac：发 widget 结束本轮）。不出现半张卡片。到达前若只有活动组，走转录屏的 `思考中` |
| 错误 | `answerWidget` 失败：在卡片下 `role="alert"` 显示异常 message，选项恢复可点。没有专门的 i18n key |
| 无 key | 回答会再发起一轮。若此时没有 key，失败句子与转录屏的 2004 相同，放在卡片下，不把 key 写进句子 |
| 权限被拒 | 此卡片不审批工具。工具审批是 [approval-bar.md](./approval-bar.md) |
| 讨论中断 | 此表面不出现 |

不实现 `dismissOnMoveOn`。下一条用户消息不会自动收起这张卡片。
