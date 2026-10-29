# Nuum Android PoC 架构

本文是 Phase 0 的设计，不包含应用代码。它要让后续 PoC 在 Android 模拟器上复现当前 Mac 应用里已经存在的产品行为：多个 Nunu、记忆、一对一会话、Room、NunuBar、三家模型的流式工具循环、审批和设置。模型调用留在客户端，API key 配在应用里面。

不做账号、后端、云端电脑、多设备同步。这些只留接口，不留实现。Mac 应用今天也没有它们。

对照事实见 [NUUM_MACOS_ANALYSIS.md](./NUUM_MACOS_ANALYSIS.md)。分析基线是 `main` @ `9e4a3ad`。

## 1. 决定

1. **用 Kotlin 重写可移植的核心，不把 Node / Electron 塞进 APK。** Host、Kernel、协议和工具规则是 TypeScript，但执行守护进程在非 darwin 上直接拒绝（`packages/executor/src/runner.ts`）。嵌入 Node 既过不了这道门，也违反低开销。
2. **保住 Mac 侧的依赖方向。** UI 只依赖契约。Kernel 只认 `runId`，不认识 agent。Host 是唯一碰记忆、转录和审批的人，并且只通过 Kernel 碰模型。这是 `dependency-cruiser.cjs` 和 `kernel-contract.ts` 已经写明的不变量。
3. **单进程，多模块。** Desktop 用 stdio 把 UI、Host、Kernel 拆成进程，是因为它们是独立的 Node 程序。Android 上同样的边界用类型和 Gradle 模块表达。PoC 不另起 `:kernel` 进程，也不起 Unix socket 守护进程。
4. **秘密只进 Android Keystore 支持的密文。** 不允许 Mac 那条「加密不可用就写明文」的退路。
5. **任意 shell 和 macOS seatbelt 不进 PoC。** 文件工具改成应用私有目录加用户授权的目录树。`grep` 用 Kotlin 实现，不 spawn `rg`。
6. **Proactive 只复现现在真正有的那一层。** 策略可以保存，界面照实说明行动没有接上。不在后台跑模型。
7. **依赖注入用构造函数和一个组合根，不用 Hilt。** Room 需要的 KSP 留在 `:core:storage`。其余模块不跑注解处理。

## 2. 工具链

数字核对于 2026-10-29。稳定通道，不用 preview。

| 组件 | 版本 | 理由 |
| --- | --- | --- |
| 语言 | Kotlin `2.4.21` | Maven Central 上当前稳定版。`2.5.0-Beta2` 不用。AGP 9 起自带 Kotlin，应用模块不要再 apply `org.jetbrains.kotlin.android`，否则构建直接失败。要高于 AGP 运行时自带的 KGP 时，在根工程 `buildscript.dependencies` 里放 `org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.21` 和 `com.google.devtools.ksp:symbol-processing-gradle-plugin:2.3.12` |
| JDK | 21 | AGP 9.5 最低 17。这台环境已有 OpenJDK 21.0.12，toolchain 锁 21 |
| AGP | `9.5.0` | 2026-10-28 稳定版。最高支持 API 37。要求 Gradle `9.6.0` |
| Gradle | `9.6.0` | AGP 9.5 的最低也是默认版本 |
| Compose BOM | `2026.09.00` | 官方文档给出的当前 BOM。对应 Compose `1.12.1`、Material3 `1.4.0` |
| compileSdk | 37 | Compose 1.12 起要求 compileSdk 37 和 AGP 9。SDK 包名是 `platforms;android-37.0`，不是 `platforms;android-37` |
| targetSdk | 36 | 本环境能装上并准备运行的系统镜像是 `android-36`。36 是已发布平台行为；37 只用于编译，避免 PoC 提前吃进尚未在这台镜像上验证的运行时变化 |
| minSdk | 28 | 个人 PoC，不追更老的存储模型。API 28 起默认禁止明文流量，通知渠道和 Keystore AES-GCM 都可用。AndroidX Security Crypto `1.1.0` 可在此基线上使用 |
| KSP | `2.3.12` | 只给 Room 用。2.3.10 起修复了 Kotlin 2.4 的模块名问题 |
| Room | `2.8.5` | 当前稳定 |
| DataStore | `1.3.0` | 当前稳定。只放非秘密偏好 |
| security-crypto | `1.1.0` | Keystore 封装。秘密文件不走 DataStore |
| OkHttp | `5.5.1` | SSE 要自己拿 `ResponseBody.source()`，不用 Retrofit |
| coroutines | `1.11.0` | 当前稳定 |
| lifecycle | `2.11.0` | 与 navigation 对齐 |
| navigation-compose | `2.10.2` | 单 Activity |
| Robolectric | `4.17` | JVM 上的 Android 单元测试 |
| Compose 编译器 | 随 Kotlin 2.4.21 的 Compose Compiler Gradle plugin | Kotlin 2.0 起不再单独对表 |

