# Nuum macOS 应用分析

分析基线：`main` @ `9e4a3adf6e0b3931e35202ee03a6a3ba55a22344`（`feat(ui): add three randomized 3D Nunu unboxing animations`）。本文只描述仓库里已经存在的行为。`README.md` 指向的 `AGENTS.md`、`docs/workbar/`、`docs/coding/`、`docs/proactive/` 被 `.gitignore` 的 `/docs/*` 排除，工作区里不存在，不把它们当作已实现功能。

Nuum 是 Steve 的本地优先桌面伴侣应用。每个 **Nunu** 有自己的身份、记忆和工作区。用户可以一对一交谈，把多个 Nunu 放进 **Room** 讨论，再把 Room 升级成 **NunuBar** 用任务卡片交付工作。模型请求发到用户自己配置的 provider。没有账号、没有后端、没有多设备同步。

## 1. 技术栈

这不是 Swift / AppKit 工程。Mac 桌面壳是 Electron，领域逻辑是 TypeScript，跑在 Node.js 上。

| 层 | 选择 | 依据 |
| --- | --- | --- |
| 包管理 | pnpm `10.33.0`，workspace `apps/*` + `packages/*` | `package.json`，`pnpm-workspace.yaml` |
| 任务编排 | Turborepo `^2.5.6` | `turbo.json`，根 `package.json` |
| 语言 | TypeScript `^5.9.2`，Node `>=22.12.0` | `package.json` `engines` |
| 桌面壳 | Electron `^38` + electron-vite `^4` + Vite `^7` | `apps/desktop/package.json` |
| UI | React `^19.2`，无 React Router | `apps/desktop/package.json`，`apps/desktop/src/renderer/App.tsx` |
| 契约 | Zod | `packages/protocol/src/domain.ts` 等 |
| Markdown | `react-markdown` + `remark-gfm` | `packages/ui/package.json` |
| 3D 开箱 | `three` `^0.186` | `packages/ui/package.json`，`packages/ui/src/conversation/nunu-unboxing.tsx` |
| OS 隔离 | `@anthropic-ai/sandbox-runtime` `0.0.80` | `packages/sandbox/package.json` |
| 测试 | `node --test` / `tsx --test`，外加 `scripts/smoke-host.mjs` | 根 `package.json` `test` |
| 依赖方向 | dependency-cruiser | `dependency-cruiser.cjs` |
| 许可 | Apache-2.0 | `LICENSE`，根 `package.json` |

没有 SQLite，没有原生 Swift 模块，仓库里也没有 Android / Kotlin 代码。

## 2. 模块与目录

```text
apps/desktop          Electron main / preload / renderer
packages/ui           React 界面。只允许依赖 @nuum/protocol
packages/host         Agent 状态、转录、记忆、权限、调度、Room/NunuBar
packages/kernel       模型循环与工具执行。不知道 agent 是谁
packages/protocol     RPC 与领域契约（Zod）
packages/tools        内置工具
packages/sandbox      进程内执行边界与持久 shell
packages/executor     独立执行守护进程。darwin 以外直接拒绝
scripts               smoke、临时目录测试、品牌资源脚本
output/brand          品牌原始素材，不是运行时模块
```

`dependency-cruiser.cjs` 把边界写成了硬规则：

- `kernel` / `sandbox` / `tools` / `executor` 不能依赖 `host`、`desktop`、`ui`。
- `host` 不能 import `kernel`、`sandbox`、`tools`、`executor`、`ui` 的实现，只能走 RPC / protocol。
- `ui` 不能依赖任何后端包。
- `kernel` 与 `sandbox` / `tools` 不能 import `executor`；`executor` 也不能 import `kernel`。

这是 Android 模块依赖要原样保住的不变量。`packages/protocol/src/kernel-contract.ts` 写明：Kernel 只认 `runId`，`runId → agentId` 由 Host 维护。

## 3. 进程与数据流

一次桌面会话里有三条进程边界。

```text
Renderer (React)
  │  contextBridge：window.nuum
  │  ipc  host:request / host:event
Electron main (apps/desktop/src/main/index.ts)
  │  持有 secrets.bin（safeStorage）
  │  spawn node packages/host/dist/main.js
  │  stdio JSON-RPC（JsonRpcPeer）
Host (packages/host)
  │  spawn node packages/kernel/dist/main.js
  │  stdio JSON-RPC
Kernel
  │  HTTPS SSE → OpenAI / Anthropic / DeepSeek
  │  无 execution endpoint 时：进程内 createSandbox + tools
  └  有 execution endpoint 时：Unix socket HTTP RPC → Executor
Executor (packages/executor，仅 darwin)
  └  再 spawn isolated-launcher.js，里面才是 OS sandbox 里的 worker
```

启动顺序见 `apps/desktop/src/main/index.ts`：

