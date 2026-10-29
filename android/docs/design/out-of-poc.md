# Mac 专用与 PoC 不做

下面每一项都写明：Mac 上存在什么，Android 规格要求界面不做什么。接口可以留在契约里，屏幕上不出现入口。

## 3D 与媒体开箱

Mac：`nunu-unboxing.tsx` 用 three.js，三种包装、彩纸、`BODY_ASSETS` 贴图、动作图集和四条 webm。WebGL 失败才退回矢量 `AgentAvatar`。

Android：只做 [screens/unboxing-2d.md](./screens/unboxing-2d.md)。不引入 3D 引擎，不播 webm，不画彩纸粒子。reduced motion 直接终态。

## Shell 终端界面

Mac：工具 `shell` 走持久 bash。活动组把 `bash` / `shell` 标成 i18n key `Bash`（zh-CN「终端」）。没有独立的终端窗口，但执行路径会跑命令。

Android：不提供 PTY、命令输入行、`shell_id`、ANSI 着色。`--nuum-terminal-ansi-*` 不进入界面。模型若仍调用 `shell`、`request_network`、`external_operation`，活动组可以出现，标签仍用 `Bash`、`Network access`、`Local operation`，输出是 Host 返回的「PoC 未实现」英文句子。用户不能在界面里开一个 shell。

资料页的命令策略控件保留，因为 Mac 的 `ExecutionWidget` 有它。它保存 `ask | never`，不打开终端。见 [screens/profile.md](./screens/profile.md)。

## 菜单栏常驻

Mac：`ProactiveTray`、模板 PNG、窗口关掉后进程留在托盘。`?surface=proactive` 是另一扇窗口。设置按钮 key `Open menu bar panel` 调用 `showProactive()`。面板页脚有 key `Quit`。说明文案 key `Manage your proactive companion from the menu bar.`

Android：没有托盘，没有常驻通知，没有第二扇「菜单栏窗口」。同一按钮打开应用内的 [screens/proactive.md](./screens/proactive.md)。不渲染 `Quit`。不在状态栏放 Nuum 图标。

## 登录与同步

Mac 没有账号、后端、多设备同步。Android 同样不画登录按钮、注册、云端执行、同步开关。`SyncPort` 的空实现在界面上没有任何一行。`IdentityContext` 不展示 userId。

## 窗口铬

Mac 有 `titleBarStyle: "hiddenInset"`、红绿灯、`--sand-traffic-lights-inset: 78px`、`.sand-cover-drag`。Android 使用系统状态栏，不画红绿灯，不留 78dp 的拖拽空位。

应用菜单（About、Hide、Quit、Front）不移植。

## 其他 Mac 界面也没有的入口

这些在 Mac 代码里就没有按钮。Android 同样不画：

| 能力 | 依据 |
| --- | --- |
| 删除 Nunu | `agentDelete` 有方法，侧栏菜单没有 |
| 从侧栏隐藏 | `hiddenFromSidebar` 只被过滤，没有开关 |
| 会话内换模型 | 设置只有全局默认 provider |
| 全局 `defaultToolPermission` 开关 | 设置页不渲染。key `Default local-tool permission` 不放到设置里 |
| 用户新建任务卡 | `WorkBoard` 收到 `onCreateTask` 但没有调用。不放 key `New task` 的按钮 |
| 能力商店可购买或可安装的预设 | 「发现」页是禁用展示 |
| CheckAgent 卡片、秘密输入卡、widget 随下一条消息自动收起 | `TODO.md`，Mac 未做 |
| 跨用户 Room | 不存在 |

## 密钥回显

Mac 设置页用 `getSecrets` 把明文填回 password 框。Android 不复制。见 [screens/settings.md](./screens/settings.md)。这是架构已经写明的差异，不是新的产品能力。