NDK 不引入。没有需要 JNI 的路径。

版本全部进 `gradle/libs.versions.toml`，由脚手架包独占。其他包只引用 catalog 别名，不在自己的 `build.gradle.kts` 里写死版本。

## 3. Gradle 模块

```text
android/
  settings.gradle.kts
  build.gradle.kts
  gradle/libs.versions.toml
  app/                         :app          组合根、Manifest、导航宿主
  core/contracts/              :core:contracts   接口。脚手架拥有，之后冻结
  core/protocol/               :core:protocol    纯 JVM 数据与规则
  core/security/               :core:security
  core/storage/                :core:storage
  core/model/                  :core:model
  core/kernel/                 :core:kernel
  core/agent/                  :core:agent       Host
  core/tools/                  :core:tools
  feature/shell/               :feature:shell
  feature/conversation/        :feature:conversation
  feature/work/                :feature:work
  feature/settings/            :feature:settings 含 Proactive 面板
  testing/acceptance/          :testing:acceptance
```

仓库根继续是现有的 pnpm workspace。Android 工程是根下的 `android/`，不参与 `pnpm-workspace.yaml`，也不改 Mac 包。根 `.gitignore` 的 `/docs/*` 会吞掉 `docs/android/`，所以文档放在 `android/docs/`。

### 3.1 谁可以依赖谁

```text
:feature:*  →  :core:contracts, :core:protocol
:core:agent →  :core:contracts, :core:protocol
:core:kernel → :core:contracts, :core:protocol
:core:model →  :core:contracts, :core:protocol
:core:tools →  :core:contracts, :core:protocol
:core:storage → :core:contracts, :core:protocol
:core:security → :core:contracts
:core:protocol → （无 Android，无 OkHttp，无 Compose）
:core:contracts → :core:protocol
:app → 全部实现模块
:testing:acceptance → :app
```

禁止：

- `:feature:*` 依赖 `:core:kernel`、`:core:agent`、`:core:model`、`:core:storage` 的实现。界面拿到的是 `HostPort`。
- `:core:kernel` 依赖 Host、UI、OkHttp 的具体类。模型通过 `ModelPort`。
- `:core:agent` 自己发 HTTPS。压缩和 turn 都走 `KernelPort`。
- `:core:protocol` 出现 `android.*` import。它要能在 JVM 测试里直接跑。

这是 Mac 上 dependency-cruiser 四条规则的对应物。脚手架在 CI 里用一条 Gradle 检查（或 ArchUnit / 自定义 task 扫 import）守住它。

### 3.2 分层

| 层 | 模块 | 职责 |
| --- | --- | --- |
| UI | `:feature:*`，`:app` 只做装配 | 状态展示、输入、导航。不写文件，不发网络 |
| 领域 | `:core:protocol`，`:core:agent`，`:core:kernel`，`:core:tools` | 转录、turn、记忆、审批、任务状态机 |
| 数据 | `:core:storage`，`:core:security`，`:core:model` | JSONL、Room 索引、DataStore、Keystore、SSE |

`:core:protocol` 用 `kotlinx.serialization` 表达今天 Zod 里的类型，而不是把 Zod 再实现一遍。校验失败要带上和现在一样可回给模型的句子：缺字段时说明什么没发出去、该怎么重发（`product-tools.ts` 里 SendMessage 的 superRefine 就是这个口径）。

领域规则继续是纯函数，方便把现有 node:test 的断言搬成 JUnit：`estimateModelTokens`、`discussionLimits`、`partitionForCompaction`、`resolveAvailableModel`、侧栏组织的唯一性、任务状态迁移。

## 4. 组合根

`:app` 里一个 `AppGraph`，在 `Application.onCreate` 手工 new 出来。没有 Hilt，没有 Koin。

```text
SecretStore  ← KeystoreSecretStore
ModelPort    ← OkHttpModelPort(SecretStore)     // 只在发请求时解密
KernelPort   ← Kernel(ModelPort, ToolRegistry)
Store        ← Room + 文件
HostPort     ← HostRuntime(Store, KernelPort, SecretStore, ToolBackend)
```

界面通过构造参数拿到窄接口，而不是一个上帝 `HostPort`。建议在 `:core:contracts` 里按 Mac 的 `HostMethods` 使用面切开：

- `SettingsPort`：`settings.get` / `settings.set` 的非秘密字段，外加 `hasOpenaiKey` 三个布尔。
- `SecretWriter`：只给设置页。写 key，不读回明文。设置页的输入框自己留着用户刚打的字符，不从存储里再解密出来显示。这比 Mac 的 `getSecrets` 更严，也够用。
- `AgentPort`：list / get / create / update / transcript / send / answerWidget / cancel / approve / deny。
- `WorkPort`：create / list / get / update / postMessage / member attach 与 detach / continue / stopDiscussion / task transition / task transcript / dispatch / catalog add 与 remove。
- `ProactivePort`：get / configure / check。`actionsAvailable` 固定 `false`。
- `DesktopPort`：选目录、打开附件、分享。Android 实现，不走 Host。