1. `userData/data` 作为 `--data-dir`，`userData` 作为 `--private-dir`，`app.getPath("documents")` 作为 `--documents-dir`（可用 `NUUM_DOCUMENTS_DIR` 覆盖）。`NUUM_USER_DATA_DIR` 可把整份 profile 指到别处。
2. `spawn("node", [hostEntry, ...])`，stderr 继承到桌面进程。
3. `sys.hello` 之后，若 `secrets.bin` 里有任一 key，调用 `settings.set` 把三把 key 注入 Host 内存。
4. `settings.get` 取语言，安装应用菜单，创建主窗口，再创建 menu bar 的 `ProactiveTray`。
5. Host 退出时 renderer 收到 `host.kernel.down`，reason 为 `host-exit`。
6. 窗口关闭时如果 tray 还在，则 hide 而不是退出。`before-quit` 对 Host 发 `SIGTERM`。Host 在 stdin `end`/`close` 时走 `detach()`（`packages/host/src/main.ts`），已接受的 executor 工作可以留下待认领。

Renderer 没有路由库。`apps/desktop/src/renderer/main.tsx` 用查询参数 `?surface=proactive` 在主窗口 `App` 和菜单栏弹层 `ProactiveSurface` 之间二选一。主窗口内部用 React state 切换中心区：创建 NunuBar、`WorkBoard`，或一对一 `ConversationWorkspace`。其上再叠创建 Nunu、资料面板、设置。

JSON-RPC 帧是换行分隔的 JSON，类型在 `packages/protocol/src/rpc-frame.ts`，对端是 `packages/protocol/src/transport.ts` 的 `JsonRpcPeer`。Executor 不用这条 stdio，而是 Unix socket 上的 HTTP `POST /rpc`，body `{ instance, method, params }`，`Authorization: Bearer <token>`（`packages/protocol/src/execution-client.ts`）。socket 路径形如 `$TMPDIR/nuum-exec-<hash16>/exec.sock`，记在 `dataDir/executor/owner.json`。

Host 对 UI 暴露的方法集中在 `packages/protocol/src/host-contract.ts` 的 `HostMethods`。事件在 `HostEvents`：agent 更新、消息 delta/完成、工具 pending/started/completed、错误、结束、work 更新、时间线、目录、proactive、settings、kernel down。

## 4. Agent loop 与工具调用

### 4.1 Kernel turn

实现：`packages/kernel/src/loop.ts` 的 `startTurn`。

- 常量 `MAX_ROUNDS = 16`。用尽后不假装正常结束，而是再发一段文本 `Stopped after 16 tool rounds without a final answer.`，然后 `turn.ended` status `idle`。
- 模型选择是唯一外部副作用，抽成 `TurnDeps.selectModel`，单测可以替换。
- 每轮可选地先发 `turn.context`（带 `usedTokens`），等 Host `turn.provideContext` 换一批消息。压缩后若仍超过 `contextWindow * 0.9`，抛出 `Context capacity exhausted; execution paused without replaying tools.`
- `streamChat` 产出 `text` / `thinking` / `tool_call`。文本和 thinking 以 `turn.delta` 流出，`part` 为 `text` 或 `thinking`。
- 没有 tool call 就 `turn.ended` status `idle`。
- 取消是 `TurnCancelled`，发 `turn.ended` status `cancelled`，不发 `turn.error`。
- 用户看不见模型的自由文本和工具输出。只有「发声工具」到达用户。direct run 默认 `SendMessage`；work run 由 Host 传入 `voiceToolNames`（`PostToWork` / `HandoffTask` 等）。静默提醒按阈值注入合成 user 消息，只留在本轮内存，不写转录：从未发声且工具数超过 1 次发 ack；发过声后又埋头发 result；工具数超过 6 发 silence。每种提醒每个静默段只发一次。

工具分三类：

1. **委派工具**。名字在 `delegatedTools` 里。Kernel 发 `turn.tool.delegate`，然后干等 Host `turn.provideToolResult`。定义必须带完整 schema，只传名字会被滤掉，模型就永远看不到它（`kernel-contract.ts` 注释）。
2. **本机工具，进程内 sandbox**。没有 `params.execution` 时 `createSandbox`，先 `authorize`。`deny` 直接把原因回给模型。`ask` 发 `turn.tool.pending`，等 `always | once | deny | never`。`never` 还会把 sandbox 权限打成 `never`。通过后 `turn.tool.started`，再 `tool.execute`。
3. **本机工具，远端 executor**。`resolveRemoteTool`：`submit`，失败则按 0/200/800 ms 重试 `status`。结果是 `approval` 时发 pending，决定本身由 Host 经特权连接写回 executor，Kernel 只再 `status`。`running` 时每 100 ms 轮询。取消时 `cancel`。

`request_network` 和 `external_operation` 的 `execute` 在工具包里直接抛错，要求执行守护进程和 Host 审批（`packages/tools/src/network-tool.ts`、`external-tool.ts`）。它们不是进程内 sandbox 能完成的动作。

错误码：`packages/protocol/src/errors.ts`。Kernel 1000–1007（internal、busy、cancelled、model、tool、sandbox、invalid）。Host 2001–2012（找不到 agent、忙、无工作区、无 key、kernel down、数据目录锁、work 不存在 / 冲突 / 禁止）。Desktop 3001–3003（secret store、选文件夹、窗口）。

### 4.2 Host 在 turn 之外做的事

`packages/host/src/runtime.ts` 是调度中心。启动一个 turn 之前：

