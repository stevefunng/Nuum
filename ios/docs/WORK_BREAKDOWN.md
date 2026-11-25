# Nuum iOS 工作包

目标是让文档合并之后，不同的人可以同时做，合并时不改同一批文件。规则和 Android 一样：除了脚手架，谁的包就只改谁的目录。契约不够用时，在自己的 package 里加内部类型，把「要改 `NuumContracts`」记成给脚手架的一条后续，而不是直接改冻结文件。

设计依据是 [IOS_ARCHITECTURE.md](./IOS_ARCHITECTURE.md) 和 [NUUM_IOS_ANALYSIS.md](./NUUM_IOS_ANALYSIS.md)。行为与 [android/docs/WORK_BREAKDOWN.md](../../android/docs/WORK_BREAKDOWN.md) 的同名包对齐。下面只写 iOS 的差别和依赖。本文件不启动这些包。

## 必须等 Mac / Xcode 的事

Phase 0 写在 Linux 上。这里没有 `xcodebuild`，也没有模拟器。下面的事在 WP-00 以及之后的完成标准里，不能由一台没有 Xcode 的机器宣称做完：

- 创建 `Nuum.xcodeproj`、签名、能力、Privacy manifest。
- 用 Xcode 27.2 编译任意 package 或 App。架构文档第 2 节的版本要在这台 Mac 上用 `xcodebuild -version` 和 `swift --version` 复核。不用 Xcode 27.3 beta。
- 启动模拟器或安装到设备。
- Keychain 往返。没有 Keychain 的桩不能算 `NuumSecurity` 完成。
- SwiftUI / XCTest 界面测试。
- 确认 ATS、备份排除和后台模式确实没有加进打出来的包。

纯 Swift 源文件可以在任何地方写。完成标准仍是 Mac 上的 `swift test` 或 `xcodebuild test`。Linux 上碰巧编译通过不能代替。本仓库不把 Linux Swift 设成 CI 门禁。

GitHub macOS runner 不假定已经装了 Xcode 27.2。在确认 runner 镜像之前，WP-00 可以只在 PR 里贴 Mac 上的版本和测试结果，而不加必需的 iOS job。一旦加 workflow，它只匹配 `ios/**` 和它自己的文件，跑在 macOS 上，不去改 `.github/workflows/android.yml`。

## 顺序

```text
WP-00 脚手架          只能在 Mac / Xcode 上完成
   ├─ WP-D  设计       只写 ios/docs/design，可与 WP-00 并行，不编译
   ├─ WP-01 protocol
   ├─ WP-02 security   完成测试要模拟器
   ├─ WP-03 storage
   ├─ WP-04 model
   ├─ WP-05 kernel     依赖契约里的 ModelPort、ToolExecutor，不依赖 WP-04 的类
   ├─ WP-06 tools
   ├─ WP-07 agent      依赖契约，不依赖各实现的源文件
   ├─ WP-08 shell
   ├─ WP-09 conversation
   ├─ WP-10 work
   └─ WP-11 settings
WP-12 组合根           等 WP-02…WP-11 的公开构造函数都在
WP-13 验收             夹具可以先写；模拟器上的全量场景等 WP-12，并且要 Mac
```

WP-01 到 WP-11 彼此不改同一个文件，可以同时开工。它们都只编译自己的 package，并用契约里的假实现做测试。WP-12 是唯一把它们构造在一起的包。

## 冻结文件

WP-00 合并之后，下面这些只有脚手架的后续 PR 能改：

- `ios/Nuum.xcodeproj/**`
- `ios/App/**` 里除了 `Graph/` 以外的骨架（WP-12 按下面的交接改入口画面）
- 各 package 的 `Package.swift`
- `ios/App` 的签名、能力、Info 设置、Privacy manifest
- 将来若有 `.github/workflows/ios.yml`，也归脚手架

功能包发现缺依赖时，在自己的 PR 描述里点名。不要私自加第三方 package，也不要改部署版本。

## WP-00 脚手架

必须第一个进主干。没有它，其他包没有模块边界。本文件所在的文档 PR 不是这一包。

**范围**