事件用 `Flow<HostEvent>`，方法名与 `HostEvents` 对齐：`agent.updated`、`agent.message.delta`、`agent.message.completed`、`agent.tool.pending`、`agent.tool.started`、`agent.tool.completed`、`agent.error`、`agent.ended`、`work.updated`、`work.event.appended`、`work.catalog.updated`、`proactive.updated`、`settings.updated`。没有独立 Kernel 进程，所以不发 `host.kernel.down`。模型失败走 `agent.error`，码用现有的 `KernelErrorCode.MODEL`（1004）和 `HostErrorCode.NO_API_KEY`（2004）。

`AgentRuntime.status` 仍然只从内存调度推导。进程被系统杀掉之后，下次冷启动不得显示 running。转录里未完成的 wake 和未写完的工具结果按 `wake.ts`、`execution-recovery.ts` 的规则恢复；恢复的是「还有一件待办」，不是「磁盘上写着 running」。

## 5. 模型流式

`ModelPort.streamChat` 返回 `Flow<NormalizedChunk>`，chunk 只有今天这三种：`text`、`thinking`、`tool_call`。

三个实现，和 `router.ts` 一致：

| provider | URL | 认证 | 备注 |
| --- | --- | --- | --- |
| openai | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer` | 图片用 `image_url` data URL |
| deepseek | `https://api.deepseek.com/v1/chat/completions` | Bearer | 不传图片，改成现有的省略说明句。thinking 读 `reasoning_content` |
| anthropic | `https://api.anthropic.com/v1/messages` | `x-api-key`，`anthropic-version: 2023-06-01` | system 抽到顶层。默认 `max_tokens` 4096 |

请求从 `NormalizedChatRequest` 现造，不经过一层「通用 LLM SDK」。SSE 解析放在 `:core:model`，用 OkHttp 的 `BufferedSource` 按行读，取消绑定到 `Coroutine` 的 `Job`，对应现在的 `AbortSignal`。

轮中输出 token 上限保持 Kernel 的算法：有 `contextWindow` 时 `max(1, min(4096, floor(window * 0.1)))`。窗口表先照抄 128_000，包括未知模型和 `deepseek-reasoner`。不要在 PoC 里猜一家的真实上下文长度。

Key 的选择顺序不变：选定的 provider 有 key 就用它，否则 `deepseek → openai → anthropic`，并退回 `DEFAULT_MODEL_ID`。

网络配置：

- `network_security_config` 禁止 cleartext。
- 不 pin 证书。三家的证书轮换不应该把 PoC 卡死。
- 日志拦截器默认关闭 body。打开 debug 日志时也要剥掉 `Authorization` 和 `x-api-key`。release 不注册这个拦截器。
- 超时：连接 20 秒，首字节之后靠读超时 60 秒，取消立即关流。这些是 PoC 的工程默认，Mac 侧用的是平台 `fetch` 默认值，没有更细的数字。

图片字节只存在于当轮 `ModelImage`。写转录之前剥掉。DeepSeek 路径不把它们放进 JSON。

## 6. 本地存储

Mac 的真源是文件，不是数据库。Android 保持这个事实，Room 只做列表需要的索引。

应用私有根：`context.filesDir/nuum/`。秘密不在这里。

| 位置 | 内容 | 对应 Mac |
| --- | --- | --- |
| `filesDir/nuum/settings.json` | 非秘密全局设置 | `dataDir/settings.json` |
| `filesDir/nuum/agents/<id>/profile.json` | 身份 | 同名 |
| `filesDir/nuum/agents/<id>/settings.json` | 模型、执行偏好、proactive、workMembership | 同名 |
| `filesDir/nuum/agents/<id>/transcript.jsonl` | append-only | 同名。坏掉的最后一行只丢这一行 |
| `filesDir/nuum/agents/<id>/read-cursor.json` | 已读 | 同名 |
| `filesDir/nuum/agents/<id>/tool-approvals.json` | 记住的允许和拒绝 | 同名 |
| `filesDir/nuum/agents/<id>/prompt-cache.json` | 冻结的 prompt 前缀 | 同名 |
| `filesDir/nuum/agents/<id>/memory/*.md` | 记忆真源 | `MemoryStore` 的 profile.md 和 `log/YYYY-MM.md` |
| `filesDir/nuum/agents/<id>/scratch/` | 工具草稿 | scratch |
| `filesDir/nuum/works/<id>/` | profile、catalog、timeline.jsonl | 同结构 |
| `filesDir/nuum/work-sessions/...` | 卡片 session.json + transcript.jsonl | sha256 路径规则照抄 |
| `filesDir/nuum/workspaces/*.json` | 工作区记录 | 同名 |
| DataStore `nuum-ui` | 侧栏宽度、身份模板是否编辑过 | 今天的 localStorage |
| Room | agent 列表、work 列表、任务行、侧栏分组的查询投影 | Mac 没有。投影可以从文件重建 |