- `precheck`（`packages/host/src/precheck.ts`）：agent 存在、不忙、当前 provider 有 key。没有 key 是 Host 错误 `NO_API_KEY`，不会把空 key 送进 Kernel。
- 用 `packages/host/src/prompt.ts` 拼 system prompt。身份段和记忆段按 epoch 冻结进 `prompt-cache.json`，为了让前缀逐字节稳定，好命中 provider 的 prefix cache。提示词写明这是跑在用户自己 Mac 上的本地 agent。
- `assembleContext`（`packages/host/src/context.ts`）把转录修成模型消息。`activeTranscript` 只取最近一次 `compact` 事件及其 `tailFromSeq` 之后的事件。
- 若估算 token 超过窗口的 0.75，先压缩再发。压完仍超过 0.75 就拒绝这次输入，不重放工具。
- 窗口表写死在 `contextWindow()`：`deepseek:deepseek-chat`、`openai:gpt-4o`、`anthropic:claude-sonnet-4-20250514` 都是 128_000，未知模型也回 128_000。测试可注入 `contextWindowTokens`。
- 轮中 Host 收到 `turn.context` 后，在约 80% 处后台压缩，约 85% 处 `provideContext` 换上新消息。

压缩（`packages/host/src/compaction.ts` + `context.ts`）：按 24_000 字符切证据，最多 16 块，否则抛错要求人工看转录。每块调 Kernel `summarize.run`（无工具、不落盘、不发 turn 事件）。摘要再按 3 组合并，单次摘要上限 6_000 字符，超时 30 秒。结果以转录事件 `type: "compact"` 追加，并 `bumpPromptEpoch`。

`summarize.run` 是 Host 碰模型的唯一合法路径，而且仍然经由 Kernel。`kernel-contract.ts` 写明 Host 绝不直接拿 model port。

调度（`packages/host/src/scheduler.ts`）：全局最多 `DEFAULT_MAX_CONCURRENT_RUNS = 3`，每个 agent 同时只有一个 run，嵌套的 `projectRoot` 也不能重叠。

唤醒（`packages/host/src/wake.ts`）：`WakeQueue` 只在内存。`MAX_HOPS = 3`，`RATE_LIMIT = 3` / `RATE_WINDOW_MS = 60_000`，每个 run 最多 `MAX_CREATES_PER_RUN = 1` 个新 agent，全局 `MAX_AGENTS = 50`。进程重启后从转录恢复尚未完成的 wake，而不是从一块「运行中」磁盘状态恢复。

Room 讨论（`packages/host/src/room-discussion.ts`）：`discussionLimits = { rounds: 3, messages: 10, perTurn: 2 }`。用户 `chat.posted` 之后按 @ 或默认全体选出应答者，每个应答者走同一条 `kernel.start`。结束状态是 `completed`、`cancelled` 或 `interrupted`。

NunuBar 执行（`packages/host/src/work-execution.ts`）：时间线事件变成 intent，落到卡片 session，再 `launch` 进 Kernel。卡片转录在 `work-sessions/`，房间可见的话走 work 时间线加委派工具。启动时 `replayWorkDispatches()` 重放讨论和卡片投递。

执行结果认领（`packages/host/src/execution-recovery.ts`）：转录是唯一的持久结果。executor 先写完、Host 后崩溃时，重启用 `executionId` 把 finished 输出补回转录，不把同一请求再跑一遍。

### 4.3 工具清单

内置工具注册于 `packages/tools/src/builtin.ts`。权限动作是 `read-file | list-directory | write-file | run-command | network`（`domain.ts`）。

| 工具 | action | mutating | 行为 |
| --- | --- | --- | --- |
| `read` | read-file | 否 | UTF-8，可指定行范围。图片走二进制再 base64。`MAX_READ_CHARS = 30_000` |
| `write` | write-file | 是 | 覆盖写 UTF-8，返回 unified diff，`MAX_DIFF_CHARS = 12_000` |
| `str_replace` | write-file | 是 | 精确替换，默认必须唯一 |
| `multi_str_replace` | write-file | 是 | 一次原子多段替换 |
| `delete` | write-file | 是 | 删文件或目录树 |
| `ls` | list-directory | 否 | 目录树，`MAX_TREE_CHARS = 20_000` |
| `glob` | list-directory | 否 | 递归 + `path.matchesGlob`，最多 500 条 |
| `grep` | read-file | 否 | `spawn` 外部 `rg`（或 `NUUM_RG_PATH`），输出上限 500_000 |
| `shell` | run-command | 是 | 持久 bash。默认 `block_until_ms` 30_000。也可用 `shell_id` 查看 |
| `request_network` | network | 否 | schema only，进程内 `execute` 抛错 |
| `external_operation` | run-command | 是 | schema only，进程内 `execute` 抛错 |

`grep` 依赖本机 `rg`。`shell` 依赖 `/bin/bash`、`/usr/bin/base64`、`/usr/bin/tr`（`packages/sandbox/src/persistent-shell.ts`）。没有 PTY，是 dumb pipe。

委派工具的名字和 schema 在 `packages/protocol/src/product-tools.ts`，Host 实现在 `packages/host/src/delegated-tools.ts`。只注册有 handler 的定义，避免「声明了但一调就报没实现」。

