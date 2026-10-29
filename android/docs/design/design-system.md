# 设计系统

Nuum 的界面语言是 sand kit。Android 沿用同一批 CSS 变量，不建立 Material color role（`primary`、`onSurface`、`surfaceContainer` 这类名字不进入规格，也不进入主题命名）。

Compose 可以用 Material3 的抽屉、开关、列表当布局容器。这些容器的颜色、字号、圆角全部改成下面引用的变量。`MaterialTheme.colorScheme` 不作为设计真源。

数值表：[tokens.md](./tokens.md)。下文只写安装方式、生效层级，以及屏幕会碰到的用法。

## 1. 安装

来源：`packages/ui/src/theme/runtime-theme-token-installer.ts`。

| 项 | 现有名字 |
| --- | --- |
| 样式节点 | `RUNTIME_THEME_STYLE_ID` = `nuum-runtime-theme` |
| 浅色类 | `RUNTIME_THEME_CLASS.light` = `nuum-light` |
| 深色类 | `RUNTIME_THEME_CLASS.dark` = `nuum-dark` |
| 文档标记 | `documentElement.dataset.theme` 与 `style.colorScheme`，值为 `light` 或 `dark` |

`buildRuntimeThemeCss(mode)` 的拼接顺序是：

1. `CORE_CSS[mode]`
2. `RADIUS_CSS`（覆盖五项圆角，见 §4）
3. `bzn(mode)`：`RUNTIME_PALETTE` + `SAND_DATA`
4. `Ezn(mode)`：`NZN_TOKENS` 然后 `THEME_PALETTE_MAPPING`

后写的同名变量获胜。屏幕读生效值。

设置里的主题字段是 `light | dark | system`。解析：

- `light` → `nuum-light`
- `dark` → `nuum-dark`
- `system` → 跟随系统深色开关，对应 Mac 的 `prefers-color-scheme`
- 设置尚未读到时先用 `dark`。Mac 主窗口背景是 `#111111`，等于 dark 的 `--sand-bg-subtle` / `--nuum-chrome`

状态栏与导航栏背景用 `--sand-bg-subtle`。浅色模式用深色系统图标，深色模式用浅色系统图标。

## 2. 八位色的字节序

CSS 八位色是 `#RRGGBBAA`。例：`--sand-text-secondary` light = `#14141499`。Android `Color.parseColor` 要的是 `#AARRGGBB`，同一颜色写成 `#99141414`。转换只改字节序，不改数值，也不改变量名。

## 3. 屏幕用法

一个界面角色只对应下表这一格。不要为同一角色再起一个 Material 名字。

| 界面角色 | CSS 变量 |
| --- | --- |
| 应用 chrome、侧栏、抽屉底 | `--nuum-bg-chrome` → `--sand-bg-subtle`。dark `#111111`，light `#f7f7f7` |
| 会话 / Room / 设置内容底 | `--nuum-bg-editor` → `--sand-bg-base`。dark `#070707`，light `#fcfcfc` |
| 抬起的卡片、审批条、工具卡 | `--nuum-bg-elevated` → `--sand-bg-elevated`。dark `#181818`，light `#fcfcfc` |
| 输入框底 | `--nuum-bg-input` → `--sand-fill-elevated`。dark `#2f2f2f`，light `#fcfcfc` |
| 次级填充、分组空态 | `--sand-fill-secondary` |
| 选中行 | `--sand-fill-ghost-selected`。别名 `--sand-agent-selected-fill` |
| 按下 / 悬停 | `--sand-fill-ghost-hover` |
| 主按钮填充 | `--sand-fill-primary`；按下 `--sand-fill-primary-hover`；不可用 `--sand-fill-primary-disabled` |
| 主按钮文字 | `--sand-text-on-primary` |
| 正文 | `--nuum-text-primary` → `--sand-text-primary` |
| 次级说明 | `--nuum-text-secondary` → `--sand-text-secondary` |
| 时间、占位、空态 | `--nuum-text-tertiary` → `--sand-text-tertiary` |
| 不可用文字 | `--sand-text-disabled` |
| 链接、强调文字 | `--nuum-text-accent` → `--sand-text-accent` |
| 危险文字 | `--sand-text-danger` |
| 成功文字 | `--sand-text-success` |
| 警告文字 | `--sand-text-warning` |
| 发丝边 | `--sand-border-subtle` |
| 默认边 | `--sand-border-default`。别名 `--nuum-stroke-secondary` |
| 焦点边 | `--sand-border-focus` |
| 危险边 | `--sand-border-danger` |
| 用户气泡底 | 该 Nunu 的 `chat` 色素（§6），不是 sand 色板 |
| 用户气泡字 | `--sand-text-on-color` |
| 助手气泡底 | `--sand-fill-bubble-agent` |
| 抽屉与对话框遮罩 | `--sand-bg-scrim` |
| 全屏模态遮罩 | `--sand-bg-scrim-heavy` |
| 浮层阴影 | `--nuum-box-shadow-md`（由 `--sand-shadow-popover-ambient`、`--sand-shadow-popover-key`、`--sand-shadow-ring` 组成） |
| 控件阴影 | `--nuum-box-shadow-sm` → `--sand-shadow-control` |
| 顶栏淡出 | `--sand-gradient-bg1-fade` |
| 流式文字闪烁 | `--sand-gradient-text-shimmer` |
| 背景模糊半径 | `--sand-blur-background` = `24px`。PoC 对话框遮罩用 scrim，不依赖模糊 |