Room 不是第二真源。启动时如果投影缺失或 `migrations.json` 版本变了，从文件重建。写入顺序：先追加 JSONL 或原子替换 JSON，成功后再更新 Room。进程死在这两步之间时，以下一次文件扫描为准。

记忆继续是 Markdown，上限仍是 profile 100 条、召回 4_000 字符、半衰期 30 天。模型用 `read` 读的是这些文件，而不是一张记忆表。

附件写到当前工作区下的 `.nuum-attachments/`，模式等价于 `0o600`（应用私有时本来就不可被别的 app 读；落在 SAF 目录时只能依赖用户选中的那棵树的权限）。限额不变：5 个、单个 10 MiB、合计 20 MiB。

工作区根：

- 每个 Nunu 默认一个应用私有目录 `filesDir/nuum/workspaces/<id>/`，相当于 Mac 上 `Documents/Nuum/...` 里那份托管目录。
- 用户点「选择文件夹」时走 Storage Access Framework，`takePersistableUriPermission`。URI 存在该 agent 的 settings 里。文件工具把这棵树当作 `project`。
- 没有托管目录、也没有 SAF 授权时，写项目文件返回 `HostErrorCode.NO_WORKSPACE`（2003），和 Mac 的缺工作区一致。

单实例锁不再用 `host.lock` 的 pid 文件。一个进程里的 `HostRuntime` 就是唯一写者。

## 7. API key

`KeystoreSecretStore`（`:core:security`）：

- Master key：Android Keystore 里的 AES-256-GCM，alias `nuum.secrets`。`setUserAuthenticationRequired(false)`。PoC 没有登录，每次发消息都要能读 key，不能绑生物识别，否则模型调用会被系统弹窗打断。
- 密文文件：`context.noBackupFilesDir/secrets.bin`。用 AndroidX Security `EncryptedFile`。布局可以仍是 `{ openaiApiKey, anthropicApiKey, deepseekApiKey }` 的 JSON，和 `Secrets` 相同。
- 加密不可用就失败，错误码 `DesktopErrorCode.SECRET_STORE`（3001）。不写明文。
- `toString()`、异常 message、转录、Room、DataStore、备份、logcat 都不得出现 key 的字符。测试里用假 key，并断言 log 拦截器的输出不含它。
- Manifest：`android:allowBackup="false"`。同时提供 `dataExtractionRules` 和 `fullBackupContent`，把 `noBackup` 和任何名为 `secrets.bin` 的文件排除。这样以后有人把 `allowBackup` 打开，key 仍然不进云备份和设备迁移。
- 进程内存里，Host 可以在一次 turn 期间持有解密后的 `Secrets`，这和现在把 `Secrets` 放进 `turn.start` 一样。turn 结束不要求把字符串从堆里擦掉（JVM 做不到可靠擦除），但不得把它放进长生命周期的日志或缓存文件。
- 设置页不提供「显示 key」。Mac 会把明文填回输入框，那是 Electron preload 的能力，PoC 不复制。替换 key 的方式是清空再输入。空字符串表示删除该 provider 的 key。

工具的 denied 名单要包含 `noBackupFilesDir` 和整个 `filesDir/nuum` 里除了该 agent `scratch/`、授权工作区、只读 knowledge 根以外的路径。`secrets.bin` 即使权限是 `always` 也不可读。这是 `create-sandbox.test.ts` 已经锁住的行为。

## 8. 后台

PoC 的 turn 是前台协程，跟进程走。不建前台服务，不用 WorkManager 跑模型。

系统杀掉进程时：

- 已追加的转录留下。
- 内存里的 `running` 消失。
- 下次启动按转录恢复未完成的 wake，并按 `execution-recovery` 认领已经写完、还没补进转录的工具结果。
- 不自动重放一个执行到一半的 `write` 或 `shell`。PoC 没有 shell；文件写入要在返回工具结果之前完成，做不到就向模型返回失败，而不是重启后续写。

`TurnSupervisor` 接口留在 `:core:contracts`，PoC 的实现是 `InProcessTurnSupervisor`。以后若要「离开界面仍继续」，再换一个带通知的前台服务实现，而不是把服务写进 Host。

Proactive 的 1 秒 tick 不搬。Mac 上 tick 也只是到点看一眼策略，并不跑模型。Android 上打开 Proactive 面板时现算 snapshot。`intervalMs`、`pausedUntil`、`sourceIds` 照常持久化，供以后的 `ProactiveSource` 使用。PoC 不注册任何 source。`check` 在没有 source 时记下 `waiting-context`，和现在的 Host 一样。