| 工具 | 谁用 | 作用 |
| --- | --- | --- |
| `SendMessage` | direct，以及 work 里换成卡片口径 | 用户唯一看得到的出口：`text` / `attachment` / `widget`。发 widget 结束本轮 |
| `update_state` | direct | 改自己的 profile，或写/忘 memory（tier：`profile` / `log` / `note`） |
| `CreateAgent` / `UpdateAgent` | direct | 新建或修改队友 |
| `SendToAgent` | direct | 异步给另一个 agent 发消息，可标 priority |
| `ReadAgentTranscript` | direct | 读队友转录尾部，limit ≤ 200 |
| `CheckAgent` | direct | 只读：是否在跑、最近工具 |
| `StopAgent` | direct | 停掉队友的 run |
| `CreateTask` / `ClaimTask` / `ReadTask` | work | 建卡、按 revision 认领、读卡或列出 |
| `PostToWork` | work | 往房间进度里发一句 |
| `HandoffTask` | work | 交回 review / blocked / done，可带 deliverable |
| `ReadWorkTimeline` | work | 分页读时间线，默认 30，最多 100 |
| `RunWorkCLI` | work | 跑目录里登记过的 CLI，不做 shell 展开。`mutating: true` |
| `DelegateWork` | work | 把房间成员派到某张卡上，委派人仍对结果负责 |

`TODO.md` 里三件还没做：CheckAgent 的 UI 卡片、SendMessage 的 secret-request 载荷（凭据不进转录）、widget 的 `dismissOnMoveOn`。

### 4.4 上下文估算

`packages/protocol/src/context-budget.ts` 的 `estimateModelTokens`：把去掉图片字节的消息和工具 schema `JSON.stringify`，ASCII 约 3 字符一个 token，非 ASCII 约 2 字符一个 token，每张图再加 8_192。这是预算，不是 provider 的真实 tokenizer。

## 5. 模型 provider 与 API key

Provider 只有三个：`openai`、`anthropic`、`deepseek`（`ProviderId`）。默认模型（`DEFAULT_MODEL_ID`）：

- openai → `gpt-4o`
- anthropic → `claude-sonnet-4-20250514`
- deepseek → `deepseek-chat`

设置界面在 DeepSeek 下还可以改成 `deepseek-reasoner`（`apps/desktop/src/renderer/App.tsx`）。没有按会话切换模型的控件。文案里提到 session model，解析函数 `resolveSessionModel`（`packages/host/src/model.ts`）会看 agent 自己的 `settings.model`，但界面没有入口去改它。

选路（`packages/kernel/src/model/router.ts`）：

- anthropic → `AnthropicModel`，`POST https://api.anthropic.com/v1/messages`，头 `x-api-key` 和 `anthropic-version: 2023-06-01`。system 消息抽成顶层 `system`。thinking 来自 `thinking_delta`。工具是 `input_schema`。默认 `max_tokens` 4096。
- deepseek → `OpenAIModel("https://api.deepseek.com/v1", "DeepSeek")`。
- openai → `OpenAIModel()`，默认 `https://api.openai.com/v1/chat/completions`，头 `Authorization: Bearer`。

两边都是 `stream: true`，手写 SSE，不用第三方 LLM SDK。OpenAI 兼容路径把 `reasoning_content` 当成 thinking。DeepSeek 不接收图片：`toOpenAIMessage(..., supportsImages=false)` 会把图片换成一句说明文字。OpenAI 用 `image_url` data URL，Anthropic 用 base64 `source`。图片 MIME 只允许 jpeg / png / gif / webp，而且 base64 只活在当轮 Kernel 内存里，不进转录（`ModelImage` 注释）。

Key 的解析顺序（`resolveAvailableModel`）：优先用户选的 provider；没有 key 就按 `deepseek → openai → anthropic` 找第一把存在的 key，并退回该 provider 的默认模型。

### Key 存在哪

两处，职责不同。

**磁盘（Desktop 主进程）** `apps/desktop/src/main/index.ts`：

- 路径：`app.getPath("userData")/secrets.bin`。
- `safeStorage.isEncryptionAvailable()` 为真时用 Electron `safeStorage.encryptString` / `decryptString`。在 macOS 上这是 Keychain 支持的密文。
- 加密不可用时退回 UTF-8 明文写入同一个文件。这是现有行为，不是目标行为。
- Renderer 通过 preload `getSecrets` / `setSecrets` 能拿到明文，用来填设置页的 password input。blur 时写回。
- 发给 Host 的 `settings.get` 公共视图只有 `hasOpenaiKey` / `hasAnthropicKey` / `hasDeepseekKey` 三个布尔（`PublicSettings`）。

**内存（Host）** `packages/host/src/agent-store.ts` 的 `secrets` 字段，由 `runtime.ts` 的 `settings.set` 更新。Host 源码里没有把 API key 写进 `settings.json` 的路径。每次 `turn.start` 和 `summarize.run` 都把整份 `Secrets` 对象交给 Kernel。

工具的沙箱把下列路径放进 `denied`，即使权限是 `always` 也不许读（`runtime.ts` 里 `toolRoots` / `prepareExecution`，测试在 `packages/sandbox/src/create-sandbox.test.ts`）：

- `dirname(dataDir)/secrets.bin`
- `dataDir/host-secrets.json`
- `dataDir/credentials.json`
- `dataDir/secrets.json`

`protectedPaths` 还包括整个 `dataDir` 和可选的 `privateDir`。

## 6. 持久化

