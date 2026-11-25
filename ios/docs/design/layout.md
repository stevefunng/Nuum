# 布局：compact 与 regular

Mac 主窗口默认 1200×800，最小 800×560，侧栏钉在窗口左侧。iOS 不把这张 1200×800 画布缩小后居中，也不保留红绿灯、`--sand-titlebar-block`（44px）拖拽区和 `--sand-traffic-lights-inset`（78px）。

断点用水平 size class，单位 pt。侧栏是一列。

- **compact**：同一时刻只看见一列。侧栏列占满窗口宽度（安全区之内）。选中一行后，内容列替换侧栏列。返回（导航返回或从起始边滑回）回到侧栏列。没有盖住内容的抽屉，没有把会话缩成一条窄轨再叠侧栏。
- **regular**：两列同时在。左侧是侧栏列，右侧是内容列。中间没有 1200×800 的信箱边。

安全区（状态栏、Home 指示条、灵动岛或刘海）加在相应边的外缘。不把 Mac 的 18px 转录 padding 拿去吃安全区。

单 `WindowGroup`。不另开菜单栏窗口，不要求菜单栏常驻。

## compact：侧栏是整列

侧栏数据、分组、置顶、搜索、新建、设置与 [screens/sidebar.md](./screens/sidebar.md) 相同。容器是导航的第一列，不是模态抽屉。

| 项 | 规格 |
| --- | --- |
| 宽度 | 窗口宽度，含在安全区之内。这是一列的宽度，不是 `min(360, 86%)` 的抽屉，也不是把 1200 缩成屏宽 |
| 高度 | 整窗，含在安全区之内 |
| 底色 | `--nuum-bg-chrome` |
| 展开内容 | 名字、预览、时间、搜索框都在。头像展开 34 pt，置顶 52 pt。不使用 88 pt 图标轨 |
| 列切换 | `--nuum-duration-slower` + `--nuum-easing-out-strong`。`accessibilityReduceMotion` 为真时直接切换，见 [motion.md](./motion.md) |

Mac 在窄窗口用 `projectResponsiveSidebar`：`available = viewportWidth - 740`，不够就把侧栏收成 88px，好留给大约 740px 的会话。这条 740 是为 1200×800 窗口服务的。compact 上不要调用它。88 pt 图标轨只在 regular、并且用户自己把宽度拖过折叠阈值时出现。

compact 内容列顶栏，高度 `--nuum-spacing-14`（56px）再加状态栏安全区：

| 位置 | 控件 |
| --- | --- |
| 起始 | 导航返回，回到侧栏列。accessibility label 用 key `Agents`，与 Mac 侧栏的 `aria-label` 相同。这是列返回，不是新的产品按钮 |
| 中间 | 当前表面自己的标题。一对一是资料入口，Room / NunuBar 是工作名 |
| 末端 | 该表面自己的动作。没有就留空 |

冷启动且没有选中的 Nunu、也没有选中的 work：停在侧栏列，空列表文案可见。内容列不先画一张缩小的空桌面。

从内容列返回：选中清空，侧栏列重新占满窗口。不清数据，不删除 Nunu。

## regular：分栏

```text
┌──────────────┬────────────────────────────────────┐
│ 侧栏列        │ 内容（会话 / Room / NunuBar / 创建） │
│ 默认 236 pt   │ 剩余宽度                             │
└──────────────┴────────────────────────────────────┘
```

侧栏宽度存在 UserDefaults suite `nuum-ui`，字段与 Mac `localStorage` key `nuum.ui.sidebar.v2` 相同：`expandedWidth`、`isCollapsed`。

| 常数 | 值 | 来源 |
| --- | --- | --- |
| 默认展开 | `236 pt` | `SIDEBAR_LAYOUT_DEFAULTS.expandedWidth` |
| 展开最小 | `220 pt` | `minExpandedWidth` |
| 展开最大 | `400 pt` | `maxExpandedWidth`，同时不超过窗口的 42%（Mac `.sand-agents-sidebar` 的 `max-width: 42vw`） |
| 折叠宽度 | `88 pt` | `collapsedWidth` |
| 拖过即折叠 | `< 208 pt` | `collapseBelow` |

