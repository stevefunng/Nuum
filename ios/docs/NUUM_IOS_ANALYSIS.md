# Nuum iOS 对齐分析

分析基线：`main` @ `c91bb7206a14174b4384d09ce37d41a809eef94e`（`feat(android): WP-13 acceptance scenarios`，PR #16）。本文只描述仓库里已经存在的东西，以及 iOS 客户端要守住的边界。不把路线图写成已实现功能。

Mac 行为的展开在 [android/docs/NUUM_MACOS_ANALYSIS.md](../../android/docs/NUUM_MACOS_ANALYSIS.md)，那份的基线是 `9e4a3ad`。它写成时仓库里还没有 Android。Android 的模块以当前 `android/` 源码为准。iOS 的设计在 [IOS_ARCHITECTURE.md](./IOS_ARCHITECTURE.md)，包的顺序在 [WORK_BREAKDOWN.md](./WORK_BREAKDOWN.md)。

仓库里今天没有 `ios/` 应用工程。本目录只有文档。

## 1. 已经存在、iOS 必须对齐的部分

### 1.1 Mac 桌面是产品真源

Nuum 是本地优先的伴侣应用。每个 Nunu 有自己的身份、记忆和工作区。用户可以一对一交谈，把多个 Nunu 放进 Room，再把 Room 升级成 NunuBar。模型请求发到用户自己配置的 provider。没有账号、没有后端、没有多设备同步。

桌面壳是 Electron，不是 Swift。领域在 TypeScript 里：

```text
apps/desktop          Electron main / preload / renderer
packages/ui           React。只允许依赖 @nuum/protocol
packages/host         转录、记忆、权限、调度、Room / NunuBar
packages/kernel       模型循环。不知道 agent 是谁
packages/protocol     Zod 契约
packages/tools        内置工具
packages/sandbox      进程内执行边界
packages/executor     仅 macOS 桌面验证过的守护进程
```

`dependency-cruiser.cjs` 禁止 kernel / tools 依赖 host 和 UI，禁止 host import kernel 的实现，禁止 UI 依赖后端包。`packages/protocol/src/kernel-contract.ts` 写明 Kernel 只认 `runId`。

文件是真源，没有数据库。相对路径、转录事件、work 状态机、三家 provider 的请求形状、附件限额（5 个、单个 10 MiB、合计 20 MiB）、错误数字码，都在 `packages/protocol/src` 和 `packages/host/src`。这些是 iOS 要编码进去的合同，不是可以重画的草图。

桌面秘密存储在 `apps/desktop` 的 `secrets.bin`。加密可用时走 Electron `safeStorage`（macOS 上由 Keychain 支持）。加密不可用时同一文件退回明文。这是现有行为。iOS 不复制这条退路。

`packages/executor/src/runner.ts` 在 `process.platform !== "darwin"` 时抛出 `This release has only validated macOS isolation; execution is disabled on this platform.` iOS 的内核也是 darwin，这句拦不住一个被塞进 App 的 Node 进程。iOS 仍然不移植 executor：那条路径是 macOS seatbelt 和 Unix socket，不是 iPhone 的沙箱。

### 1.2 Android PoC 是已经落地的移植

Android 工程在 `android/`，不在 pnpm workspace 里。`android/settings.gradle.kts` 的模块是 `:app`、`:core:contracts`、`:core:protocol`、`:core:security`、`:core:storage`、`:core:model`、`:core:kernel`、`:core:agent`、`:core:tools`、`:feature:shell`、`:feature:conversation`、`:feature:work`、`:feature:settings`、`:testing:acceptance`。

iOS 对齐的是这些模块的边界和公开类型，不是 Kotlin 或 Compose：