## 9. 功能对照

「范围内」指 PoC 要在模拟器上能演示。「范围外」指这一期不实现，但接口不堵死。

| Mac 能力 | Android | PoC |
| --- | --- | --- |
| 多 Nunu：名字、描述、标签、颜色、形状、材质 | 同一套 profile 字段。形状用现有 SVG path 画在 Compose 里。材质用色板和简单质感，不打包 9.4 MB 的 png/webm | 范围内 |
| 创建时随机外观并永久绑定；用户只选颜色 | `rollAgentAvatar` 的纯函数搬进 `:core:protocol` | 范围内 |
| three.js 三种开箱动画、彩纸、动作图集、webm | 创建成功时播一段 Compose 动画，遵守 `prefers-reduced-motion` 的系统设置。不引入 3D 引擎 | 范围内做 2D。3D 和 webm 范围外 |
| 角色模板 Researcher / Project partner / Daily operator | 只填文字，不改外观 | 范围内 |
| 侧栏搜索、置顶、分组、拖拽、宽度 | 列表和分组照做。拖拽用 Compose 手势。宽度在手机上改为抽屉，平板上保留可拖分栏 | 范围内 |
| 一对一发送、停止、流式文本 | `Flow` 收集 delta | 范围内 |
| thinking 与工具活动折叠成组 | 移植 `activity-groups.ts` 的分组规则 | 范围内 |
| 附件，5 × 10 MiB，合计 20 MiB | SAF 选文件。图片进当轮，不进转录 | 范围内 |
| 点附件用 Finder 打开 | `ACTION_VIEW`，失败则分享 | 范围内 |
| 工具审批：拒绝 / 一次 / 始终允许 | 同一条审批条。`never` 仍不出现在这条 UI 上，和现在一样 | 范围内 |
| Widget 卡片，最多 6 个选项 | Compose 卡片。旧版 JSON widget 继续用等宽文本显示，不发明新渲染 | 范围内 |
| Peer 消息抽屉 | 同一投影 | 范围内 |
| 资料页改身份、命令策略、撤销 grant、打开工作区 | 工作区用 SAF 或托管目录 | 范围内 |
| 设置：语言 zh-CN / en、主题、三家 provider、DeepSeek 两个模型、API key | 同字段。key 不回显 | 范围内 |
| 全局 `defaultToolPermission` | 协议保留，设置页仍然不放入口 | 范围内（行为与 Mac 一致，即没有这个开关） |
| 删除 Nunu、从侧栏隐藏 | API 可以在 `AgentPort` 留出，界面不做 | 范围外。Mac 界面也没有 |
| 会话内换模型 | 不做 | 范围外。Mac 界面也没有 |
| Room、升级为 NunuBar、共享聊天、@、停止和继续 | 同一状态机和 `discussionLimits` | 范围内 |
| 任务泳道、交付物、派发、状态迁移、执行历史 | 同一 `WorkTaskState` | 范围内 |
| 用户在界面上新建任务卡 | 不做按钮 | 范围外。`WorkBoard` 今天没有调用 `onCreateTask`。模型 `CreateTask` 仍在范围内 |
| 能力目录本地导入 | 元数据可存。`knowledge` 的只读根可以是 SAF 树 | 范围内（元数据 + knowledge 只读） |
| 能力商店「即将推出」 | 保留禁用页 | 范围内，仍然不可用 |
| `RunWorkCLI`、`cli` 目录项的执行 | 调用返回明确错误：这一版没有本地可执行文件 | 范围外 |
| `skill` 清单的执行 | 只保存路径说明，不加载代码 | 范围外 |
| 文件工具 read / write / str_replace / multi_str_replace / delete / ls / glob | 对托管目录和 SAF 树实现。diff 上限 12_000，读上限 30_000，树上限 20_000，glob 500 | 范围内 |
| `grep` | Kotlin 递归扫描，遵守同样的输出上限。不依赖 `rg` | 范围内 |
| `shell`、持久 bash | 不实现。模型若调用，工具结果说明 PoC 没有 shell | 范围外。接口 `ToolBackend` 留着 |
| `request_network` | 不做。Mac 上进程内实现本来就会抛错，真要跑必须过 darwin executor | 范围外 |
| `external_operation` | 同 shell | 范围外 |
| OS sandbox / seatbelt | 用目录范围代替。不声称等价于 seatbelt | 范围外 |
| 审批 `always` 也不能读 secrets 和 Host 数据目录 | denied 根包含 `filesDir/nuum` 的非工作区部分和 `noBackupFilesDir` | 范围内 |
| 命令黑名单 `rm -rf /`、`mkfs`、`dd if=`、fork bomb | shell 不存在，这组正则无调用点。规则文本仍放在 protocol 测试里，以免以后接回时丢掉 | 范围内（测试保留），执行范围外 |
| 压缩、16 轮上限、静默提醒、128k 窗口、0.75 / 0.80 / 0.85 / 0.90 水位 | 原样移植 | 范围内 |
| 调度：全局 3、每 agent 1、projectRoot 不重叠 | 原样 | 范围内 |
| Wake：3 hop、每分钟 3 次、每 run 最多新建 1 个 agent、全局 50 | 原样 | 范围内 |
| 委派工具里除 `RunWorkCLI` 以外的全部 | Host 实现 | 范围内 |
| CheckAgent 的可视化卡片、秘密输入卡、widget 自动收起 | 不做 | 范围外。`TODO.md` 里 Mac 也未做 |
| Proactive 菜单栏、开关、暂停、Check setup | 设置里的一个面板，加上通知渠道之外的应用内状态。没有常驻通知 | 范围内（与现行为对齐） |
| Proactive 采集和自主行动 | `actionsAvailable = false`，无 source | 范围外 |
| 跨用户协作 | 不存在于 Mac | 范围外 |
| 账号、后端、云电脑、多设备同步 | 只留第 14 节的接口 | 范围外 |