展开宽度 = `clamp(保存值, 220 pt, min(400 pt, 窗口宽度的 42%))`。若上限已经小于 220 pt，改用 88 pt 折叠轨，并保留原来保存的展开宽度。不调用 `projectResponsiveSidebar`。

拖动手柄在侧栏尾缘，竖条热区 `--nuum-spacing-11`（44 pt）宽，可见线 1 pt，颜色 `--sand-border-default`。accessibility label 用 key `Resize sidebar`。拖动中不写盘；松手后写入，与 `settleSidebarLayout` 相同。

regular 顶栏没有回到侧栏的按钮。侧栏一直在。

内容区在默认 236 pt 侧栏旁边继续用剩余宽度。到达 regular 时不要自动折叠。只有用户把把手拖到 208 pt 以下才进入 88 pt 轨。88 pt 轨里：头像 40 pt，隐藏搜索框、名字、预览、时间；新建按钮留在底栏，设置按钮留在底栏。与 Mac `.is-collapsed` 相同。

从 compact 转到 regular：若已经有选中项，两列同时出现，内容不重载。从 regular 转到 compact：有选中项时停在内容列；没有选中项时停在侧栏列。

## 内容宽度

气泡和卡片的最大宽度跟内容列走，不跟「假设的 1200 画布」走。

| 元素 | 最大宽度 |
| --- | --- |
| 用户消息 | `min(88%, 560 pt, 内容列宽度 - 82 pt)` |
| 助手栈、工具卡、通知 | `min(88%, 640 pt)` |
| widget | 最小 260 pt，最大 380 pt；内容列更窄时最大改为内容列减去 `--nuum-spacing-8`（32px） |
| 创建 Nunu 卡片 | regular：`min(440 pt, 窗口宽度 - 32 pt)`。compact 改全列页，见 [screens/create-nunu.md](./screens/create-nunu.md) |
| 设置 | 见 [screens/settings.md](./screens/settings.md) |
| 资料栏 | compact 盖住内容列。regular 贴在内容列尾部，宽度 `clamp(300 pt, 内容列的 33%, 420 pt)`，左边 1 pt `--sand-border-subtle` |

转录列在很宽的 regular 里不再继续拉满气泡：气泡已经有 560 / 640 的上限，背景用 `--nuum-bg-editor` 铺满内容列。助手气泡靠起始边，用户气泡靠末端边。

## 资料、设置、目录在两档里的容器

| 表面 | compact | regular |
| --- | --- | --- |
| 资料 | 盖住内容列的一页。关闭用 key `Close profile` | 内容列尾部的一栏，会话仍可见 |
| 设置 | 从侧栏推入的一页。General / Models 在页顶横排 | 居中对话框，宽 `min(860 pt, 窗口宽度 - 32 pt)`。窗口宽度 `< 900 pt` 时对话框改为窗口减去 32 pt 见方，与 Mac `@media (max-width: 900px)` 相同 |
| 能力目录、任务详情、身份编辑 | 盖住内容列的一页 | Mac 的 `dialog`，宽沿用各屏规格 |
| Proactive | 从设置推入的一页 | 内容列上的全高页，侧栏仍在。不另开窗口 |
| peer 抽屉 | 从底部升起的半屏，最高 88% | 内容列内居中的表面，最大 640 pt |
| 审批条 | 钉在输入框上方，全宽减去左右 `--nuum-spacing-4` | 同一位置，最大 640 pt，靠起始边 |

竖向顺序是「顶栏 → 滚动内容 → 底栏输入」。regular 只是左面多了侧栏列。不要把 Mac 的三栏（侧栏 + 会话 + 资料）在 compact 上挤成三列。
