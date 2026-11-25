# Nuum iOS 客户端架构

本文是 Phase 0 的设计，不包含应用代码，也不创建 Xcode 工程。它要让以后的 iOS 客户端复现 Mac 应用里已经存在、并且 Android PoC 已经落地的产品行为：多个 Nunu、记忆、一对一会话、Room、NunuBar、三家模型的流式工具循环、审批和设置。模型调用留在客户端，API key 配在应用里面。

不做账号、后端、云端电脑、多设备同步。这些只留接口，不留实现。Mac 应用今天也没有它们。

对照事实见 [NUUM_IOS_ANALYSIS.md](./NUUM_IOS_ANALYSIS.md)。后续包的切分见 [WORK_BREAKDOWN.md](./WORK_BREAKDOWN.md)。分析基线是 `main` @ `c91bb7206a14174b4384d09ce37d41a809eef94e`。

## 1. 决定

1. **用 Swift 重写可移植的核心，不把 Node / Electron 塞进 App。** Host、Kernel、协议和工具规则在 `packages/` 里是 TypeScript。`packages/executor/src/runner.ts` 在非 darwin 上拒绝执行，但 iOS 并不因此就该跑这条守护进程：它是 macOS 桌面的 seatbelt 路径，入口是 Node。iOS 用自己的 App Sandbox。
2. **保住 Mac 和 Android 已经写成代码的依赖方向。** UI 只依赖契约。Kernel 只认 `runId`，不认识 agent。Host 是唯一碰记忆、转录和审批的人，并且只通过 Kernel 碰模型。Mac 的规则在 `dependency-cruiser.cjs` 和 `packages/protocol/src/kernel-contract.ts`。Android 的对应物是 `android/build.gradle.kts` 的 `checkDependencyDirection`。
3. **单进程，多 Swift package。** Desktop 用 stdio 把 UI、Host、Kernel 拆成进程，是因为它们是独立的 Node 程序。iOS 上同样的边界用 package 的 import 表达。不另起进程，不起 Unix socket，不做 App Extension 来跑 turn。
4. **秘密只进 Keychain。** 不允许 Mac 那条「加密不可用就写明文」的退路。Android 把同一份 JSON 做成 Keystore 裹住的 `secrets.bin`（`KeystoreSecretStore`，alias `nuum.secrets`）。iOS 不复制那个文件：Keychain 自己就能存这一小段 JSON。加密或写入失败抛 `3001`，不在 Application Support、UserDefaults 或源码里落明文。
5. **任意 shell 和 macOS seatbelt 不进这个客户端。** 文件工具只碰应用容器里的托管目录，加上用户用 document picker 授权的目录。`grep` 用 Swift 实现，不 spawn `rg`。`shell`、`request_network`、`external_operation` 留在工具表里，执行返回固定的未实现句子。
6. **Proactive 只复现现在真正有的那一层。** 策略可以保存。界面照实说明行动没有接上。不在后台跑模型。`actionsAvailable` 保持 `false`。
7. **组合根手工 new，不用 DI 框架。** 不引入 Swinject、Factory，也不引入 Datadog、Sentry、Firebase 或任何金融 SDK。观测和支付不在这个客户端里。

## 2. 工具链

公开稳定版，核对日 2026-11-25。来源是 Apple 的 Xcode 27.2 发布记录（build `27B52`，2026-10-29）和 Swift.org 的 Swift 6.4.2 公告。这台机器是 Linux，没有 Xcode，下面的版本**没有**在本机执行 `xcodebuild -version`。脚手架包在 Mac 上复核；对不上就改这一节。不用 beta（核对日已有 Xcode 27.3 beta 2）。

| 组件 | 版本 | 理由 |
| --- | --- | --- |
| 语言 | Swift 6.4.2，Swift 6 语言模式 | 随 Xcode 27.2。打开完整并发检查。缺一个 `await` 就改代码，不关 Strict Concurrency |
| Xcode | 27.2（`27B52`） | 当前稳定版。Apple 写明需要 macOS Tahoe 26.6 或更新 |
| SDK | iOS 27.2 | 用这版 Xcode 自带的 SDK 编译 |
| 最低系统 | iOS 26.0 | 个人客户端。上一个大版本已经有 SwiftUI、Observation、Keychain 和 security-scoped bookmark。不为更老的系统加第二套存储 |
| UI | SwiftUI | 单窗口。UIKit 只出现在 SwiftUI 还没有的系统桥（例如必须时的 Quick Look 包装），并且只出现在 shell / conversation 的实现里 |
| HTTP | `URLSession` | SSE 自己读字节。不引入 LLM SDK，也不引入 Alamofire |
| 持久化 | 文件 + `Codable` | 真源是 JSON / JSONL，和 Mac、Android 同一套相对路径 |
| 列表 | 启动时从文件建的内存投影 | `MAX_AGENTS` 是 50。不用 SwiftData、Core Data 或第三方 SQLite 当第二真源。Android 的 Room 只是可重建投影；iOS 不把 Room 再移植一遍 |
| 非秘密偏好 | `UserDefaults` suite `nuum-ui` | 对应 Android 的 DataStore `nuum-ui`。不放 key |
| 秘密 | Keychain | 见第 7 节 |
| 测试 | Swift Testing；模拟器上的 XCTest | 纯 package 用 Swift Testing。Keychain 和界面测试要模拟器 |