系统提示词里「跑在用户自己的 Mac 上」「real shell」这两句要改成当前设备的事实：本地 Android 应用，可以读授权目录里的文件，不能跑 shell。其余段落（自主决定、不编造数据、发声工具才是出口）保留。冻结前缀的机制保留，所以这句环境描述放在不参与缓存的那段，避免每次系统信息变化都打掉前缀。Mac 实现把 OS 放进环境段（`PromptEnvironment.os`），Android 同样把 `Build.VERSION` 放在那里。

## 10. 威胁模型

要保护的东西：三把 API key、转录、记忆、工作区文件、已经记住的工具授权。

| 威胁 | PoC 的处理 |
| --- | --- |
| 备份或设备迁移把 key 带走 | `allowBackup=false`，密文在 `noBackupFilesDir`，extraction rules 再排除一次 |
| logcat、崩溃文本、调试代理看到 key | 拦截器剥离认证头；异常不拼接 key；release 无 body 日志 |
| 模型通过 `read` 把 `secrets.bin` 读出来 | denied 根。单测覆盖，即使权限是 `always` |
| 模型诱导写工作区之外的路径 | 路径必须落在托管目录、SAF 树或该 agent 的 scratch。agent 自己的 memory 目录对工具只读 |
| 恶意附件 | 数量和大小限额；不执行附件；图片只按白名单 MIME 解码 |
| 另一应用读 Nuum 的文件 | 转录和记忆在应用私有目录。SAF 树的安全边界是用户授权，文档里要写明 |
| 提示注入把工具结果当成指令 | 压缩提示已经要求把证据当引用而不是指令（`compaction.ts`）。PoC 保留这段 system 文本。这不是沙箱，不能写成已经解决 |
| 根设备、解锁后的物理接触 | 不在 PoC 的对抗范围内。Keystore 挡不住持有解锁设备的人 |
| 把 key 送到自建后端 | PoC 没有后端。`ModelPort` 的实现只允许三个写死的 HTTPS 源。新增源要改代码，不能从设置里填任意 base URL |

不记录的东西：key、`Authorization`、图片 base64、SAF 文档的正文。可以记录的东西：provider 名、模型名、HTTP 状态码、工具名、字节数、runId。

## 11. 性能预算

这些是以后阶段的验收线，不是本机已经测到的数字。

| 项 | 目标 | 怎么守 |
| --- | --- | --- |
| 冷启动到第一帧 | 模拟器 API 36 x86_64 上 < 800 ms，不含模型请求 | 组合根不做 IO。设置和 agent 列表异步读。Macrobenchmark 放到验收包，PoC 后期再跑 |
| 空闲内存 | PSS < 180 MB | 不加载 three.js，不把 9.4 MB 原图打进包 |
| 一次流式会话 | PSS < 350 MB | delta 进环形缓冲，完成后再落转录。图片不进 JSONL |
| release APK | < 30 MB | R8 minify + shrinkResources。Nunu 身体若要位图，由设计包给 webp，单张 < 200 KB。PoC 默认用矢量形状，可以不带那些 png |
| debug APK | < 45 MB | 同上，允许调试符号 |
| 安装包里的原生库 | 0 | 无 NDK |
| 并发模型调用 | 最多 3 个 run | 已有调度上限，也是电量和流量的上限 |
| 主线程 | 不解析 JSONL，不跑压缩 | 磁盘和 SSE 都在 `Dispatchers.IO` |

启动时不要扫描全部转录。列表数据来自 Room 投影；打开某个 Nunu 才读它的 JSONL 尾部。Mac 的 `readLinesBackward` 就是这个习惯。

## 12. 测试