- Xcode 27.2 能编出一个空的 SwiftUI App，窗口显示应用名 Nuum。`xcodebuild` 的实际版本写进 PR。
- 建好架构文档第 3 节的全部 package。除 `App` 和 `NuumContracts` 外，每个 package 只有能编译的空占位。
- `NuumContracts` 放上架构文档第 4、5、15 节的端口和最小类型。方法可以先抛未实现，签名要够 WP-07 和各 feature 编译。
- `NuumProtocol` 的 `Package.swift` 不依赖 UIKit、SwiftUI、Security、URLSession。
- Bundle id 用 `com.nuum`，与 Android `applicationId` 相同。
- 能力：不声明 `UIBackgroundModes`，不开 iCloud，不开 App Group，不开推送，不加 `NSAllowsArbitraryLoads`，不开 `UIFileSharingEnabled`。
- Privacy manifest 只声明实际用到的系统 API，不声明追踪。
- `ios/README.md` 用几行说明要 Xcode 27.2，以及在 Mac 上怎么编。不改仓库根的 `README.md`。

**拥有**

- 上面的冻结文件。
- `ios/App` 的入口。显示应用名的那个画面文件头注释 `OWNED BY WP-12 AFTER SCAFFOLD`。其他人不要改它。

**交出的契约**

- `ModelPort`、`KernelPort`、`ToolExecutor`、`ToolBackend`、`SecretStore`、`AgentStore`、`Clock`、`IdentityContext`、`SyncPort`、`TurnSupervisor`、`ProactiveSource`。
- `SettingsPort`、`SecretWriter`、`AgentPort`、`WorkPort`、`ProactivePort`、`DesktopPort`。
- `HostEvent`，名字与 `HostEvents` 一致，不含 `host.kernel.down`。
- `NuumError(code, message)`。
- 扫 import 的测试，失败即这一包没有完成。

**依赖**

- 无。设计包可以并行，因为它不编译。

**完成**

- 在 Mac 上，空工程能编过，模拟器能画出应用名。CI 在 runner 确认之前不跑模拟器。
- 契约里没有 SwiftUI 类型。
- 打出来的包没有后台模式，ATS 没有放开明文。

## WP-D 设计

不写 Swift。工程师按规格在自己的 feature package 里实现。可与 WP-00 并行。

**范围**

- 只写 `ios/docs/design/**`。
- 颜色、字号、间距来自现有 sand token，并写明对应的 CSS 变量名。规格说明 compact 与 regular 两种宽度：侧栏是一列，不是把 1200×800 缩小。
- 屏幕与 Android `android/docs/design/screens/` 同一组：侧栏、空会话、转录、审批条、widget、附件、创建 Nunu、2D 开箱、资料、设置、Room、NunuBar、能力目录、Proactive。
- 每屏列出空、加载、流式、错误、无 key、权限被拒、讨论中断。
- 开箱在 `accessibilityReduceMotion` 下直接到终态。不要求 3D。
- 矢量优先。不把 `packages/ui/src/assets/nunu/` 的 9.4 MB 原图放进切图。
- 文案引用 `packages/ui/src/i18n/messages.ts` 的 key。
- 写明产品 widget 不是 WidgetKit。

**完成**

- 每个交互都指回 Mac 上的一个现有行为，或者写明「Mac 上没有，iOS 也不做」。
- 不要求 shell、菜单栏常驻、登录、同步、后台模型。
- 不修改 `ios/docs/design` 以外的路径。

## WP-01 protocol

**范围**

把 `packages/protocol/src` 和 `android/core/protocol` 里客户端会用到的类型和纯函数搬成 Swift。包括领域、转录、work、product-tools 的参数校验、token 估算、权限规则的数据形状、proactive、附件限额、错误码。不包括桌面窗口方法。

讨论限额 3 / 10 / 2 不在 protocol 里。WP-07 拥有这三个数字。本包只拥有 protocol 文件里已经有的常量，例如附件限额、proactive 间隔上下界。

**拥有** `ios/Packages/NuumProtocol/**` 里除 `Package.swift` 以外的源文件和测试。

**依赖** WP-00。