dark 下 `--sand-shadow-*` 多为 `#00000000`。深色浮层靠 `--sand-bg-elevated` 与 `--sand-border-subtle` 分开，不另加黑色投影。

焦点环沿用设置页：`2px` 实线 `--nuum-text-secondary`，offset `3px`。

终端色 `--nuum-terminal-ansi-*`、语法色 `--nuum-syntax-*`、编辑器 gutter 色都在 [tokens.md](./tokens.md) 里，避免改名。PoC 屏幕不使用它们。原因见 [out-of-poc.md](./out-of-poc.md)。

## 4. 圆角

`RADIUS_CSS` 在 `CORE_CSS` 之后，下面五项以它为准：

| CSS 变量 | 生效值 | CORE_CSS 里先写的值 |
| --- | --- | --- |
| `--nuum-radius-base` | `8px` | `6px` |
| `--nuum-radius-lg` | `10px` | `8px` |
| `--nuum-radius-xl` | `14px` | `12px` |
| `--nuum-radius-2xl` | `16px` | `14px` |
| `--nuum-radius-3xl` | `18px` | `16px` |

未被覆盖、屏幕会用到的：

| CSS 变量 | 值 | 用在 |
| --- | --- | --- |
| `--nuum-radius-none` | `0px` | 分割线 |
| `--nuum-radius-xs` | `2px` | 极小标记 |
| `--nuum-radius-sm` | `4px` | 菜单项 |
| `--nuum-radius-4xl` | `18px` | 消息气泡（Mac `.sand-message` 的 `border-radius: 18px`） |
| `--nuum-radius-full` | `9999px` | 主按钮、色点、开关、状态点 |

审批条 Mac 用 `16px`，取 `--nuum-radius-2xl`。工具卡 `12px` 在生效阶梯里没有同值；工具卡与 widget 选项沿用 Mac 的 `12px` 常数，并在注释里写「介于 `--nuum-radius-lg`（10px）与 `--nuum-radius-xl`（14px）之间，跟 `.sand-tool-card` / `.sand-widget-card__option`」。不要为此新命名一个 token。

## 5. 字号与间距

两种 mode 相同。Android 取 `1px = 1dp`，不另做一套 sp 阶梯。

| 角色 | CSS 变量 | 值 |
| --- | --- | --- |
| 侧栏时间、分组计数 | `--nuum-font-size-xs` / `--nuum-line-height-xs` | `11px` / `14px` |
| 工具卡、思考状态、审批按钮 | `--nuum-font-size-sm` / `--nuum-line-height-sm` | `12px` / `16px` |
| 界面默认（侧栏名字、chrome） | `--nuum-font-size-base` / `--nuum-line-height-base` | `13px` / `18px`。字距 `--nuum-letter-spacing-base` = `-0.08px` |
| 消息正文 `.sand-message-prose` | `--nuum-font-size-lg` | `14px`，行高 `22px`（Mac 写死 `22px`，等于 `--nuum-line-height-lg`） |
| 无衬线 | `--nuum-font-family-sans` | 系统无衬线。不打包 SF Pro、Inter 或 Roboto 文件 |
| 等宽（参数、输出、路径） | `--nuum-font-family-mono` | 系统等宽 |

字重沿用 Mac：正文 400，名字与主按钮 600，字标 `Nuum` 600，字距 `-0.04em` 只用于空会话的字标。

间距阶梯是 `--nuum-spacing-1`（4px）到 `--nuum-spacing-20`（80px），每步 4px。半步在表里，例如 `--nuum-spacing-1-5` = `6px`、`--nuum-spacing-0-5` = `2px`。屏幕规格里的间距都点名这些变量。