版本锁在脚手架的工程设置里。功能包不改部署版本，也不往 package 里加第三方依赖。缺一个系统框架时，在 PR 里点名，由脚手架加。

## 3. 模块

```text
ios/
  Nuum.xcodeproj                 脚手架才创建。本 PR 没有它
  App/                           组合根、入口、签名和能力
  Packages/NuumContracts/
  Packages/NuumProtocol/
  Packages/NuumSecurity/
  Packages/NuumStorage/
  Packages/NuumModel/
  Packages/NuumKernel/
  Packages/NuumAgent/            Host
  Packages/NuumTools/
  Packages/NuumFeatureShell/
  Packages/NuumFeatureConversation/
  Packages/NuumFeatureWork/
  Packages/NuumFeatureSettings/
  Packages/NuumAcceptance/
```

仓库根继续是现有的 pnpm workspace。`ios/` 不写入 `pnpm-workspace.yaml`，也不改 Mac 包和 `android/`。根 `.gitignore` 的 `/docs/*` 会吞掉 `docs/ios/`，所以文档放在 `ios/docs/`。这和 `android/docs/` 是同一条原因。

和 Android Gradle 模块的对应：

| Android | iOS package | 职责 |
| --- | --- | --- |
| `:app` | `App` | 组合根、场景、能力 |
| `:core:contracts` | `NuumContracts` | 端口和最小类型。脚手架拥有，之后冻结 |
| `:core:protocol` | `NuumProtocol` | 纯数据与规则 |
| `:core:security` | `NuumSecurity` | Keychain |
| `:core:storage` | `NuumStorage` | 文件布局 |
| `:core:model` | `NuumModel` | 三家 HTTPS SSE |
| `:core:kernel` | `NuumKernel` | turn 循环。不读磁盘，不发 HTTP |
| `:core:agent` | `NuumAgent` | Host |
| `:core:tools` | `NuumTools` | 目录型文件工具 |
| `:feature:shell` | `NuumFeatureShell` | 导航、侧栏、创建、资料 |
| `:feature:conversation` | `NuumFeatureConversation` | 一对一 |
| `:feature:work` | `NuumFeatureWork` | Room / NunuBar |
| `:feature:settings` | `NuumFeatureSettings` | 设置和 Proactive 面板 |
| `:testing:acceptance` | `NuumAcceptance` | 场景 |

### 3.1 谁可以依赖谁

```text
Feature*     →  NuumContracts, NuumProtocol
NuumAgent    →  NuumContracts, NuumProtocol
NuumKernel   →  NuumContracts, NuumProtocol
NuumModel    →  NuumContracts, NuumProtocol
NuumTools    →  NuumContracts, NuumProtocol
NuumStorage  →  NuumContracts, NuumProtocol
NuumSecurity →  NuumContracts
NuumProtocol →  Foundation（Codable）。无 UIKit，无 SwiftUI，无 Security，无 URLSession
NuumContracts → NuumProtocol
App          →  全部实现 package
NuumAcceptance → App
```

禁止：

- Feature package import `NuumKernel`、`NuumAgent`、`NuumModel`、`NuumStorage` 的实现。界面拿到的是端口。
- `NuumKernel` import Host、UI、`URLSession`。模型通过 `ModelPort`。
- `NuumAgent` 自己发 HTTPS。压缩和 turn 都走 `KernelPort`。
- `NuumProtocol` 和 `NuumContracts` 出现 `UIKit`、`SwiftUI`、`Security`、`Network`。

脚手架用一条扫 `import` 的测试守住这张表，失败即这一包没完成。它对应 Android 的 `checkDependencyDirection`。

### 3.2 分层

| 层 | 模块 | 职责 |
| --- | --- | --- |
| UI | Feature packages，`App` 只做装配 | 状态展示、输入、导航。不写数据目录，不发网络 |
| 领域 | `NuumProtocol`，`NuumAgent`，`NuumKernel`，`NuumTools` | 转录、turn、记忆、审批、任务状态机 |
| 数据 | `NuumStorage`，`NuumSecurity`，`NuumModel` | JSONL、可重建的列表投影、UserDefaults、Keychain、SSE |