默认数据根：不经 Electron 时是 `~/.nuum`（`packages/host/src/main.ts`）；经桌面壳时是 Electron `userData/data`。没有数据库。JSON 用原子写（临时文件再 rename，`agent-store.ts` 的 `writeJsonAtomic`）。转录是 append-only JSONL，最后一行写坏只丢这一行（`agent-store.test.ts`）。

单实例锁：`dataDir/host.lock`，内容是 pid 和时间。

全局：

| 路径 | 内容 |
| --- | --- |
| `settings.json` | `defaultToolPermission`、`defaultModel`、`theme`、`language`、`sidebar`。不含 key |
| `migrations.json` | `MIGRATION_VERSION = 3` |
| `room-memberships-v2.json` | 成员关系迁移标记 |
| `workspaces/<sha256>.json` | 工作区记录，id 是 owner 的 sha256 |
| `executor/owner.json` | socket 路径与 token |
| `executor/discovery.json` | executor 自己写的发现信息 |
| `executor/daemon.log` | 守护进程日志 |

每个 agent，`agents/<id>/`：

| 文件 | 内容 |
| --- | --- |
| `profile.json` | id、name、description、tags、avatarColor / Shape / Material、createdAt。Host 是唯一写者 |
| `settings.json` | model、workspace、execution、hiddenFromSidebar、proactive、workMembership |
| `transcript.jsonl` | 事件流 |
| `read-cursor.json` | 已读游标。未读是游标和末条 seq 的比较，不单独落盘 |
| `tool-approvals.json` | 已记住的允许 / 拒绝 |
| `prompt-cache.json` | 冻结的 prompt 前缀 |
| `memory/profile.md` | 常驻事实，上限 100 条 |
| `memory/log/YYYY-MM.md` | 按日的 fact 和 note。召回字符预算 4_000，半衰期 30 天 |
| `proactive-activity.json` | proactive 活动，只存 context ref，不存正文和凭据 |
| `scratch/` | 工具草稿目录 |

记忆的真源就是这些 Markdown。`memory.ts` 明确不另写 `memory` 事件，避免第二真源。`update_state` 的调用痕迹留在 `tool` 事件里。重复事实按归一化 key 去重，再写是幂等。

Work，`works/<id>/`：`profile.json`、`catalog.json`、`runtime-version.json`、`timeline.jsonl`。迁移可能留下 `timeline.jsonl.pre-simplification.bak`。

卡片 session：`work-sessions/<sha256(workId)>/<sha256(workId,taskId,agentId,membershipRevision)>/` 下的 `session.json` 和 `transcript.jsonl`。卡片自己的 scratch 在 session 目录里。

工作区目录不在 dataDir 里。`packages/host/src/workspaces.ts` 在文档目录下创建 `Nuum/` 和 `Nuum/Rooms/`，再按 label 放项目根。

附件不进 dataDir。`packages/host/src/attachments.ts` 把上传写到 `{projectRoot}/.nuum-attachments/upload-<random>/`，文件名 `{index}-{basename}`，mode `0o600`，`flag: "wx"`。限额在 `packages/protocol/src/attachments.ts`：最多 5 个，单个 10 MiB，合计 20 MiB。非图片且 ≤ 64 KiB 的 UTF-8 会内联进文本。图片只在当轮请求里从这些路径再读出来。

**不落盘的运行态**（`domain.ts` 里 `AgentRuntime` 的注释，以及 `HostRuntime`）：`status` 来自内存调度，重启后磁盘上不可能留下假的 `running`。同样只活在内存里的还有进行中的 run、pending tool、压缩任务、讨论、wake 队列，以及 API key。`lastActivityAt` 来自末条事件的 `createdAt`。`unread` 来自已读游标。

转录事件类型（`packages/protocol/src/transcript.ts`）包括 `user`、`wake`、`assistant`（parts：thinking / text / tool_call）、`tool`、`message`（对用户可见的 SendMessage 结果）、`compact`、`profile`、`peer`、`notice`。`wake` 的来源是另一个 agent、某次 work，或占位的 `routine`（注释写明本版不产生，留给以后的定时唤醒）。

Work 事件（`packages/protocol/src/work.ts`）包括 `chat.posted`、`task.created` / `claimed` / `assigned` / `delegated` / `transitioned` / `progressed` / `handed_off`，以及讨论和执行的开始/结束。任务状态：`proposed`、`ready`、`in_progress`、`blocked`、`review`、`done`、`cancelled`。优先级 `low | normal | high`。角色 `coordinator | worker | observer`。成员关系带 `revision`，拖入拖出用 CAS。目录项 `skill | cli | knowledge | local-tool`。knowledge 固定 `readOnly: true`。

UI 自己的偏好不进 Host：侧栏宽度在 `localStorage` key `nuum.ui.sidebar.v2`；身份模板是否已经编辑过在 `nuum-identity-edited`（`agent-templates.ts`）。

## 7. 权限、沙箱与系统集成

权限档 `ToolPermission = always | ask | never`。全局默认是 `ask`（`Settings.defaultToolPermission`）。agent 可以用 `workspace.toolPermission` 覆盖，`null` 表示跟随全局。执行偏好 `ExecutionPreferences` 还有：`commands`（ask/always/never，默认 ask）、按工作区记住的 `commandGrants`、`externalGrants`、`networkGrants`。网络目标正则只允许 `hostname:(443|80)`（`packages/protocol/src/permission-rules.ts`）。