| 合同 | 当前实现 |
| --- | --- |
| 端口和事件名 | `android/core/contracts/src/main/kotlin/com/nuum/contracts/Ports.kt`、`HostEvent.kt` |
| 相对路径 | 同目录 `Paths.kt` 的 `NuumPaths`。会话哈希在 `android/core/storage/.../StoragePaths.kt` |
| 错误码 | `android/core/protocol/.../Errors.kt`，与 `packages/protocol/src/errors.ts` 相同 |
| 模型 id、回退顺序、`Secrets` 字段 | `android/core/protocol/.../Domain.kt` |
| Keystore 与 JSON 形状 | `KeystoreSecretStore.kt`（alias `nuum.secrets`）、`SecretsCodec.kt` |
| 组合根 | `android/app/src/main/kotlin/com/nuum/graph/AppGraph.kt`。手工构造，`LocalOnly`，`NoSync` |
| 依赖方向 | `android/build.gradle.kts` 的 `checkDependencyDirection` |
| 限额 | `android/core/agent/.../Limits.kt`、`android/core/tools/.../Limits.kt`、`android/core/kernel/.../Kernel.kt` |
| 环境句 | `android/core/agent/.../Prompt.kt`：本地 Android、可读授权目录、不能跑 shell。OS 放在不冻结的环境段 |
| 验收场景 | `android/docs/acceptance/SCENARIOS.md` |

Android 的 CI 是 `.github/workflows/android.yml`，只在 `android/**` 和这份 workflow 自身变化时跑，跑在 `ubuntu-latest`。iOS 文档和以后的 iOS 工程都不改这个文件，也不改它的 release 预算。

### 1.3 要保住的不变量

Mac 分析第 11 节的六条，Android 已经按这个方向实现。iOS 同样保住：

1. UI 不持有模型端口，也不把 API key 写进转录、日志或普通设置。
2. Kernel 只认 `runId`。agent、work、记忆都在 Host。
3. 用户只看见发声工具的产物。工具过程和 thinking 可以折叠，规则与 `packages/ui/src/conversation/activity-groups.ts` 相同。
4. 运行状态不落成假的 running。进程死了，下次起来是 idle，除非转录里有待恢复的 wake 或未认领的执行结果。
5. 工具默认 `ask`。拒绝和始终允许要能记住。秘密文件即使 `always` 也不可读。
6. 压缩在调用模型的同一侧发生。Host 不另开一条模型客户端。`summarize.run` 仍走 Kernel。

## 2. 缺口

### 2.1 相对 Mac，iOS 有意不做

这些在 Mac 上存在，Android PoC 也没有搬进设备，iOS 同样不做：

- Electron、React、three.js 开箱、webm、菜单栏 tray、红绿灯窗口。
- `safeStorage` 的明文退路，以及设置页把 key 填回输入框。iOS 跟 Android：只写不读。
- executor、`sandbox-runtime`、Unix socket、seatbelt、持久 bash、外部 `rg`。
- 任意 shell、`request_network`、`external_operation` 的真正执行。工具表保留，调用返回未实现。
- 账号、后端、云同步、跨用户 Room。
- `TODO.md` 的三项。
- 删除 Nunu 的界面、从侧栏隐藏的开关、会话内换模型、设置里的全局工具权限、用户在 NunuBar 上手工建卡、能力商店、Proactive 的采集和自主行动。Mac 的界面今天也没有这些。

产品 widget（转录卡片，最多 6 个选项）要做。WidgetKit 主屏幕小组件不做。两件事名字容易混，实现不能混。

### 2.2 相对 Mac，Android 已经记下、iOS 跟着 Android 的差异

`android/docs/acceptance/SCENARIOS.md` 写明两处 Host 行为，iOS 按这个已经能跑通的版本对齐，而不是在文档里再发明第三种：

- `turn.context` 必须回答，否则带上下文窗口的 turn 会一直等。回答不替换消息。轮前 0.75 的压缩保留。Mac 在约 0.80 / 0.85 做的轮中压缩，Android 没有移植。iOS 第一期也不移植。补的时候仍走同一次 `provideContext`。
- `always` / `never` 记住的是 pending 事件上的 action 和规范化 target，不是工具参数里的一个 `action` 字段。写文件的参数只有路径和内容。

系统提示的环境句要换成 iOS 的事实。机制与 `Prompt.kt` 相同：这句话在环境段，不在冻结前缀里。

Android 工具的未实现句子是 `This Android PoC does not implement this tool.` iOS 用 `This iOS client does not implement this tool.` `RunWorkCLI` 的句子两边相同：`This version of Nuum has no local executable. RunWorkCLI is not implemented.`

