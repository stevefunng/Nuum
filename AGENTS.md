# AGENTS.md — Nuum 项目地图（AI 主入口）

> 本文件是遵循 [agents.md](https://agents.md/) 规范的 AI agent 项目入口。
> 先读本文件再改代码。改业务逻辑、协议或进程边界时先读 [开发规范](./docs/coding/README.md)；修改 UI、交互或主题时还必须阅读 [UI 规范](./docs/coding/ui-guidelines.md)。
> 当前施工：agent-first 主链路、会话真源 / UI 投影与 NunuBar V1 已实现。
> Proactive Mode 已有 Host 策略与菜单栏控制基座；上下文采集、模型评估与行动执行尚未接入。详见 [基座说明](./docs/proactive/foundation.md)。
> Room / NunuBar 新方案（主 session 增量群聊 + 独立卡片 session）已按简化方案重构：改 Work 协作域前先读 [NunuBar 设计](./docs/workbar/foundation.md)。
> 更新时间：2026-10-15

## 项目定位

Nuum 是 agent-first 的本地 AI 桌面客户端。它把 agent 作为持久实体，让身份、记忆、工具与工作状态独立于临时会话存在。

技术本质：**Electron 薄壳 + React UI + 独立 Host、Kernel 与执行 daemon**。模型默认走 DeepSeek（OpenAI 兼容），也支持 OpenAI / Anthropic 官方 API。Host 管产品与授权，Kernel 管模型循环，执行 daemon 管受限本地执行。

## 仓库结构

```
Nuum/
├── apps/
│   └── desktop/                 # 唯一可运行产品：Electron 壳（main / preload / renderer 挂载）
├── packages/
│   ├── ui/                      # 渲染层（侧栏、工作区、设置、主题 token）
│   ├── host/                    # 会话 / 设置 / 权限 / 拉起 Kernel；入口 src/main.ts，bin: nuum-host
│   ├── kernel/                  # 模型循环、工具执行；入口 src/main.ts，bin: nuum-kernel
│   ├── executor/                # 应用级执行 daemon、执行记录、隔离工具进程
│   ├── protocol/                # Desktop ↔ Host ↔ Kernel 的 JSON-RPC 契约
│   ├── tools/                   # 工具注册与内置工具
│   └── sandbox/                 # 工具执行沙箱
├── scripts/
│   └── smoke-host.mjs           # Host stdio 冒烟
├── docs/coding/                 # 开发规范（原则 / 测试 / 提交）
├── dependency-cruiser.cjs       # 包边界门禁
└── AGENTS.md                    # 本文件
```

`apps/` 放可运行产品。`packages/` 放库与进程入口：Host / Kernel 的可执行文件是各自 `dist/main.js`。

## 进程与通信

```
Renderer  --IPC-->  Desktop main  --stdio RPC-->  Host  --stdio RPC-->  Kernel
   UI         壳 / 密钥 / spawn         会话与设置              模型与工具
```

- Desktop spawn Host：`packages/host/dist/main.js`，并传入 `--kernel-entry packages/kernel/dist/main.js`。
- Host spawn Kernel。Renderer 只调用 Host RPC（`HostMethods` / `HostEvents`）。
- Host 另行监督 `packages/executor/dist/main.js`，通过私有 Unix socket 授权上下文；Kernel 使用该上下文调用文件、搜索和 shell。`RunWorkCLI` 也经过 daemon。禁止生产代码绕回 Host/Kernel 直接执行。
- 当前 OS 隔离仅验证 macOS，通过 sandbox-runtime 的 Seatbelt 与网络代理落实；不支持的平台拒绝执行。构建 executor 时必须生成 `dist/worker-bundle.mjs`。
- Kernel 是 Host 拉起的引擎子进程，协议为 stdio JSON-RPC。
- API Key 由 Desktop `safeStorage` 保管，经 Host RPC 下发；`PublicSettings` 只带 `hasOpenaiKey` / `hasAnthropicKey` / `hasDeepseekKey`。

跨包共享面是 `@nuum/protocol`。

## 包职责

| 改动 | 目录 |
|---|---|
| 窗口、托盘、拖拽区、spawn 路径、密钥落盘 | `apps/desktop` |
| 侧栏、对话、输入栏、设置弹层、主题 | `packages/ui`（`apps/desktop/src/renderer` 只挂载） |
| 会话 CRUD、转写、权限预检、设置、工具审批 | `packages/host` |
| 模型路由、turn 循环、工具执行 | `packages/kernel` |
| RPC 方法名、事件、zod 结构 | `packages/protocol` |
| 工具定义与执行 | `packages/tools`、`packages/sandbox` |

侧栏列表实体是 `AgentView`（agent）。

## UI 实现约束

Nuum 的桌面 UI 采用紧凑、原生、低视觉噪音的 Grokbot-like 设计语言。

- UI 改动必须遵循 [UI 规范](./docs/coding/ui-guidelines.md)。
- `packages/ui` 是 UI 组件、样式和主题 token 的实现位置；不要在 `apps/desktop/src/renderer` 复制组件或覆盖样式。
- 优先复用主题 token 和 `packages/ui/src/kit` 中的基础组件。
- 不得为了复刻参考界面凭空增加业务字段。所有可编辑字段必须能追溯到 `@nuum/protocol` 中的真实 schema 和 Host 持久化能力。
- Grokbot 仅作为视觉与交互参考；Nuum 的领域模型、会话真源和能力边界仍以自身协议及文档为准。
- UI 修改完成后必须在实际 Electron 窗口中验证，不能只依赖浏览器或静态代码检查。

## 允许的依赖方向

由 `pnpm run lint:deps`（`dependency-cruiser.cjs`）检查。允许的边：

- `apps/desktop` → `@nuum/ui`、`@nuum/protocol`
- `packages/host` → `@nuum/protocol`；运行时 spawn Kernel 可执行文件
- `packages/kernel` → `@nuum/protocol`、`@nuum/tools`、`@nuum/sandbox`
- `packages/tools` → `@nuum/protocol`、`@nuum/sandbox`
- `packages/sandbox` → `@nuum/protocol`
- `packages/executor` → `@nuum/protocol`、`@nuum/tools`、`@nuum/sandbox`；Host/Kernel 只能通过协议调用 executor，不能导入其实现。
- `packages/ui` → `@nuum/protocol`

## 启动与验证

```bash
pnpm install          # Node >= 22，pnpm 10
pnpm dev              # 先编 Host + Kernel，再 electron-vite
pnpm typecheck
pnpm test             # 包测试 + scripts/smoke-host.mjs
pnpm run lint:deps
```

`apps/desktop` 的 `dev` / `preview` 使用 `env -u ELECTRON_RUN_AS_NODE` 启动 Electron。改 UI 后在桌面窗口走通相关路径。

## 当前能力

三进程边界；主键是 agent（一条转录、一份记忆、可互发）；分段 system prompt；SendMessage 是助手唯一对用户出口；支持 Compact 检查点、每 agent workspace、按动作权限、新本地文件/搜索工具，以及每 agent 长驻 `shell` 会话。JSONL 转录保持唯一真源，UI 按因果关系投影出用户消息、agent 互发消息和可折叠工具活动，不维护第二条时间线。

Room / NunuBar 共用追加式 Work timeline，聊天与卡片为投影。成员真源已迁到 Room，Nunu 可加入多个房间；普通本地讨论使用主 session；同群同 compact 代际连续时增量，否则补最近 24 条背景，卡片按参与 Nunu 使用独立可恢复 session。同 Nunu 共用一个执行槽。SendMessage 将卡片交付/阻塞摘要与流转作为一个事件提交；UI 支持房间升级、独立执行记录及人工验收。建卡 Nunu 固定负责，worker 回报自动返回负责人卡片 session，阻塞待用户确认；Room / NunuBar 无 @ 均唤醒，群聊采用三轮、十条公开消息的顺序循环及提及选择，不持久化循环位置。客户端快照水位仅管理房间顺序，与模型输入位置分离。通用 compact 支持后台准备、长 run 调用边界应用、版本校验和取消；个人会话仅显示群聊参与提示。不确定执行须显式继续；跨用户推迟 V3，验证及限制见 [实施进度](./docs/workbar/implementation.md)。

Proactive 基座按 `AgentSettings.proactive` 保存每个 Nunu 的独立策略，本期菜单栏只展示默认成员；启停、定时暂停、检查与活动记录由 Host 管理。当前没有产品上下文来源，不调用模型或执行 proactive 行动。关闭主窗口后保留菜单栏与后台进程，退出 Nuum 才结束。

工作区由 Host 分配：个人使用系统文稿/Nuum/<名称>，同房间成员使用文稿/Nuum/Rooms/<房间名称>。授权保存在每 Nunu 的 settings.json，按工作区记忆命令和网络目标；默认工具断网。资料卡提供配置组件，客户端设置不再保存当前 Nunu 目录；NunuBar 无 goal、独立设置菜单或右上角工作中计数。生命周期和验收见 [执行 daemon 实施记录](./docs/reviews/2026-10-20-sandbox-implementation.md)；不得新增锁或隐含扩展现有调度互斥。

2026-10-22 权限更新：工作区内普通执行免逐条审批；外部文件与命令使用 external_operation，通过 Host 审批后在独立受限上下文执行。审批以模型理由为主，按钮为单次允许／始终允许／拒绝；长期规则按 Nunu 保存，拒绝按用户任务隔离。规则与验证见 [本轮权限记录](docs/reviews/2026-10-22-per-agent-permissions.md)。

沙箱与权限的长期维护入口：[技术架构与产品规则](docs/sandbox/README.md)。修改执行、授权、工作区或审批行为时同步更新该目录；历史 reviews 保留阶段验收记录。