`NuumProtocol` 用 `Codable` 表达今天 Zod 和 `android/core/protocol` 里的类型，而不是另起一套字段名。校验失败要带上和现在一样可回给模型的英文句子。`SendMessage` 的 superRefine 口径在 `packages/protocol/src/product-tools.ts`，Android 已搬到 `android/core/protocol`。

领域规则继续是纯函数：`estimateModelTokens`、讨论限额、压缩切分、`resolveAvailableModel`、侧栏组织的唯一性、任务状态迁移。讨论限额三个数字（3 轮、10 条、每轮 2）今天在 `android/core/agent/src/main/kotlin/com/nuum/agent/Limits.kt`，不在 protocol。iOS 也放在 Agent 包。

## 4. 组合根

`App` 里一个 `AppGraph`，在启动时手工构造。没有 DI 容器。

```text
SecretStore  ← KeychainSecretStore
ModelPort    ← URLSessionModelPort(SecretStore)   // 只在发请求时读出 key
KernelPort   ← Kernel(ModelPort, ToolExecutor)
Store        ← 文件
Host         ← HostRuntime(Store, KernelPort, SecretStore, ToolBackend)
```

界面通过窄端口拿能力，而不是一个上帝对象。名字与 `android/core/contracts/src/main/kotlin/com/nuum/contracts/Ports.kt` 一致，这一份又对齐 `packages/protocol/src/host-contract.ts` 的 `HostMethods` 使用面：

- `SettingsPort`：`settings.get` / `settings.set` 的非秘密字段，外加 `hasOpenaiKey`、`hasAnthropicKey`、`hasDeepseekKey`。
- `SecretWriter`：只给设置页。写 key，不读回明文。输入框只留着用户刚打的字符。空字符串删除该 provider 的 key。
- `AgentPort`：list / get / create / update / delete / transcript / send / answerWidget / cancel / approve / deny。
- `WorkPort`：create / list / get / update / postMessage / member attach、detach、move / continue / stopDiscussion / task transcript / transition / dispatch / catalog add 与 remove。
- `ProactivePort`：get / configure / check。`actionsAvailable` 固定 `false`。
- `DesktopPort`：选目录、选文件、打开附件、分享。iOS 实现，不走 Host。

事件名与 `HostEvents` 一致（`android/core/contracts/.../HostEvent.kt`）：`agent.updated`、`agent.message.delta`、`agent.message.completed`、`agent.tool.pending`、`agent.tool.started`、`agent.tool.completed`、`agent.error`、`agent.ended`、`work.updated`、`work.event.appended`、`work.catalog.updated`、`proactive.updated`、`settings.updated`。没有独立 Kernel 进程，所以不发 `host.kernel.down`。模型失败走 `agent.error`，码用 `KernelErrorCode.MODEL`（1004）和 `HostErrorCode.NO_API_KEY`（2004）。

`AgentRuntime.status` 只从内存调度推导。进程被系统杀掉之后，下次冷启动不得显示 running。转录里未完成的 wake 和未写完的工具结果按 `packages/host/src/wake.ts`、`execution-recovery.ts` 的规则恢复。恢复的是「还有一件待办」，不是「磁盘上写着 running」。

## 5. 协议

数字码与 `packages/protocol/src/errors.ts`、`android/core/protocol/.../Errors.kt` 相同。不发明平行错误体系。1001 和 2005–2007 继续空着。`DesktopErrorCode.WINDOW`（3003）只保留数字，不移植桌面窗口方法。选文件夹失败用 `FOLDER_PICK`（3002）。秘密存储失败用 `SECRET_STORE`（3001）。

| 段 | 码 |
| --- | --- |
| Kernel | 1000 internal、1002 busy、1003 cancelled、1004 model、1005 tool、1006 sandbox、1007 invalid |
| Host | 2001 agent、2002 busy、2003 workspace、2004 api key、2008 kernel down、2009 data dir lock、2010 work、2011 conflict、2012 forbidden |
| Desktop | 3001 secret store、3002 folder pick、3003 window |

错误是 `NuumError(code, message)`，对应 Mac 的 `RpcError` 和 Android 的 `NuumException`。`message` 里不得出现 key。

JSON 字段名与现有文件一致，这样同一份 `transcript.jsonl` 在三边可读。时间用 `Int64` epoch millis，和 `createdAt` 一致。存储层不用 `Date` 换一套纪元。

Kernel 事件名保持 `turn.context`、`turn.delta`、`turn.tool.pending`、`turn.tool.started`、`turn.tool.delegate`、`turn.tool.completed`、`turn.error`、`turn.ended`。