### 2.3 相对 Android，平台不同因而实现不同

| Android | iOS |
| --- | --- |
| Kotlin、Gradle、Compose、OkHttp、Room 投影 | Swift、SwiftUI、`URLSession`、文件投影。不把 Room 再做一个数据库 |
| Keystore AES-GCM + `noBackupFilesDir/secrets.bin` | 同一 JSON 放进一条 Keychain item，service `nuum.secrets`。不写 `secrets.bin` |
| SAF `takePersistableUriPermission` | `fileImporter` 的 security-scoped bookmark |
| `filesDir/nuum` | Application Support 的 `nuum/`。不开文件共享 |
| 进程被杀死才丢内存；没有后台模型 | 还会被挂起。不声明后台模式，不用 background URLSession 跑模型 |
| Robolectric 可以在 Linux CI 上跑一部分 UI | Keychain 和 SwiftUI 测试要 Mac 上的模拟器 |
| `minSdk` 28、`compileSdk` 37 | 最低 iOS 26.0，SDK iOS 27.2。版本在架构文档第 2 节，脚手架在 Mac 上复核 |

Android 的设计规格（`android/docs/design/`）是屏幕行为的参考。iOS 不复制 Material，也不复制 XML。sand token 仍是 `packages/ui` 里的那一套。

## 3. 约束

1. **API key 在应用里配置。** 三个 provider 由用户粘贴 key。请求只发到架构文档第 6 节的三个 HTTPS 源。设置里没有自定义 base URL。
2. **源码、文档、xcconfig、CI、示例 plist 里不放 key。** 不提交 `.env`。测试只用假 key，并断言它没有出现在异常和日志里。
3. **先文档，后脚手架。** 本 PR 不创建 Xcode 工程、Swift package、Info.plist 或 workflow。那些是 [WORK_BREAKDOWN.md](./WORK_BREAKDOWN.md) 的 WP-00，而且要在装了 Xcode 的 Mac 上做。这台 Linux 环境编不过 iOS。
4. **不改 Android 应用。** 不动 `android/src`、Gradle、`libs.versions.toml`、`.github/workflows/android.yml`。不动 `apps/` 和 `packages/`。
5. **`ios/` 不进 pnpm workspace。** 根 `.gitignore` 的 `/docs/*` 会吞掉 `docs/ios/`，所以文档在 `ios/docs/`。
6. **不加 Datadog、其他观测 SDK，也不加金融 SDK。** 不加 LLM SDK。
7. **根 `README.md` 这次不改。** 它描述桌面应用，仓库地图没有 `android/`。只加一行 iOS 会让 Android 客户端看起来不存在。

## 4. 契约索引

实现时以这些文件为准。名字冲突时，优先 Mac `packages/protocol` 的 JSON 字段，其次 Android `contracts` 里已经公开的端口名。

| 主题 | 文件 |
| --- | --- |
| 领域、`Secrets`、默认模型 | `packages/protocol/src/domain.ts`，`android/core/protocol/.../Domain.kt` |
| 转录 | `packages/protocol/src/transcript.ts` |
| Work | `packages/protocol/src/work.ts` |
| 委派工具 | `packages/protocol/src/product-tools.ts` |
| 附件限额 | `packages/protocol/src/attachments.ts` |
| 错误码 | `packages/protocol/src/errors.ts` |
| Host 方法与事件 | `packages/protocol/src/host-contract.ts`，`android/core/contracts/.../Ports.kt`，`HostEvent.kt` |
| Kernel 只认 runId | `packages/protocol/src/kernel-contract.ts` |
| 路径 | `android/core/contracts/.../Paths.kt`，`android/core/storage/.../StoragePaths.kt` |
| turn 循环 | `packages/kernel/src/loop.ts`，`android/core/kernel/.../Kernel.kt` |
| 秘密 | `android/core/security/.../KeystoreSecretStore.kt`，`SecretsCodec.kt`。Mac 明文退路在 `apps/desktop` 的主进程，iOS 不跟 |
| 验收口径 | `android/docs/acceptance/SCENARIOS.md` |

iOS 不另起一套事件名、错误码或 JSON 字段。