| 层 | 放哪 | 覆盖 |
| --- | --- | --- |
| JVM 单元测试 | `:core:protocol`，`:core:kernel`，`:core:agent` 的纯函数 | token 估算、16 轮停止、提醒阈值、压缩切分、记忆去重和 100 条上限、讨论 3×10、调度上限、wake 限额、SendMessage 参数错误文案、模型消息编码（DeepSeek 丢图、Anthropic system 抽离）。模型用假的 `ModelPort`，不联网 |
| Robolectric | `:core:storage`，`:feature:*` 里不需要模拟器的 Compose 逻辑 | JSONL 尾部损坏、Room 投影可从文件重建、主题和语言 |
| Keystore | `:core:security` 的 `androidTest` | 加密往返、文件不在 `filesDir`、日志不含假 key。Robolectric 的 Keystore 不可靠，这项放真机或模拟器 |
| Compose UI | 各 feature 模块的 `androidTest`，或 JVM Compose 测试 | 空会话、审批三条按钮、widget、设置页不回显 key、NunuBar 泳道 |
| 仪器 | `:testing:acceptance` | 见 `WORK_BREAKDOWN.md` 的验收包。MockWebServer 放在设备侧不可用时，改为 Host 测试里的假 `ModelPort`；SSE 解析的字节级测试留在 `:core:model` 的 JVM 测试，用 OkHttp `MockWebServer` |
| 架构 | CI 的依赖检查 | 第 3.1 节的禁止依赖 |
| 回归 | 不改 Mac 包 | CI 可以继续跑现有 `pnpm test`，但 Android job 不依赖它 |

不在 CI 里放真的 API key，也不打真的 provider。

## 13. 编码约定

- 标识符英语，和现有包一致：`Nunu`、`Room`、`NunuBar`、`runId`、`SendMessage` 不要翻译。
- 领域注释可以用中文，因为被移植的注释本来就是中文。不翻译成另一套说法。
- Kotlin 官方风格，4 空格。公开函数不写无信息量的 KDoc。
- 协程：调用方传入 `CoroutineScope`。禁止 `GlobalScope`。禁止在主线程调用 `runBlocking`。
- 错误用现有数字码加一条人话，包在一个 `NuumException(code, message)` 里，对应 `RpcError`。不要发明平行的异常体系。
- 序列化字段名与 JSON 文件里的名字一致，这样同一份 `transcript.jsonl` 的形状在两边可读。
- 时间用 `Long` epoch millis，和 `createdAt` 一致，不用在存储层改成 `Instant` 的另一种纪元。
- UI 字符串进 `values/strings.xml` 和 `values-zh-rCN/strings.xml`。默认语言跟随系统；应用内设置仍可强制 `zh-CN` 或 `en`，和 `Language` 枚举一致。缺省文案以现有 `messages.ts` 为准，不重写产品用语。
- feature 模块不出现 `java.io.File` 指向数据目录的代码。它们只调 Port。
- 每个模块的测试放在该模块内。验收工程除外。
- 不格式化、不移动 `apps/` 和 `packages/` 下的任何文件。

## 14. 以后的缝

全部放在 `:core:contracts`。PoC 只提供下面这些默认实现，调用点集中在 `AppGraph`，方便整段替换。

| 接口 | PoC 实现 | 以后 |
| --- | --- | --- |
| `ModelPort` | 三个直连客户端 | 账号体系出现后可以换成走后端的实现。Host 和 UI 不改 |
| `SecretStore` | Keystore 文件 | 账号绑定的密钥。本地文件实现保留给离线 |
| `IdentityContext` | `LocalOnly`，没有 userId | `AccountSession`。转录记录不提前加 user 字段，避免把空字段写进真源 |
| `SyncPort` | `NoSync`，方法是空操作 | 多设备。同步的单位以后是 agent 目录和 work 时间线，不是 Room 行 |
| `TurnSupervisor` | 进程内 | 前台服务 |
| `ToolBackend` | 目录型文件工具，shell / network 返回「未实现」 | 若要做执行隔离，单独的实现，不把 seatbelt API 写进 Kernel |
| `ProactiveSource` | 无注册 | 采集。`actionsAvailable` 在有真正的行动执行器之前保持 `false` |
| `Clock` | 系统时钟 | 测试注入。记忆半衰期和 proactive 暂停都吃它 |

不要为这些缝加数据库列、不要加登录按钮、不要加「云端执行」开关。空实现如果需要被 UI 观察到，就什么都不显示。

## 15. 构建与验证环境

探测发生在 2026-10-29 的这台 Cloud Agent VM 上，不是猜测。

### 15.1 机器