进程内沙箱（`packages/sandbox/src/create-sandbox.ts`）的根是 `home`、`project | null`、`scratch`、`terminals`、`denied[]`、`readOnly[]`。判定顺序：denied 路径拒绝；readOnly 上可读不可写；必须落在 home 或 scratch 之下；scratch 和 project 预批准；agent 自己的目录对工具只读（要改记忆走 `update_state`）；其余走 standing decision。`always` 放行，`never` 拒绝，否则 `ask`。命令先取第一个非 env 赋值的 token 当 target，并套 `DENY_COMMANDS`：对 `/`、`~`、`$HOME` 的 `rm -rf`，`mkfs`，`dd if=`，以及 fork bomb 形态。

OS 级隔离只在 executor 路径：

- `packages/executor/src/runner.ts`：`process.platform !== "darwin"` 时抛出 `This release has only validated macOS isolation; execution is disabled on this platform.`
- 集成测试同样 `skip: process.platform !== "darwin"`（`executor/src/isolation.test.ts`、`host/src/executor-client.test.ts`）。
- worker 里的 sandbox 权限被设成 `always`，因为审批已经在进 worker 之前做完。注释写明 Host 凭据不进 worker。
- 文件系统策略 `denyRead: ["/"]`，再按名单 `allowRead`。名单里有 macOS 路径（`/System`、`/usr`、`/bin`、`/Library/Apple`、`/private/etc` 等）以及 workspace、scratch、只读知识根。
- 网络：`allowedDomains` 来自 context，`allowLocalBinding: false`。
- 外部命令的 `PATH` 固定为 `/usr/bin:/bin:/usr/sbin:/sbin`，`HOME` 是 context root。
- 真正的包裹由 `@anthropic-ai/sandbox-runtime` 的 `SandboxManager.wrapWithSandbox` 完成。Nuum 源码里没有直接写 `sandbox-exec`。平台不支持就抛 `OS sandbox is unavailable on this platform`。

Executor RPC：`hello`、`register`、`submit`、`status`、`cancel`、`decide`、`acknowledge`、`contextStatus`、`revoke`、`suspend`、`shutdown`。非 owner 的 submit 要求 5 秒内有过 Host 联系，除非是在重放已知 id。账本在内存，最多 128 个 in-flight，输入 ≤ 1 MiB，输出切片 100_000，同一 id 不同 input 报错，已 ack 的 id 禁止重放。空闲 30 秒且账本空、owner 无联系就退出。

Desktop 用到的系统能力（`apps/desktop/src/main/index.ts`、`proactive-tray.ts`）：

- 隐藏标题栏和红绿灯：`titleBarStyle: "hiddenInset"`，`trafficLightPosition: { x: 16, y: 15 }`。拖拽区在 `packages/ui/src/shell.css` 的 `.sand-cover-drag`，`--sand-traffic-lights-inset: 78px`。
- 应用菜单使用 Electron 的 macOS role：`about`、`hide`、`hideOthers`、`unhide`、`quit`、`front` 等。标签随 `zh-CN` / `en` 切换。
- Menu bar tray：`Tray` + template PNG（`apps/desktop/resources/proactive-onTemplate.png` 与 off，含 @2x）。状态文案含「服务未连接 / Unavailable」。
- `dialog.showOpenDialog` 选目录，`shell.openPath` 打开附件，`shell.openExternal` 已在 main 注册，但 preload 没有暴露。
- 窗口控制 IPC（minimize / zoom / close / getState）和 `theme.get` 已注册。`theme.get` 固定返回 `{ theme: "system" }`。preload 没有把这些交给 renderer。真正的主题走 Host `settings.set`。
- `webPreferences`：`contextIsolation: true`，`nodeIntegration: false`，`sandbox: false`（preload 需要 Node 能力）。

Proactive（`packages/protocol/src/proactive.ts`，`packages/host/src/proactive.ts`）：策略有 `enabled`、`pausedUntil`、最多 20 个不重复的 `sourceIds`、`intervalMs` 在 60_000 到 3_600_000，默认 300_000。`ProactiveSnapshot.actionsAvailable` 的 schema 是字面量 `false`。Host 每秒 tick，到点只收集 context reference。源码注释：`This foundation stops at context references. No model run or action execution is wired yet.` 活动账本不存正文和凭据。

## 8. 设置

全局 `Settings`（`domain.ts`）：默认工具权限、默认模型、主题 `light | dark | system`、语言 `zh-CN | en`（缺省当中文）、侧栏组织。

设置页在 `ConversationWorkspace` 的 `SettingsOverlay` 里，分两段（`App.tsx`）：

- General：语言、主题、打开菜单栏面板。
- Models：默认 provider（DeepSeek / OpenAI / Anthropic）、DeepSeek 的 `deepseek-chat` 与 `deepseek-reasoner`、三把 API key 的 password 框。

没有暴露的设置项：`defaultToolPermission` 不在设置页里。每个 Nunu 的命令策略、工作区文件夹、已记住的 grant 在资料面板的 `ExecutionWidget`（`packages/ui/src/conversation/execution-widget.tsx`），不在全局设置里。

