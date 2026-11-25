# 范围外

下面每一项都写明 Mac 上的现成行为，或者写明「Mac 上没有，iOS 也不做」。接口可以留在契约里，屏幕上不出现入口。

不要求菜单栏常驻、登录、同步、后台模型。

## 3D 与媒体开箱

Mac：`nunu-unboxing.tsx` 用 three.js，三种包装、彩纸、`BODY_ASSETS` 贴图、动作图集和四条 webm。WebGL 失败才退回矢量 `AgentAvatar`。`prefers-reduced-motion: reduce` 时时钟跳到 `UNBOX_PLAYBACK_DURATION`。

iOS：只做 [screens/unboxing-2d.md](./screens/unboxing-2d.md)。不要求 3D。不引入 3D 引擎，不播 webm，不画彩纸粒子。`accessibilityReduceMotion` 为真时直接到终态。

## Shell 终端界面

Mac：工具 `shell` 走持久 bash。活动组把 `bash` / `shell` 标成 i18n key `Bash`（zh-CN「终端」）。没有独立的终端窗口，但执行路径会跑命令。

iOS：不提供 PTY、命令输入行、`shell_id`、ANSI 着色。`--nuum-terminal-ansi-*` 不进入界面。模型若仍调用 `shell`、`request_network`、`external_operation`，活动组可以出现，标签仍用 `Bash`、`Network access`、`Local operation`，输出是 `This iOS client does not implement this tool.` 用户不能在界面里开一个 shell。

`RunWorkCLI` 的句子与 Mac 相同：`This version of Nuum has no local executable. RunWorkCLI is not implemented.`

资料页的命令策略控件保留，因为 Mac 的 `ExecutionWidget` 有它。它保存 `ask | never`，不打开终端。见 [screens/profile.md](./screens/profile.md)。

## 菜单栏常驻

Mac：`ProactiveTray`、模板 PNG、窗口关掉后进程留在托盘。`?surface=proactive` 是另一扇窗口。设置按钮 key `Open menu bar panel` 调用 `showProactive()`。面板页脚有 key `Quit`。说明文案 key `Manage your proactive companion from the menu bar.`

iOS 不要求菜单栏常驻。没有托盘，没有常驻通知，没有第二扇窗口。同一按钮打开应用内的 [screens/proactive.md](./screens/proactive.md)。不渲染 `Quit`。不在状态栏放 Nuum 图标。

## 登录与同步

Mac 上没有账号、后端、多设备同步。Mac 上没有，iOS 也不做：登录按钮、注册、云端执行、同步开关。`SyncPort` 的空实现在界面上没有任何一行。`IdentityContext` 不展示 userId。

## 后台模型

Mac 的 Proactive 有 1 秒 tick，并且可以在窗口之外继续。iOS 不搬这个 tick，也不在后台跑模型。不声明 `UIBackgroundModes`。不用 `BGAppRefreshTask`、`BGProcessingTask`，也不用 background `URLSession` 跑模型。打开 Proactive 面板时现算 snapshot。场景进入后台时不新开模型请求。

## WidgetKit

产品 widget 是转录卡片，见 [screens/widget.md](./screens/widget.md)。WidgetKit 主屏幕小组件、Live Activity、App Intent：Mac 上没有，iOS 也不做。

## 窗口铬与应用菜单

Mac 有 `titleBarStyle: "hiddenInset"`、红绿灯、`--sand-traffic-lights-inset: 78px`、`.sand-cover-drag`。iOS 使用系统状态栏和安全区，不画红绿灯，不留 78 pt 的拖拽空位。

Mac 的应用菜单在 `apps/desktop/src/main/index.ts`：About、Hide、Hide Others、Quit。这是 Electron 壳，不是 `packages/ui` 的产品表面。iOS 不移植这张菜单，不画 About、Hide、Quit 页面。Proactive 页脚也不渲染 key `Quit`。

## Mac 界面也没有的入口

这些在 Mac 代码里就没有按钮。Mac 上没有，iOS 也不做：

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
| @ 提及菜单 | 用户在正文里自己打 `@名字`。Host 解析 @ |
| Room 共享聊天的附件按钮 | Mac 的共享聊天没有这个按钮 |
| 创建 Work 的目标输入 | key `Goal` 在文案表里；当前 `WorkCreation` 没有这个输入 |
| 创建页的 `Shuffle` | `agent-creation.tsx` 没有这个按钮 |

## 密钥回显

Mac 设置页用 `getSecrets` 把明文填回 password 框。iOS 不复制。见 [screens/settings.md](./screens/settings.md)。这是 [IOS_ARCHITECTURE.md](../IOS_ARCHITECTURE.md) 第 7 节已经写明的差异：只写不读。设置页不提供「显示 key」。

## 观测、支付、LLM SDK

Mac 上没有，iOS 也不做：Datadog、Sentry、Firebase、金融 SDK、LLM SDK。模型请求用 `URLSession` 按架构第 6 节的三个 HTTPS 源现造。界面上没有这些服务的入口。