**完成**

- JSON 字段名与现有文件一致。
- SendMessage 的校验错误字符串保持英文。
- 测试覆盖：provider 回退顺序、附件限额、侧栏组织的唯一性、任务状态枚举、`actionsAvailable` 只能是 false、一张图的 token 估算加 8192。
- package 没有 UIKit、SwiftUI、Security、URLSession 的 import。
- Mac 上 `swift test` 通过。

## WP-02 security

**范围**

`KeychainSecretStore`。一条 Generic Password，service `nuum.secrets`，account `api-keys`，`AfterFirstUnlockThisDeviceOnly`，不同步。JSON 形状与 `SecretsCodec` 相同。失败抛 3001，句子用架构文档第 7 节的两句固定英文。不写 `secrets.bin`，不写明文。

**拥有** `ios/Packages/NuumSecurity/**` 的源文件和测试。

**依赖** `SecretStore` 契约。

**完成**

- 模拟器测试：写入后 Application Support 和 Documents 里都没有 `secrets.bin`；读回相等；没有 item 时读到空 `Secrets`。
- 异常 message 不含测试 key。
- 这项在 Mac 的模拟器上跑。Linux 上的假 Keychain 不算完成。

## WP-03 storage

**范围**

文件布局按架构文档第 8 节。原子写 JSON，append-only JSONL，坏尾行可恢复。列表投影从文件重建，不引入 SwiftData。UserDefaults suite `nuum-ui` 只放非秘密 UI 偏好。

记忆 Markdown 的规则属于 WP-07。本包按路径读写字节和文本，不解释 Markdown。

**拥有** `ios/Packages/NuumStorage/**` 的源文件和测试。

**依赖** `AgentStore` 契约、protocol 类型。

**交出** 路径函数公开，测试可以对照 `NuumPaths` 和 `StoragePaths` 的相对路径，包括 work session 的 sha256 规则。

**完成**

- 原子写中途失败不损坏旧文件。
- JSONL 最后一行截断只丢该行。
- 投影丢掉之后能从 `profile.json` 重建列表。
- `settings.json` 往返不含任何 key 字段。
- 数据根标记为排除备份。

## WP-04 model

**范围**

`URLSession` SSE。三个 provider 的请求和响应形状按 `packages/kernel/src/model/` 和 `android/core/model`。DeepSeek 不上传图片。认证头可剥离。

**拥有** `ios/Packages/NuumModel/**` 的源文件和测试。

**依赖** `ModelPort`。不依赖 Kernel。

**交出** 给 `ModelRef` 和 `Secrets` 返回端口和 key 的选择函数，签名与 `router.ts` 的选择顺序相同。缺 key 抛 `1007`。

**完成**

- 本地假 HTTP：OpenAI 工具调用增量拼接、`reasoning_content`、Anthropic `thinking_delta` 与 `input_json_delta`、非 200 变成 `1004` 且 message 里没有 key、取消后任务结束。
- 日志夹具断言 `Authorization` 和 `x-api-key` 不出现。
- 不打真的 provider。

## WP-05 kernel

**范围**

移植 `loop.ts` / `Kernel.kt` 的控制流。`MAX_ROUNDS = 16`，三种静默提醒的阈值和英文句子保持原样，取消不发 error，0.9 的失败句子保持原样。工具执行通过 `ToolExecutor`，不读文件系统。

**拥有** `ios/Packages/NuumKernel/**` 的源文件和测试。

**依赖** `ModelPort`、`ToolExecutor`、`KernelPort`。用测试假对象，不等 WP-04。

**交出** `Kernel`，实现 `KernelPort`。

**完成**

- 无工具则结束、委派工具等待结果、轮数用尽的提示、取消、缺 key。不发网络。
- package 不 import `URLSession`。

## WP-06 tools

**范围**

范围内的文件工具和 `grep`。路径判定顺序见架构文档第 9 节。`shell`、`request_network`、`external_operation` 注册进表，执行返回 `This iOS client does not implement this tool.` bookmark 还没有授权时，按路径在允许根之外拒绝。

**拥有** `ios/Packages/NuumTools/**` 的源文件和测试。