侧栏组织 `SidebarOrganization`：`pinnedAgentIds` 加若干 section（id、name ≤ 80、agentIds、可选折叠）。pin、分组成员、组 id 都必须唯一。

每个 agent 的 `AgentSettings` 还可以 `hiddenFromSidebar`。列表会把它滤掉，但没有界面开关。也没有删除 agent 的界面，尽管 `HostMethods.agentDelete` 存在。

## 9. 用户可见的功能与界面

主窗口默认 1200×800，最小 800×560，背景 `#111111`。设计语言是自研的 sand kit，不是 Material。原语在 `packages/ui/src/kit/sand-kit-primitives.tsx`：`SandButton`、`SandIcon`、`SandIconButton`，图标表 `sand-icon-registry.ts`（类型里留了 `darwin | win32 | linux`）。主题 token 由 `packages/ui/src/theme/runtime-theme-token-installer.ts` 安装到 `documentElement`，类名 `nuum-light` / `nuum-dark`。文案约 428 个 key，在 `packages/ui/src/i18n/messages.ts`，运行时 `t()`。菜单栏和 tray 的一部分字符串是主进程里的硬编码双语，不走这张表。

### 9.1 侧栏

`packages/ui/src/conversation/sidebar.tsx`。

- 搜索：agent 的名字、描述、标签；work 的预览。只过滤，不另建索引。
- 新建菜单：新建 Nunu，或新建 Room / NunuBar。
- 打开设置。
- 右键：置顶/取消、移入分组、新建分组、重命名分组、分组上移下移、解散分组、编辑资料、复制 Agent ID。
- 拖拽：重排置顶、拖进分组、拖进某个 work。
- 宽度可拖，可收起，存在 localStorage。组织结果通过 `settings.set` 的 `sidebar` 字段持久化。
- 未分组的 agent 和 work 按 `lastActivityAt` 混排。

### 9.2 一对一会话

`packages/ui/src/conversation/workspace.tsx`。

- 头：打开资料；运行状态驱动 Nunu 的表情（idle / thinking / working / waiting / error / sending / receiving / happy / wave）。
- 转录投影成 `ViewBlock`：用户消息、可见 `message`（文本、附件、widget）、通知、peer、以及折叠后的工具活动。thinking 和工具调用不是逐条铺开，`activity-groups.ts` 把它们收成组。
- 输入：草稿、发送、停止。`agent.send` / `agent.cancel`。
- 附件：选择文件、拖入、移除。限额与 protocol 一致。点历史附件走 `shell.openPath`。
- 工具审批条 `execution-approval.tsx`：拒绝、允许一次、始终允许。`allowAlways === false` 时没有「始终允许」。`ToolResolution` 还有 `never`，这条审批 UI 没有用它。若 pending 带了 `workId`，一对一界面把审批藏起来，改由 NunuBar 上该成员的审批条处理。
- Widget：选项最多 6 个，可带说明和 `default | primary | danger`，可允许自由输入。点选结果作为下一条用户消息。旧版 widget 字符串仍然渲染成 `<pre>`，注释写明真实渲染是下一版的事。
- Peer 抽屉：看 agent 之间的消息。
- 空状态文案是让用户直接问，或丢一个文件进来。

### 9.3 创建 Nunu 与开箱

`agent-creation.tsx` 加 `nunu-unboxing.tsx`。

- 名字最长 80。
- 颜色七个软色素：cream、green、orange、violet、blue、magenta、honey，另有遗留 id `black`。用户只选颜色。
- 形状 `circle | blob | droplet | cloud | tablet` 和材质 `plush | felt | matte | glass` 在创建时 `rollAgentAvatar()` 随机，之后绑定。隐藏材质 `aurora` 可被解析，但不在常规骰子里。
- 开箱是 three.js 场景，三种包装随机（`rollUnboxingPackage`），带彩纸。WebGL 失败则 `fallback`。`prefers-reduced-motion` 时跳到结束姿态。
- 角色模板只填文字，不改外观：Researcher、Project partner、Daily operator（`agent-templates.ts`）。创建页和身份弹窗共用。模板在第一次保存身份前出现。

头像素材在 `packages/ui/src/assets/nunu/`，约 9.4 MB：身体贴图 png 各 1–1.7 MB，动作图集 `actions-atlas.png` 约 2.1 MB，四条 webm（wave / cheer / think / sleepy）合计约 1 MB，另有一张 66 KB 的 portrait。

### 9.4 资料面板

`agent-profile-panel.tsx`。

- 改名字、标签、描述，套用角色模板。保存走 `agent.update`。
- 执行区：打开个人工作区文件夹、命令策略 ask/never、撤销 external / command / network grant。
- 打招呼只触发本地 portrait 反应，不发消息。

### 9.5 Room 与 NunuBar

创建对话框 `WorkCreation`：kind 为 `room` 或 `work`，加一个名字。Room 可以升级成 work（`work.update` `{ kind: "work" }`），成员和历史保留。`README.md` 把升级后的工作区叫 NunuBar。

`work-board.tsx`、`work-content.tsx`、`work-chat.tsx`、`work-dialog.tsx`：

