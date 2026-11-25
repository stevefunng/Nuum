# 设置（General / Models）

Mac：`SettingsOverlay` 加 `App.tsx` 里的两段。入口是侧栏底栏，key `Settings`。

不包含执行偏好。执行偏好在 [profile.md](./profile.md)。不包含 `defaultToolPermission`。这个开关：Mac 上没有，iOS 也不做。

## 容器

| 宽度 | 容器 |
| --- | --- |
| compact | 从侧栏推入的一页。底 `--nuum-bg-editor`。返回关闭 |
| regular 且窗口 `< 900 pt` | 对话框几乎铺满：宽高都是窗口减去 32 pt。遮罩 `--sand-bg-scrim`。点遮罩关闭。Mac：`@media (max-width: 900px)` |
| regular 且窗口 `≥ 900 pt` | 对话框宽 `min(860 pt, 窗口 - 32 pt)`，高度随内容，最高为窗口的 90%，内部滚动 |

不把 1200×800 的设置窗缩小后居中。

导航 accessibility label key `Settings sections`。两项横排，或在对话框左侧竖排（regular 且 `≥ 900 pt` 用左栏，与 Mac 双栏相同；更窄时改到标题下横排）：

| 项 | key | 图标 | 选中 |
| --- | --- | --- | --- |
| general | `General` | `settings-gear` | 当前页，底 `--sand-fill-ghost-selected` |
| models | `Models` | `sliders` | 同上 |

关闭按钮在面板末端，accessibility label key `Close`，图标 `close`。标题就是当前项的 key：`General` 或 `Models`。Mac：关闭 `SettingsOverlay`。

行的节奏：左边标题 `--nuum-text-primary`，下面 `--nuum-font-size-sm` 的 `--nuum-text-secondary` 说明；右边控件。行与行之间用 `--sand-border-subtle`。分组标题 `--nuum-font-size-sm`，颜色 `--nuum-text-secondary`。

## General

分组标题 key `Appearance`。

| 行标题 key | 说明 key | 控件 |
| --- | --- | --- |
| `Language` | `Choose the language used throughout Nuum.` | 选项值 `zh-CN` 显示「中文」，`en` 显示 `English`。accessibility label key `Language`。Mac：语言选择 |
| `Theme` | `Keep the current dark shell, or switch to the light palette.` | 选项 key `Follow system`（值 `system`）、`Light`（`light`）、`Dark`（`dark`）。accessibility label key `Theme`。Mac：主题选择 |

语言保存中控件不可用。失败在控件下警告：key `Could not change language. Please try again.` 成功后整棵界面立刻换成该语言，包括这一页。

主题保存后立刻换 `nuum-light` / `nuum-dark`，不等重启。`Follow system` 跟随系统，系统切换时若当前值仍是 `system` 则跟着换。Mac：`prefers-color-scheme`。

第二组标题用 key `Proactive mode`。Mac 的 `App.tsx` 这一处写了裸字符串，译文表里这个 key 的 `zh-CN` 与 `en` 都是 `Proactive mode`。

| 行 | 规格 |
| --- | --- |
| 标题 | 文本 `Nunu` |
| 说明 | key `Manage your proactive companion from the menu bar.` 文案保持这句，因为 key 就是它。行为不要求菜单栏常驻 |
| 按钮 | key `Open menu bar panel`。点击推入 [proactive.md](./proactive.md)。Mac 这个按钮调用 `showProactive()` 打开托盘窗口。iOS 打开应用内的同一面板，不创建托盘，不创建第二窗口 |

## Models

分组标题 key `Model preferences`。

| 行标题 key | 说明 key | 控件 |
| --- | --- | --- |
| `Default provider` | `Used for new chats until you change the session model.` | `deepseek` 显示 `DeepSeek`，`openai` 显示 `OpenAI`，`anthropic` 显示 `Anthropic`。切换时模型 id 用该 provider 的 `DEFAULT_MODEL_ID`。Mac：全局默认 provider |
| `DeepSeek model` | `deepseek-chat for everyday use. deepseek-reasoner for longer reasoning.` | 仅当 provider 是 deepseek。选项值就是 `deepseek-chat` 与 `deepseek-reasoner`，标签与值相同 |

按会话改模型的行：Mac 上没有，iOS 也不做。

分组标题 key `API keys`。

| 行标题 key | 说明 key |
| --- | --- |
| `DeepSeek API key` | `Stored in the OS keychain and injected into Host memory only.` |
| `OpenAI API key` | `Optional. Used when the default provider is OpenAI.` |
| `Anthropic API key` | `Optional. Used when the default provider is Anthropic.` |

三个输入框：

- 安全输入。显示明文的眼睛按钮：Mac 上没有，iOS 也不做。
- 打开页面时值为空字符串。不从 Keychain 解密，不用 `hasOpenaiKey` / `hasAnthropicKey` / `hasDeepseekKey` 填字符。Mac 用 `getSecrets` 把明文填回；iOS 按架构第 7 节只写不读。
- 不自动聚焦，所以只是打开页面不会触发删除。
- 失焦：当前字符串为空则删除该 provider 的 key；非空则写入。这是 WP-11 的行为，对应 Mac 的保存，但读回路径不复制。
- 界面任何文本节点都不出现 key 的字符。说明文案保持上表，不追加「已保存」。

密码框视觉宽度在 regular 里约 175 pt；compact 上改为该行剩余宽度，最小 160 pt。圆角 `--nuum-radius-lg`，边 `--sand-border-default`，底 `--nuum-bg-input`。

写入走 `SecretWriter`。空字符串删除。失败码 3001 的句子用架构第 7 节的两句固定英文，message 里不得含 key。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 三把 key 的框始终以空字符串开始。这不是错误 |
| 加载 | `settings.get` 未返回：导航可点，行上的选择器先不可用，不显示假 provider |
| 流式 | 此表面不出现 |
| 错误 | 语言失败用 key `Could not change language. Please try again.`。主题或 provider 保存失败用 `NuumError.message`，警告放在该行下 |
| 无 key | 此页是写入 key 的地方，不展示 2004。三个布尔都不为真时也不在这里警告；发送失败留在会话 |
| 权限被拒 | 此表面不出现。工具审批在 [approval-bar.md](./approval-bar.md) |
| 讨论中断 | 此表面不出现 |

密钥存储失败若返回 3001，警告使用异常 message，框里用户刚打的字符可以留着，便于再试。message 里不得含 key。

登录、同步、自定义 base URL：Mac 上没有，iOS 也不做。不要求后台模型来验证 key。