- 内核 `6.12.94+`，`x86_64`，4 vCPU。`/proc/cpuinfo` 有 `vmx`。`/sys/module/kvm_intel/parameters/nested` 为 `Y`。
- `/dev/kvm` 存在。最初权限 `crw-rw---- root:103`。`ubuntu` 不在 gid 103，`/etc/group` 里这个 gid 没有名字。直接 open 失败。
- `sudo -n` 可用。`sudo chmod 666 /dev/kvm` 之后，同一用户 `os.open("/dev/kvm", O_RDWR)` 成功。这个 chmod 不会跨重启保留。以后每次启动模拟器前都要再做一次，或者把用户加入对应组。
- 内存：`MemTotal` 约 16 GB。`/proc/vmstat` 的 `balloon_inflate` 为 2_621_440 页（约 10 GB），`balloon_deflate` 为 0。探测时 `MemAvailable` 约 5 GB，没有 swap。气球会在分配压力下缩小，但快速拉起模拟器加 Gradle 仍可能顶满。
- 磁盘：`/` 约 254 GB，探测前可用约 247 GB。空间不是限制。
- JDK：OpenJDK `21.0.12`。开始时没有 `ANDROID_HOME`，也没有系统里的 `sdkmanager`。

### 15.2 SDK 与 APK

命令行工具是 `commandlinetools-linux-14742923_latest.zip`，装在 `/tmp/android-sdk`，没有进仓库。`sdkmanager` 安装成功，随后又装上了 `platforms;android-37.0` 和 `build-tools;37.0.0`。包名 `platforms;android-37` 不存在，安装失败并打印 `Failed to find package 'platforms;android-37'`。

| 包 | 版本 |
| --- | --- |
| platform-tools | 37.0.1 |
| build-tools | 36.0.0，以及后装的 37.0.0 |
| platforms;android-36 | 2 |
| platforms;android-37.0 | 已安装，目录 `/tmp/android-sdk/platforms/android-37.0` |
| emulator | 37.2.12 |
| system-images;android-36;google_apis;x86_64 | 7 |

空的 `/tmp/apk-probe` 用 AGP `9.5.0`、Gradle `9.6.0`、JDK 21 打 debug APK。第一次失败，错误是：

`The 'org.jetbrains.kotlin.android' plugin is no longer required for Kotlin support since AGP 9.0.`

去掉这个插件、改用 AGP built-in Kotlin 之后：

- `compileSdk = 36`：`BUILD SUCCESSFUL in 27s`，APK 约 2.5 MB。
- `compileSdk = 37`：`BUILD SUCCESSFUL in 14s`，APK 约 2.6 MB。

这是探测工程，不是 Nuum。仓库里没有 Android 应用代码。

### 15.3 模拟器

`sudo chmod 666 /dev/kvm` 之后，`/dev/kvm` 可以 `O_RDWR` 打开。`emulator -accel-check` 打印 `KVM (version 12) is installed and usable.`

`-accel on` 的无界面启动没有跑起来。QEMU 命令行里有 `-enable-kvm`，随后宿主机内核打出：

`kernel BUG at arch/x86/kvm/x86.c:702!`，调用栈是 `kvm_spurious_fault` → `vmx_vcpu_create` → `kvm_arch_vcpu_create`。`adb devices` 为空，5554/5555 没有在听。进程被杀掉。

`-accel off -no-window -gpu off` 能启动，并打印 `x86_64 emulation may not work without hardware acceleration!`。进程大约占满一个核，RSS 到约 2.9 GB。观察窗口内：

- `adb devices` 先是 `emulator-5554 offline`，随后变成 `emulator-5554 device`。
- `getprop init.svc.zygote` 为 `running`。
- `getprop ro.build.version.sdk` 为 `36`。
- `sys.boot_completed` 和 `dev.bootcomplete` 一直是空的。
- `adb install` 失败：`Can't find service: package`。
- `am start` 失败：`Can't find service: activity`。

没有继续等到 `sys.boot_completed`。探测进程已停。

### 15.4 以后阶段怎么验证

这台 VM 上，冷启动一台模拟器直到能装包，是慢而且不稳定的嵌套虚拟化，不要当作每条 PR 的门禁。

1. 每条 PR 跑 JVM 单元测试、Robolectric，以及 `assembleDebug`。这三条在这次探测里不依赖能启动的系统镜像，APK 构建已经成功。
2. 仪器测试放到已经预热好的 AVD 上：镜像和 userdata 留着，不要每次从 `-no-snapshot` 冷启动。超时要比这次用的三到六分钟更长，并且以 `sys.boot_completed=1` 而且 `package` 服务存在为准，不要只看 `adb devices` 出现 `device`。
3. 若必须用硬件加速，换一台嵌套 KVM 能真正创建 vCPU 的机器或池。本机的 `accel-check` 通过不等于 `-accel on` 能开机。
4. 不要在这台机器上改用 ARM 镜像。CPU 是 x86_64，ARM 会再加一层翻译。
5. Gradle 和模拟器不要同时顶满内存。先完成 `assembleDebug`，停掉 daemon，再开 AVD。