控件视觉高度：

| CSS 变量 | 值 | 用在 |
| --- | --- | --- |
| `--nuum-height-xs` | `20px` | 状态点所在的小标记 |
| `--nuum-height-sm` | `24px` | 圆形图标按钮的图形盒（侧栏搜索、新建、设置） |
| `--nuum-height-base` | `28px` | 审批按钮、分组更多 |
| `--nuum-height-lg` | `32px` | 创建页主按钮 |

触控热区把可点范围扩到 48dp，图形盒仍用上表高度。热区可以透出，不把 28px 的按钮画成 48px 的 Material 块。

## 6. 时长

| CSS 变量 | 值 | 用在 |
| --- | --- | --- |
| `--nuum-duration-instant` | `50ms` | 按压色 |
| `--nuum-duration-fast` | `100ms` | 色点 `transform`（Mac 色点 `140ms` 就近用这一档，不新增值） |
| `--nuum-duration-normal` | `150ms` | 行悬停 |
| `--nuum-duration-slow` | `200ms` | 资料栏进入（Mac `220ms` 就近用这一档） |
| `--nuum-duration-slower` | `300ms` | 抽屉开合 |
| `--nuum-easing-out-strong` | `cubic-bezier(0.165, 0.84, 0.44, 1)` | 抽屉、资料栏 |
| `--nuum-easing-default` | `ease` | 颜色过渡 |

开箱时长不在这张表里，见 [motion.md](./motion.md)。

## 7. Nunu 色素与形状

色素不在 sand 色板里。它们写进 `profile.json` 的 `avatarColor`，定义在 `packages/ui/src/conversation/nunu-appearance.ts` 的 `AGENT_AVATAR_COLORS`。

| id | 创建页 i18n key | `value`（身体） | `dark` | `chat`（用户气泡） |
| --- | --- | --- | --- | --- |
| `cream` | `Cream` | `#f3e8d4` | `#c8af8b` | `#806444` |
| `green` | `Sage` | `#bac8a8` | `#7e9270` | `#526c43` |
| `orange` | `Peach` | `#f4c2a1` | `#ce8e6a` | `#ad5c30` |
| `violet` | `Lilac` | `#d5c6eb` | `#a28dbd` | `#79569d` |
| `blue` | `Mist blue` | `#bedce7` | `#7cabbf` | `#39738c` |
| `magenta` | `Rose` | `#eec3cc` | `#bd899b` | `#a4526c` |
| `honey` | `Honey` | `#efdb9b` | `#c1a456` | `#8c6b22` |

遗留 id `black` 不出现在创建色板。读到时：`value #a7aaa8`，`dark #707873`，`chat #3b4140`。i18n key 是 `black`。

形状 id：`circle | blob | droplet | cloud | tablet`。path 的 `d` 用 `nunu-appearance.ts` 里 `SHAPES` 的字符串，viewBox 头像 `18 8 196 196`，全身 `0 0 232 232`。材质 id：`plush | felt | matte | glass`，隐藏值 `aurora` 可解析，不进 `rollAgentAvatar()`。

矢量质感，不引用 png：

| 材质 | 画法 |
| --- | --- |
| `matte` | 以 `value` 平涂 |
| `felt` | `value` 平涂，再叠加 8% `--sand-text-primary` 的细点。点是矢量，不使用 `felt.png` |
| `plush` | `value` 平涂，下缘向 `dark` 过渡 |
| `glass` | 色素强度 0.38（`resolveNunuPigment`），加一道低透明度 `--sand-text-on-color` 高光 |
| `aurora` | 与 `glass` 相同，再加一道低透明度 `--sand-fill-supplementary4` 扫光 |

深色模式下身体仍用 `value` / `dark`，不改成 `--sand-text-primary`。用户气泡始终用 `chat`。

## 8. 深色

切换设置里的 `Theme` 后立即调用与 `createRuntimeThemeInstaller.update` 等价的整表替换，不等待进程重启。`Follow system`、`Light`、`Dark` 三个 key 见 [screens/settings.md](./screens/settings.md)。

深色不是把浅色反相。每个变量的 dark 列以 [tokens.md](./tokens.md) 为准。例如 `--sand-fill-primary` light `#070707`、dark `#fafafa`；`--sand-text-danger` light `#c21d2e`、dark `#ff5667`。

Mac 的 widget 选项目前写死浅色 `#fcfcfc`。Android 的 widget 在两种模式下都改用 §3 的变量，见 [screens/widget.md](./screens/widget.md)。