## 6. 模型

`ModelPort.streamChat` 的 chunk 只有三种：`text`、`thinking`、`tool_call`。

三个实现，和 `packages/kernel/src/model/router.ts`、`android/core/model` 一致：

| provider | URL | 认证 | 备注 |
| --- | --- | --- | --- |
| openai | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer` | 图片用 `image_url` data URL |
| deepseek | `https://api.deepseek.com/v1/chat/completions` | Bearer | 不传图片，改成现有的省略说明句。thinking 读 `reasoning_content` |
| anthropic | `https://api.anthropic.com/v1/messages` | `x-api-key`，`anthropic-version: 2023-06-01` | system 抽到顶层。默认 `max_tokens` 4096 |

请求从现有的规范化请求现造，不经过一层通用 LLM SDK。SSE 放在 `NuumModel`，用 `URLSession` 按行读。取消绑定到调用方的 `Task`，对应现在的 `AbortSignal`。

默认模型（`android/core/protocol/.../Domain.kt` 的 `DEFAULT_MODEL_ID`）：openai `gpt-4o`，anthropic `claude-sonnet-4-20250514`，deepseek `deepseek-chat`。设置里 DeepSeek 还可以是 `deepseek-reasoner`。没有按会话换模型的控件。

Key 的选择顺序不变：选定的 provider 有 key 就用它，否则 `deepseek → openai → anthropic`，并退回该 provider 的 `DEFAULT_MODEL_ID`。空字符串不是 key。

轮中输出 token 上限保持 Kernel 的算法：有 `contextWindow` 时 `max(1, min(4096, floor(window * 0.1)))`。窗口表先照抄 128_000，包括未知模型和 `deepseek-reasoner`。不要猜一家的真实上下文长度。

网络：

- 使用系统默认 ATS。三个源都是 HTTPS。不添加 `NSAllowsArbitraryLoads`，也不为这三家加例外域。
- 不 pin 证书。三家的证书轮换不应该把客户端卡死。
- 日志不得包含 `Authorization`、`x-api-key` 或 key 的字符。release 不注册 body 日志。
- 超时：连接 20 秒，首字节之后读超时 60 秒，取消立即关流。这是 Android `ModelHttp` 里的工程默认。Mac 用的是平台 `fetch` 默认值。

图片字节只存在于当轮。写转录之前剥掉。DeepSeek 路径不把它们放进 JSON。MIME 只允许 jpeg / png / gif / webp。

## 7. API key

Android（`KeystoreSecretStore`，alias `nuum.secrets`）把 `{ openaiApiKey, anthropicApiKey, deepseekApiKey }` 加密后写到 `noBackupFilesDir/secrets.bin`，Keystore 要求用户认证是关闭的，因为每次发消息都要能读 key。Mac 的 Electron `safeStorage` 在加密不可用时会把同一文件写成 UTF-8 明文。iOS 跟 Android 的失败策略，不跟 Mac 的明文退路。

`KeychainSecretStore`（`NuumSecurity`）：