**依赖** `ToolBackend` / `ToolExecutor`。不依赖 agent。

**交出** `LocalToolBackend`。

**完成**

- `always` 仍读不到 `secrets.bin`、`host-secrets.json`、`credentials.json`、`secrets.json`。
- scratch 可写。agent memory 路径不可写；在工具包自己的根里、且没有被 denied 盖住时，memory 可读。这和 `PathPolicyTest` 一致。把整棵数据根放进 denied 的刻法属于 WP-12。
- `grep` 遵守输出上限，实现里没有进程启动调用。
- 不 import Security。

## WP-07 agent

**范围**

Host：调度、wake、prompt 组装、记忆规则、压缩触发、转录投影、委派工具（除 `RunWorkCLI`）、Room 讨论限额、NunuBar 状态迁移、执行结果认领、proactive 的 snapshot。

`turn.context` 必须回答，且不替换消息。轮前 0.75 压缩保留。不在这一包里补 Mac 的轮中 0.80 / 0.85 压缩。

环境句用架构文档第 10 节的 iOS 句子。OS 字符串由调用方注入。`RunWorkCLI` 返回未实现。`actionsAvailable` 恒为 false。不注册 `ProactiveSource`。

**拥有** `ios/Packages/NuumAgent/**` 的源文件和测试。

**依赖** 契约：`KernelPort`、`AgentStore`、`SecretStore`、`ToolBackend`、`Clock`。不 import 那些实现类型，不 import `URLSession` 或 UIKit。

**交出** `HostRuntime`，实现 `SettingsPort`、`AgentPort`、`WorkPort`、`ProactivePort`。turn 开始时向 `SecretStore` 要 `Secrets`，没有 key 就抛 `2004`。

**完成**

- 内存版 store 和假 Kernel：并发上限 3、同 agent 不重叠、讨论轮数、记忆去重与 profile 100 条、压缩不直接构造模型客户端、重启后 status 不是 running、wake 限额、`CreateAgent` 受 `MAX_AGENTS` 约束。
- 带上下文窗口的 turn 会收到 `provideContext` 回答。
- 提示词含 iOS 环境句，不含 `real shell`。

## WP-08 shell

**范围**

导航、侧栏、主题、创建 Nunu、2D 开箱、资料页身份。执行偏好的界面若与设置共享控件，放在本 package 的公开 SwiftUI 类型里，由设置包不重复实现，也不引用本包，以免两个 feature 互相依赖。保存走 `AgentPort`。

**拥有** `ios/Packages/NuumFeatureShell/**` 的源文件和测试。

**依赖** `AgentPort`、`SettingsPort`、`DesktopPort`、`WorkPort` 的只读列表。假端口放在本包的测试里，不放进 contracts。

**交出** shell 视图。中心槽由 `App` 填入会话或 NunuBar。

**完成**

- 空侧栏、置顶、分组重名被拒绝时的展示、创建时只提交颜色加上一次随机外观、reduced motion 不跑开箱动画。
- 不读 Application Support。

## WP-09 conversation

**范围**

一对一转录、输入、停止、附件（`DesktopPort` 选文件，字节交给 `AgentPort.send`）、审批条、widget、peer 抽屉、活动分组。pending 带 `workId` 时不在这里画审批条。

**拥有** `ios/Packages/NuumFeatureConversation/**` 的源文件和测试。

**依赖** `AgentPort`、`DesktopPort`。

**交出** 会话视图。

**完成**

- 空状态、delta 追加、审批回调是 `deny` / `once` / `always`、widget 选项变成一次 `answerWidget`、超过 5 个附件时不调用 send。
- 不绘制 NunuBar。

## WP-10 work

**范围**

Room / NunuBar：创建、升级、共享聊天、成员、泳道、交付物、派发、状态迁移、中断后继续、目录的本地导入和禁用的发现页、成员自己的审批条。不提供用户建卡按钮。

**拥有** `ios/Packages/NuumFeatureWork/**` 的源文件和测试。

**依赖** `WorkPort`、`AgentPort`、`DesktopPort`。

**交出** Work 视图和创建视图。

