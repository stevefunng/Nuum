# 能力目录

Mac：`WorkCapabilityDialog`（`work-dialog.tsx`）以及 `WorkBoard` 检查器里的能力列表。Room 和 NunuBar 共用。入口在成员区上方。

## 列表

节标题 key `Capabilities`，旁边是条目数。末端加号，`aria-label` key `Add capability`，图标 `plus` 12dp，热区 48dp。

每条：名字，下面小字是种类 key。

| `entry.kind` | key |
| --- | --- |
| `local-tool` | `Local tool` |
| `skill` | `Skill` |
| `cli` | `CLI` |
| `knowledge` | `Knowledge` |

移除按钮 `aria-label` key `Remove {name}`，图标 `close`。点击直接 `catalog.remove`，没有确认框，与 Mac 相同。

空列表：不写额外空态句子。Mac 只留标题和加号。Android 同样只留这两样。

≥ 840dp 时这一节在检查器上半部，和成员之间可以拖，`aria-label` key `Resize capabilities and agents`。手机上这一节全宽，放在成员节上面，没有这条拖拽。

## 对话框

标题 key `Capabilities`。副标题 key `Skills, tools and knowledge for this Work.`。关闭 key `Close dialog`。

页签 `aria-label` key `Capability source`：

| 页 | key | 默认 |
| --- | --- | --- |
| discover | `Discover` | 打开时停在这里 |
| local | `Import local` | |

### 发现

不可安装。卡片没有点击。只有底部一条能切换到导入页。

眉题 key `THE COLLECTION`，旁边 key `Coming soon`。

两张展示卡，都带 key `Presets on the way`：

| 卡 | 眉 | 标题 | 说明 |
| --- | --- | --- | --- |
| skill | `KNOW-HOW` | `Skills` | `Thoughtful workflows.` 与 `Ready for your next task.` |
| cli | `HANDS-ON` | `CLI tools` | `Familiar tools.` 与 `A little more possibility.` |

图标分别是 `sliders` 与 `attach`，24dp，只是装饰。

底部按钮：强调 key `Already have something in mind?`，说明 key `Bring a local Skill, CLI or knowledge folder.`，末端 key `Import local` 加 `plus`。点击把页签切到 local，不关闭对话框。

### 本地导入

种类四选一，`aria-pressed`：

| kind | 按钮 key |
| --- | --- |
| `skill` | `Skill` |
| `cli` | `CLI` |
| `knowledge` | `Knowledge` |
| `local-tool` | `Local tools` |

切换种类时清空路径和错误。

| 字段 | 标签 key | 占位 |
| --- | --- | --- |
| 名字 | `Name` | skill 用 `e.g. Design review`，其余用 `A short, recognizable name` |
| 路径 | skill：`Skill manifest`；cli：`Executable`；knowledge：`Knowledge folder`；local-tool：`Tool names` | skill `/path/to/skill/SKILL.md`；cli `/path/to/executable`；knowledge `/path/to/knowledge`；local-tool key `Tool names, separated by commas` |
| 子命令 | 仅 cli，key `Allowed subcommands` | `e.g. status, diff, log` |

skill 与 knowledge 的路径行有按钮 key `Browse`，调用 `DesktopPort` 选目录。skill 把选中的目录加上 `/SKILL.md`。目录名在名字为空时填进名字。

说明一段：

| kind | key |
| --- | --- |
| `knowledge` | `Agents can read this folder. The source files stay in place.` |
| `skill` | `Choose the folder containing SKILL.md, or enter its full path.` |
| `cli` | `Use an installed executable. List the subcommands this Work can use.` |
| `local-tool` | `Add tools already registered in Nuum.` |

提交按钮 key `Add to Work`，进行中 key `Importing…`。名字或路径空白则不可用。

提交体与 Mac 相同：

| kind | 字段 |
| --- | --- |
| `skill` | `manifestPath` |
| `cli` | `executable`，`allowedSubcommands` 按逗号或空白拆开 |
| `knowledge` | `roots` 一项，`readOnly: true` |
| `local-tool` | `toolNames` 按逗号拆。空则 alert key `Enter at least one tool name.`，不发请求 |

`description` 传空字符串。

失败 alert：key `Could not import. Check the path and try again.`，或异常 message。成功则关闭对话框，列表出现新行。

发现页的卡片不能点。不要给 `Presets on the way` 加购买或安装。

`cli` 与 `skill` 只保存路径说明。PoC 不执行 `RunWorkCLI`，不加载 skill 代码。导入成功只表示元数据写进了 `catalog.json`。若用户稍后派发导致工具返回未实现句子，那是执行结果，不在这个对话框里预告新文案。

knowledge 的根是只读 SAF 树或用户选的目录。没有 URI 权限时导入失败，用上面的失败 key。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 列表没有条目时只留标题和加号。发现页始终是「即将上线」，这不是空态错误 |
| 加载 | 导入中按钮 key `Importing…`，种类和输入不可用 |
| 流式 | 此表面不流式。目录更新走 `work.catalog.updated`，列表整表替换 |
| 错误 | key `Could not import. Check the path and try again.` 或 `Enter at least one tool name.` |
| 无 key | 导入不调用模型。此表面不出现 2004 |
| 权限被拒 | 选目录时用户取消：路径不变，无 alert。知识库 URI 失效导致导入失败：同一条导入失败 alert |
| 讨论中断 | 此表面不出现 |
