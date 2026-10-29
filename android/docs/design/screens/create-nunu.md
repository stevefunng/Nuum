# 创建 Nunu

Mac：`packages/ui/src/conversation/agent-creation.tsx`。从侧栏新建菜单的 key `Create new Nunu` 进入。

手机是全屏页，避免键盘挡住色板。≥ 840dp 是居中对话框，宽 `min(440dp, 窗口宽度 - 32dp)`，底 `--nuum-bg-elevated`，圆角 `--nuum-radius-3xl`，阴影 `--nuum-box-shadow-md`，遮罩 `--sand-bg-scrim`。点遮罩在未提交时关闭，等价 Mac 点 dialog 外缘。

`aria-labelledby` 指向标题。标题 key `Create new Nunu`。

## 结构

1. 顶栏。标题在起始边。关闭按钮在末端，图形盒 28dp，热区 48dp，图标 `close` 18dp，`aria-label` key `Close dialog`。提交中不可用。
2. 开箱区域。规格在 [unboxing-2d.md](./unboxing-2d.md)。高度 280dp；窗口高度 `< 640dp` 时 192dp。
3. 名字。单行，高 36dp，圆角 9dp，边 `--sand-border-default`，文字居中，`--nuum-font-size-lg`。`aria-label` key `Nunu name`。占位 key `Give your Nunu a name`。`maxLength` 80。打开页时聚焦。
4. 色板。`aria-label` key `Nunu color`。七个圆，直径 28dp，热区 48dp，间距 `--nuum-spacing-2`。填充是该 id 的 `value`。选中时外环 3dp `--nuum-bg-elevated`，再加 1dp `--sand-border-focus`。未选中外环 3dp `--nuum-bg-elevated` 加 1dp `--sand-border-subtle`。
5. 错误。`role="alert"`，`--sand-text-danger`，`--nuum-font-size-sm`。文字是创建失败的 message；若调用方传入的是 i18n key，用 `t`。Mac 对 `error` 调了 `t(error)`。
6. 底栏，顶边 `--sand-border-subtle`，按钮靠末端，间距 `--nuum-spacing-2`。
   - key `Cancel`。底 `--nuum-bg-secondary`，字 `--nuum-text-primary`，圆角 `--nuum-radius-full`，视觉高度 `--nuum-height-lg`。
   - key `Create`。提交中 key `Creating…`。底 `--sand-fill-primary`，字 `--sand-text-on-primary`。名字空白或提交中不可用。不可用时不透明度 0.45。

## 提交的字段

每次打开页面调用一次 `rollAgentAvatar()`。用户只改颜色。形状和材质保持这一次随机结果，直到创建成功写入 profile。换颜色不重新掷骰子。

提交对象只有：

| 字段 | 来源 |
| --- | --- |
| `name` | 输入 trim，最长 80 |
| `description` | 空字符串。职责不在这一页写 |
| `avatarColor` | 选中的 id |
| `avatarShape` | 这一次骰子 |
| `avatarMaterial` | 这一次骰子 |

不提交模板。模板只在资料页第一次保存身份前出现，见 [profile.md](./profile.md)。模板上的迷你头像颜色不写进 profile。

色板顺序与 `AGENT_AVATAR_COLORS` 相同。`aria-label` 与 `title`：

| id | key |
| --- | --- |
| `cream` | `Cream` |
| `green` | `Sage` |
| `orange` | `Peach` |
| `violet` | `Lilac` |
| `blue` | `Mist blue` |
| `magenta` | `Rose` |
| `honey` | `Honey` |

`aria-pressed` 标出当前色。没有「形状」或「材质」选择器。key `Character shape` 不放在这一页。

系统返回在未提交时关闭。提交中忽略返回和遮罩。

创建成功后关闭这一页，侧栏选中新 Nunu，内容列进入空会话。开箱不单独占一个成功页。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 名字为空时 `Create` 不可用。开箱区域仍然显示这一次骰子的形象 |
| 加载 | 提交中：按钮 key `Creating…`，名字、色板、关闭、取消都不可用 |
| 流式 | 此表面不出现 |
| 错误 | 例如达到 `MAX_AGENTS`。alert 使用 Host 的 message。表单恢复可编辑，骰子结果保留 |
| 无 key | 创建不需要 key。此表面不出现无 key 条 |
| 权限被拒 | 此表面不碰文件工具 |
| 讨论中断 | 此表面不出现 |

不提供 key `Shuffle`。Mac 创建页没有这个按钮；形象只在打开时随机一次。