**完成**

- room 升级的 kind 是 `work`。发现页不可点。导入只提交协议允许的四种 kind。blocked 迁移带 reason。界面上没有创建任务的控件。

## WP-11 settings

**范围**

语言、主题、Proactive 面板入口；默认 provider、DeepSeek 的两个模型、三把 key 的写入。key 输入框不从存储回填。Proactive：开关、暂停、Check setup、行动未连接。

**拥有** `ios/Packages/NuumFeatureSettings/**` 的源文件和测试。

**依赖** `SettingsPort`、`SecretWriter`、`ProactivePort`。

**交出** 设置视图和 Proactive 视图。

**完成**

- 切换 provider 时模型 id 用 `DEFAULT_MODEL_ID`。空字符串调用删除。测试里的 `SecretWriter` 若被读回，测试失败。
- `actionsAvailable` 的展示来自 snapshot。

## WP-12 组合根

最后一个功能 PR。把实现装配起来，并让入口使用 shell。

**范围**

- `AppGraph` 按架构文档第 4 节构造。
- `InProcessTurnSupervisor`、`NoSync`、`LocalOnly` 放在 `App/Graph/`。
- 把 feature 放进 shell 的内容槽。
- 调试菜单不提供「打印 secrets」。假 `ModelPort` 若由 debug 开关注入，默认关闭，开关不出现在 release，实现只在 `Graph/`。

**拥有**

- `ios/App/Graph/**`
- WP-00 留下的入口画面。WP-00 和 WP-12 先后改这一个文件：占位整文件替换。两者不并行编辑。

**依赖** WP-01 到 WP-11 的公开类型都已经在主干。

**完成**

- 模拟器上能：创建一个 Nunu、没有 key 时看到 `2004`、写入假 key 后确认容器里没有明文 secret 文件、打开 Room 并升级、打开设置和 Proactive 且行动状态为未连接。
- 组合根的 denied 刻法与 `DeniedRoots.kt` 相同：转录、memory、`settings.json` 仍被拒绝；scratch 和当前 project 不被拒绝；秘密路径放进例外也刻不掉。
- 真模型不进这次验收。

## WP-13 验收

**范围**

模拟器上的端到端场景。清单以 `android/docs/acceptance/SCENARIOS.md` 的 1–12 为口径，把 Android 特有的步骤换成 iOS 的等价物（Keychain 而不是 `secrets.bin`，document picker 而不是 SAF，没有 `adb backup`）。失败写成清单里的缺陷，修复回到拥有该模块的人。

**拥有**

- `ios/Packages/NuumAcceptance/**`
- `ios/docs/acceptance/**`

**依赖** WP-00 之后就可以提交测试空壳和清单。全量执行等 WP-12，并且在 Mac 上。

**完成**

- 清单上每条都有一次模拟器记录：通过，或带日志的失败。
- 不修改 `packages/`、`apps/`、`android/`。

## 冲突与接口变更

| 情况 | 做法 |
| --- | --- |
| 两个 feature 都要一个控件 | 控件留在先用到它的那个 package，另一个复制一小段，直到 WP-12 之后有单独的重构。不要新建共享 UI package，那会把所有界面 PR 串起来 |
| 契约少了一个方法 | 向脚手架提一个只改 `NuumContracts` 的小 PR。功能 PR 不夹带契约修改 |
| 设计规格和 Mac 行为不一致 | 以 Mac 代码为准，改规格 |
| 规格和 Android 已经落地的 `turn.context` 行为不一致 | 以 `android/docs/acceptance/SCENARIOS.md` 为准。不在功能 PR 里偷偷补轮中压缩 |

## 不在任何包里的事

- 不移植 executor、`sandbox-runtime`、bash、`rg`。
- 不加登录、后端、同步、云端执行、iCloud、WidgetKit、推送。
- 不加 Datadog 或其他观测 SDK，不加金融 SDK，不加 LLM SDK。
- 不实现 `TODO.md` 的三项。
- 不改 Mac 应用，不改 `android/` 的源码、Gradle 和 CI。
- 不在本份文档 PR 里开始 WP-00 或其后的任何包。