- 一条 Generic Password。`kSecAttrService` 为 `nuum.secrets`，和 Android 的 alias 同一字符串。`kSecAttrAccount` 为 `api-keys`。
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`。解锁后的进程能读，不弹生物识别，不进 iCloud Keychain，不随备份迁到另一台设备。不设置 `kSecAttrAccessControl` 的生物识别标志。
- `kSecAttrSynchronizable` 为 false。
- 值是 UTF-8 JSON，字段与 `SecretsCodec` 相同。空字段省略。没有这条 item 时 `read` 返回空的 `Secrets`，这不是错误。
- 不写 `secrets.bin`。Android 的文件是 EncryptedFile 的载体。iOS 的载体是 Keychain 这一条。
- 解密、解码或写入失败抛 `NuumError` 3001。句子用 Android 已经固定的两句，方便测试对照：`Couldn't read secrets because decryption failed.`、`Couldn't store secrets because encryption failed.`。不要把 `OSStatus`、JSON 或底层错误文本拼进 message。
- `description`、异常、转录、UserDefaults、os log、崩溃文本都不得出现 key 的字符。测试用假 key，并断言日志路径不含它。
- 数据目录排除备份（`isExcludedFromBackup`），与 Android `allowBackup=false` 对齐。Keychain 的 ThisDeviceOnly 再排除一次 key 本身。
- 进程内存里，Host 可以在一次 turn 期间持有解密后的 `Secrets`。这和现在把 `Secrets` 放进 `turn.start` 一样。不得把它放进长生命周期的日志或缓存文件。
- 设置页不提供「显示 key」。替换的方式是清空再输入。

`packages/host/src/runtime.ts` 的 `toolRoots` 把四个路径放进 denied：`secrets.bin`、`host-secrets.json`、`credentials.json`、`secrets.json`。`packages/sandbox/src/create-sandbox.test.ts` 锁住的是 `always` 也读不到 denied 路径。Android 的 `android/app/src/main/kotlin/com/nuum/graph/DeniedRoots.kt` 再把整个数据根放进 denied，然后只刻出当前 scratch、当前 project 和只读 knowledge。`noBackupFilesDir` 和 `secrets.bin` 标成 sealed，即使调用方把它们放进例外也刻不掉。转录、memory、`settings.json`、别的 agent 和工作区因此在跑起来的应用里不可读。iOS 的组合根做同样的刻法：Application Support 的 `nuum/` 先整棵拒绝，再刻出 scratch、bookmark 工作区和只读 knowledge；那四个文件名永不刻出。Keychain 不是文件，工具实现里不出现 Security 框架的读接口。

## 8. 本地存储

Mac 的真源是文件。Android 保持这个事实，Room 只做列表索引。iOS 同样以文件为真源。列表是内存投影，从 `profile.json` 和 work 的 `profile.json` 重建。不引入数据库。

应用数据根：Application Support 下的 `nuum/`。不用 Documents，不开 `UIFileSharingEnabled`，这样转录不会出现在「文件」App 里。秘密不在这棵树里。

相对路径跟 `android/core/contracts/.../Paths.kt` 的 `NuumPaths`，以及 `android/core/storage/.../StoragePaths.kt` 里多出来的会话路径：

| 位置 | 内容 |
| --- | --- |
| `settings.json` | 非秘密全局设置。不含 key |
| `migrations.json` | `MIGRATION_VERSION = 3` |
| `agents/<id>/profile.json` | 身份。Host 是唯一写者 |
| `agents/<id>/settings.json` | 模型、执行偏好、proactive、workMembership、bookmark |
| `agents/<id>/transcript.jsonl` | append-only。坏掉的最后一行只丢这一行 |
| `agents/<id>/read-cursor.json` | 已读 |
| `agents/<id>/tool-approvals.json` | 记住的允许和拒绝 |
| `agents/<id>/prompt-cache.json` | 冻结的 prompt 前缀 |
| `agents/<id>/memory/*.md` | 记忆真源。profile 100 条，召回 4_000 字符，半衰期 30 天 |
| `agents/<id>/scratch/` | 工具草稿 |
| `works/<id>/` | profile、catalog、timeline.jsonl |
| `work-sessions/<sha256(workId)>/<sha256(...)>/` | `session.json` 与 `transcript.jsonl`。哈希输入与 `StoragePaths.cardSessionPayload` 相同，也就是 Node `JSON.stringify([workId, taskId, agentId, membershipRevision])` |
| `workspaces/<sha256>.json` | 工作区记录。id 是 owner 的 sha256 |
| `workspaces/<id>/` | 托管项目根 |
| UserDefaults `nuum-ui` | 侧栏宽度一类的 UI 偏好、身份模板是否编辑过 |

文件保护用 `completeUntilFirstUserAuthentication`，和 Keychain 那条 item 的可用窗口一致。写入沿用 Mac 的原子替换：临时文件再换名。JSONL 只追加。投影和文件不一致时，以下一次文件扫描为准。

工作区：

- 每个 Nunu 默认一个容器内目录 `nuum/workspaces/<id>/`，相当于 Mac 上 `Documents/Nuum/...` 里那份托管目录。
- 用户点「选择文件夹」时走 SwiftUI `fileImporter`，把 security-scoped bookmark 存在该 agent 的 settings 里。使用前 `startAccessingSecurityScopedResource()`。这棵树是 `project`。
- 没有托管目录、也没有 bookmark 时，写项目文件返回 `HostErrorCode.NO_WORKSPACE`（2003）。

附件写到当前工作区下的 `.nuum-attachments/`。限额不变：5 个、单个 10 MiB、合计 20 MiB。容器内文件是应用私有的；落在 bookmark 目录时，边界是用户授权的那棵树。

单实例锁不再用 `host.lock` 的 pid 文件。一个进程里的 `HostRuntime` 就是唯一写者。

不使用 iCloud 容器，不设 App Group。以后若要做扩展，扩展不得拿到这把 Keychain。

## 9. 工具

权限动作仍是 `read-file | list-directory | write-file | run-command | network`。默认档是 `ask`。

工具包里的判定顺序移植 `packages/sandbox/src/create-sandbox.ts`，Android 的对照测试是 `android/core/tools/src/test/kotlin/com/nuum/tools/PathPolicyTest.kt`：denied 拒绝，`always` 不能覆盖；readOnly 可读不可写；必须落在 home 或 scratch 之下；scratch 和 project 预批准；`agents/` 在没有被 denied 盖住时可读不可写，改记忆走 `update_state`；其余走 `always | ask | never`。组合根再加上一段 `DeniedRoots.kt` 的刻法，见第 7 节。刻完之后，转录和 memory 在运行时落在 denied 里，工具包那条「可读」不会被走到。

| 工具 | 本期 |
| --- | --- |
| `read` `write` `str_replace` `multi_str_replace` `delete` `ls` `glob` | 对托管目录和 bookmark 树实现。读上限 30_000，diff 上限 12_000，树上限 20_000，glob 500 |
| `grep` | Swift 递归扫描，输出上限 500_000。不调用外部程序 |
| `shell` `request_network` `external_operation` | 注册进表。执行返回 `This iOS client does not implement this tool.` 不 spawn 进程 |
| `RunWorkCLI` | 返回 `This version of Nuum has no local executable. RunWorkCLI is not implemented.` |
| 其余委派工具 | Host 实现。只注册有 handler 的定义 |

命令黑名单（`rm -rf /`、`mkfs`、`dd if=`、fork bomb）没有调用点。规则文本仍放在 protocol 测试里。

没有 bookmark、路径又在允许根之外时，按「路径在允许根之外」拒绝。

## 10. Agent loop

控制流移植 `packages/kernel/src/loop.ts`，Android 的实现在 `android/core/kernel/.../Kernel.kt`。

- `MAX_ROUNDS = 16`。用尽后发出 `Stopped after 16 tool rounds without a final answer.`，然后 `turn.ended` status `idle`。
- 没有 tool call 就 `turn.ended` status `idle`。
- 取消是 `TurnCancelled`：`turn.ended` status `cancelled`，不发 `turn.error`。
- 用户看不见模型的自由文本和工具输出。只有发声工具到达用户。direct run 默认 `SendMessage`。静默提醒的英文句子、阈值（ack 超过 1、result 超过 0、silence 超过 6）和「每种每段一次、不写转录」保持原样。
- 委派工具发 `turn.tool.delegate`，然后等 Host `turn.provideToolResult`。定义必须带完整 schema。
- 本机工具先 `authorize`。`ask` 发 `turn.tool.pending`，等 `always | once | deny | never`。通过后 `turn.tool.started`，再执行。
- 压缩后若仍超过 `contextWindow * 0.9`，失败句子保持 `Context capacity exhausted; execution paused without replaying tools.`
- 调用模型之前，估算超过窗口的 0.75 就先压缩。压完仍超过 0.75 就拒绝这次输入，不重放工具。
- Host 收到 `turn.context` 必须回答，否则 Kernel 会一直等。Android 验收记录（`android/docs/acceptance/SCENARIOS.md`）写明：当前回答不替换消息，轮中的 0.80 / 0.85 压缩没有移植。iOS 跟这份已经落地的行为。Mac 的 `packages/host/src/runtime.ts` 仍会在约 0.80 处准备、约 0.85 处替换。那是以后可以在同一次 `provideContext` 里补上的差异，不是另一套协议。
- `summarize.run` 仍是 Host 碰模型的唯一合法路径，而且经由 Kernel。

调度：全局最多 3 个 run，每个 agent 同时一个，嵌套的 `projectRoot` 不重叠。

唤醒：`MAX_HOPS = 3`，每分钟 3 次，每个 run 最多新建 1 个 agent，全局 50。队列只在内存。重启后从转录恢复尚未完成的 wake。

Room：`discussionLimits = { rounds: 3, messages: 10, perTurn: 2 }`。NunuBar 的任务状态、角色、目录 kind 与 `packages/protocol/src/work.ts` 相同。knowledge 固定只读。

系统提示词里「跑在用户自己的 Mac 上」「real shell」改成当前设备的事实，放在不参与冻结前缀的环境段：`This is a local iOS app. You can read files in directories the user authorized. You cannot run a shell.` OS 一行由 `App` 注入（例如 `iOS 26.2`），Agent 包不 import UIKit。其余段落保留。这和 `android/core/agent/.../Prompt.kt` 的做法相同，只是把 Android 那句换成 iOS。

## 11. 后台

Turn 是前台 `Task`，跟进程走。不声明 `UIBackgroundModes`。不用 `BGAppRefreshTask`、`BGProcessingTask`，也不用 background `URLSession` 跑模型。

系统杀掉进程时：已追加的转录留下；内存里的 `running` 消失；下次启动按转录恢复未完成的 wake，并认领已经写完、还没补进转录的工具结果。不自动重放一个执行到一半的 `write`。文件写入要在返回工具结果之前完成，做不到就向模型返回失败。

iOS 会先挂起再可能被 jetsam。挂起不是继续跑模型的机会。场景进入后台时不新开模型请求。进程若只是挂起后恢复，内存里的 turn 可能还在；这不改变「status 不落盘」的规则。

`TurnSupervisor` 留在契约里。本期实现是 `InProcessTurnSupervisor`。以后若要离开界面仍继续，换一个实现，不把后台策略写进 Host。iOS 没有 Android 那种可长期运行的前台服务，不要假装有。

Proactive 的 1 秒 tick 不搬。打开面板时现算 snapshot。`intervalMs`、`pausedUntil`、`sourceIds` 照常持久化。不注册任何 `ProactiveSource`。没有 source 时 `check` 记下 `waiting-context`。

## 12. 界面

设计语言跟现有 sand token（`packages/ui/src/theme/runtime-theme-token-installer.ts`）和 `packages/ui/src/i18n/messages.ts`。不另起一套产品名词，也不把界面改成一套与 Nunu 无关的系统分组列表。Android 的屏幕规格在 `android/docs/design/`。iOS 的交互与那些规格和 Mac 行为一致；尺寸用水平 size class，而不是把 1200×800 缩小。

产品里的 widget 是转录里的卡片，最多 6 个选项。它不是 WidgetKit。本期不加主屏幕小组件、Live Activity、App Intent。

### 12.1 Shell

单 `WindowGroup`。compact 宽度用侧栏列，regular 宽度用分栏。侧栏搜索、置顶、分组、创建 Nunu、2D 开箱、资料页身份。创建时用户只选颜色，形状和材质用与 `rollAgentAvatar` 相同的纯函数掷一次并写入 profile。`accessibilityReduceMotion` 为真时开箱直接到终态。不引入 3D 引擎，不打包 `packages/ui/src/assets/nunu/` 的 9.4 MB 原图。

### 12.2 Conversation

一对一转录、输入、停止、附件、审批条、widget、peer 抽屉、工具活动分组（规则同 `packages/ui/src/conversation/activity-groups.ts`）。附件选择走 `DesktopPort`。审批三条是拒绝、允许一次、始终允许。`never` 不出现在这条 UI 上。pending 带 `workId` 时，这一屏不画审批条。

### 12.3 Work

Room 和 NunuBar：创建、升级、共享聊天、@、停止和继续、成员、泳道、交付物、派发、状态迁移、目录的本地导入，以及禁用的发现页。不提供用户建卡按钮。建卡路径是模型的 `CreateTask`。每个成员自己的审批条放在这里。

### 12.4 Settings

两页：语言（`zh-CN` / `en`）、主题（`light | dark | system`）、打开 Proactive 面板；默认 provider、DeepSeek 的两个模型、三把 key 的写入。key 输入框不从存储回填。Proactive 显示行动未连接，文案与 Mac 一致。`defaultToolPermission` 协议保留，设置页不放入口。

全局默认语言和主题的字段与 `Settings` 相同。字符串进 String Catalog 的 `en` 和 `zh-CN`。缺省文案以 `messages.ts` 为准。

## 13. 范围内与范围外

「范围内」指这个客户端要能在模拟器上演示。「范围外」指这一期不实现，但第 14 节的接口不堵死。与 Android 架构第 9 节同一张产品边界：多 Nunu、一对一、附件限额、审批、Room、NunuBar、文件工具、压缩、调度和 wake 限额在范围内；删除 Nunu 的界面、会话内换模型、用户手工建卡、能力商店、`shell`、OS sandbox、Proactive 的采集和行动、账号、后端、同步在范围外。`TODO.md` 的三项（CheckAgent 卡片、秘密输入卡、widget 自动收起）不做。

iOS 额外明确不做：WidgetKit、Live Activity、iCloud 同步、App Group、推送、第三方观测 SDK、金融 SDK、把 executor 打进 App。

## 14. 威胁模型

要保护的东西：三把 API key、转录、记忆、工作区文件、已经记住的工具授权。

| 威胁 | 处理 |
| --- | --- |
| 备份或换机把 key 带走 | Keychain `ThisDeviceOnly` 且不同步。数据目录 `isExcludedFromBackup` |
| 日志或崩溃文本看到 key | 不把 key 传给 logger。异常句子是固定的。release 无 body 日志 |
| 模型通过 `read` 把秘密文件读出来 | denied 根。单测覆盖 `always`。工具代码不调用 Keychain |
| 模型诱导写工作区之外的路径 | 路径必须落在托管目录、bookmark 树或该 agent 的 scratch。memory 对工具只读 |
| 恶意附件 | 数量和大小限额。不执行附件。图片只按白名单 MIME 解码 |
| 另一应用读 Nuum 的文件 | 转录在容器内。bookmark 树的边界是用户授权，要在文档和界面上说清楚 |
| 提示注入把工具结果当成指令 | 保留现有压缩提示里「证据当引用」的句子。这不是沙箱 |
| 越狱或解锁后的物理接触 | 不在对抗范围内。Keychain 挡不住持有解锁设备的人 |
| 把 key 送到自建后端 | 没有后端。`ModelPort` 只允许第 6 节三个写死的 HTTPS 源。设置里不能填任意 base URL |
| 观测或支付 SDK 把转录送出去 | 不引入这些 SDK |

可以记录的东西：provider 名、模型名、HTTP 状态码、工具名、字节数、runId。

## 15. 以后的缝

全部放在 `NuumContracts`。本期只提供下面这些默认实现，调用点集中在 `AppGraph`。

| 接口 | 本期 | 以后 |
| --- | --- | --- |
| `ModelPort` | 三个直连客户端 | 账号体系出现后可以换成走后端的实现。Host 和 UI 不改 |
| `SecretStore` | Keychain 一条 item | 账号绑定的密钥。本地实现保留给离线 |
| `IdentityContext` | `LocalOnly`，没有 userId | `AccountSession`。转录不提前加 user 字段 |
| `SyncPort` | `NoSync`，方法是空操作 | 多设备。同步单位是 agent 目录和 work 时间线，不是列表投影 |
| `TurnSupervisor` | 进程内 | 另一个实现。不把后台模式写进 Host |
| `ToolBackend` | 目录型文件工具；shell / network 返回未实现 | 若要做执行隔离，单独的实现，不把 seatbelt 写进 Kernel |
| `ProactiveSource` | 无注册 | 采集。有真正的行动执行器之前 `actionsAvailable` 保持 `false` |
| `Clock` | 系统时钟 | 测试注入 |

不要为这些缝加数据库列、登录按钮或「云端执行」开关。空实现如果需要被 UI 观察到，就什么都不显示。

## 16. 测试与编码

| 层 | 放哪 | 覆盖 |
| --- | --- | --- |
| Swift Testing | `NuumProtocol`、`NuumKernel`、`NuumAgent` 的纯函数 | token 估算、16 轮停止、提醒阈值、压缩切分、记忆去重和 100 条上限、讨论 3×10、调度上限、wake 限额、SendMessage 错误文案、DeepSeek 丢图、Anthropic system 抽离。模型用假的 `ModelPort`，不联网 |
| 文件 | `NuumStorage` | 原子写中途失败不损坏旧文件；JSONL 尾行截断只丢该行；`settings.json` 往返不含 key 字段 |
| Keychain | `NuumSecurity` 的模拟器测试 | 写入后容器里没有 `secrets.bin`；读回相等；异常 message 不含测试 key。不要在没有 Keychain 的环境里用桩冒充通过 |
| 界面 | Feature 的 XCTest | 空会话、审批三个按钮、widget、设置页不回显 key、NunuBar 没有手工建卡 |
| 架构 | 扫 import 的测试 | 第 3.1 节 |
| 回归 | 不改 Mac 包，不改 `android/` | 现有 Android workflow 只在 `android/**` 下触发 |

不在 CI 和源码里放真的 API key，也不打真的 provider。

编码：

- 标识符英语：`Nunu`、`Room`、`NunuBar`、`runId`、`SendMessage` 不翻译。
- 领域注释可以用中文。公开 API 不写无信息量的注释。
- 调用方传入生命周期。不用无主的全局任务去跑 turn。
- Feature 不直接用 `FileManager` 指向数据目录。
- 不格式化、不移动 `apps/`、`packages/`、`android/` 下的任何文件。

## 17. 构建环境

本文写在 Linux 云代理上，工作区没有 `xcodebuild`，也没有 iOS 模拟器。第 2 节的版本是公开稳定版，不是本机探测。

脚手架以及一切模拟器、真机、Keychain 往返、签名和 `xcodebuild`，都要等一台装有 Xcode 27.2 的 Mac。在那台机器上记录 `xcodebuild -version` 和 `swift --version`。GitHub 的 macOS runner 不假定已经带这版 Xcode；在确认之前，不把 iOS job 设成会挡住 desktop 或 Android PR 的必需检查。iOS workflow 若要加，路径过滤只覆盖 `ios/**` 和它自己的 workflow 文件，并且不去改 `.github/workflows/android.yml`。

本 PR 只增加 `ios/docs/` 下的三份文档。