- 任务泳道和交付物。状态标签来自 i18n。
- Room 时共享聊天默认展开。可以 @ 成员。
- 停止讨论；中断之后可以带一段历史窗口继续（`work.continue`）。
- 成员加入、离开、在 work 之间拖动。
- 能力目录：列表、添加、移除。添加对话框有「发现」页，文案是 Coming soon / Presets on the way；「导入本地」可用，对应 catalog 的 skill / cli / knowledge / local-tool。
- 每个成员自己的工具审批。
- 打开某张卡的执行历史（`work.task.transcript`）。
- 用户可以做状态迁移（blocked / review / done / cancelled）和 dispatch。

`App.tsx` 把 `onCreateTask` 传给了 `WorkBoard`，组件内部没有调用它。用户界面不能新建任务卡。建卡路径是模型的 `CreateTask`，或尚未接线的 `work.task.create`。`work.task.assign` 和 `work.member.move` 有 Host 方法，主界面没有对应按钮（成员移动走拖拽另一条路径）。

协作是本机的。`README.md` 写明跨用户协作还在计划中。

### 9.6 Proactive 菜单栏

`ProactivePanel`：打开/关闭、暂停一段时间、Check setup、打开某个 Nunu、回到主窗口、退出、重试。准备度文案把 context source 标成 Available 或 Not connected，把 agent actions 标成 Not connected，并说明这一版没有接上采集和自主行动。这和 Host 里 `actionsAvailable: false` 一致。

### 9.7 这一版用户实际做不到的事

以代码为准，而不是路线图：

- 删掉一个 Nunu（API 在，UI 不在）。
- 从侧栏隐藏一个 Nunu（字段在，开关不在）。
- 在聊天里换模型。
- 在设置里改全局工具权限默认值。
- 在 NunuBar 界面上自己建任务卡。
- 从能力商店发现预设（只有本地导入）。
- 让 Proactive 自己收集上下文并采取行动。
- 把旧版 widget JSON 渲染成真正的卡片。
- CheckAgent 的可视化、SendMessage 秘密输入卡、widget 随下一条消息自动收起（`TODO.md`）。
- 在非 macOS 上使用 executor 那条隔离执行路径。

## 10. macOS 专用与可移植

| 部分 | 判断 | 依据 |
| --- | --- | --- |
| Zod 契约、转录、work 状态机、token 估算、压缩策略、调度上限、wake 限额 | 可移植 | 纯数据与纯函数，只依赖协议类型 |
| Kernel turn 循环、提醒阈值、16 轮上限 | 可移植 | `loop.ts` 不碰 OS，模型端口是 `fetch` + SSE |
| OpenAI / Anthropic / DeepSeek 请求形状 | 可移植 | `packages/kernel/src/model/` |
| Host 的 prompt、记忆 Markdown、JSONL、审批规则 | 可移植 | 文件格式和规则与 OS 无关；提示词文本里写了 Mac，要改措辞 |
| React 信息架构（侧栏、会话、Room、NunuBar、设置、审批、widget） | 交互可移植，实现不可移植 | 组件是 DOM + CSS |
| three.js 开箱、webm、动作图集 | 资源可借鉴，运行时不可移植 | 依赖 WebGL 和浏览器媒体 |
| Electron 窗口、红绿灯、应用菜单、template tray | macOS 壳 | `titleBarStyle: "hiddenInset"`，Tray template image |
| `safeStorage` → Keychain，以及明文回退 | macOS 壳的秘密存储 | `index.ts` `readSecrets` / `writeSecrets` |
| `dialog` 选目录、`shell.openPath` | 桌面集成 | IPC |
| 进程内文件工具（read/write/ls/glob/delete/replace） | 逻辑可移植，路径语义是 POSIX | `node:fs` |
| `grep` 调用 `rg`，`shell` 调用 bash | 依赖桌面 Unix 用户空间 | `search-tools.ts`，`persistent-shell.ts` |
| executor、sandbox-runtime、Unix socket、`darwin` 硬门槛 | macOS 专用，而且是这一版唯一验证过的隔离 | `runner.ts` |
| 文档目录 `~/Documents/Nuum` | 桌面文件布局 | `workspaces.ts`，Electron `documents` |
| Proactive 的菜单栏常驻 | macOS 壳；行为本身还没接上 | tray + `actionsAvailable: false` |

## 11. 对 Android PoC 的直接推论

要忠实复现的是用户能看见、能操作的产品，加上驱动它的 turn 循环、记忆、Room / NunuBar 和三家模型。不要把 Electron、Node、`rg`、bash、`sandbox-runtime` 搬进 APK。

PoC 必须保住的不变量：

1. UI 不持有模型端口，也不把 API key 写进转录、日志或普通设置。
2. Kernel 只认 `runId`。agent、work、记忆都在 Host 一侧。
3. 用户只看见发声工具的产物。工具过程和 thinking 可以折叠展示，和现在的 activity group 一样。
4. 运行状态不落成「假 running」。进程死了，下次起来是 idle，除非转录里有待恢复的 wake / 未认领的执行结果。
5. 工具默认 `ask`。拒绝和始终允许要能记住。秘密文件即使 `always` 也不可读。
6. 压缩在调用模型的同一侧发生，Host 不另开一条模型客户端。

PoC 明确不做、只留缝的：账号、后端代理、云端电脑、多设备同步、跨用户 Room、Proactive 的自主行动、macOS 级 OS sandbox、任意 shell。这些在当前 Mac 应用里要么不存在，要么只是未接线的基础。
