# Nuum Android PoC 工作包

目标是让不同的人同时做，合并时不改同一批文件。规则只有一条：除了脚手架，谁的包就只改谁的目录。契约不够用时，在自己的模块里加内部类型，把「要改 `:core:contracts`」记成给脚手架的一条后续，而不是直接改冻结文件。

设计依据是 [ANDROID_ARCHITECTURE.md](./ANDROID_ARCHITECTURE.md) 和 [NUUM_MACOS_ANALYSIS.md](./NUUM_MACOS_ANALYSIS.md)。

## 顺序

```text
WP-00 脚手架
   ├─ WP-D  设计          （只写 android/docs/design，可与 WP-00 并行）
   ├─ WP-01 protocol
   ├─ WP-02 security
   ├─ WP-03 storage
   ├─ WP-04 model
   ├─ WP-05 kernel        依赖 contracts 里的 ModelPort、ToolExecutor，不依赖 WP-04 的类
   ├─ WP-06 tools
   ├─ WP-07 agent         依赖 contracts，不依赖各实现的源文件
   ├─ WP-08 shell
   ├─ WP-09 conversation
   ├─ WP-10 work
   └─ WP-11 settings
WP-12 组合根             等 WP-02…WP-11 的公开构造函数都在
WP-13 验收               脚手架一落地就可以写夹具；全量场景等 WP-12
```

WP-01 到 WP-11 彼此不改同一个文件，可以同时开工。它们都只编译自己的模块，并用契约里的假实现做测试。WP-12 是唯一把它们 new 在一起的包。

## 冻结文件

WP-00 合并之后，下面这些文件只有脚手架的后续 PR 能改：

- `android/settings.gradle.kts`
- `android/build.gradle.kts`
- `android/gradle/libs.versions.toml`
- `android/gradle.properties`
- `android/gradle/wrapper/**`
- `android/.gitignore`（若需要）
- `android/core/contracts/**`
- `.github/workflows/android.yml`

功能包发现缺依赖时，在自己的 PR 描述里点名 catalog 别名。不要私自加版本号。

## WP-00 脚手架

必须第一个进主干。没有它，其他包没有模块边界。

**范围**

- Gradle 工程能 `./gradlew :app:assembleDebug` 和 `./gradlew test`，此时界面只有一个空的 `MainActivity`，显示应用名。
- 版本锁定为架构文档第 2 节的那一列。应用模块不要 apply `org.jetbrains.kotlin.android`；AGP 9 的 built-in Kotlin 会因此直接失败。Kotlin 2.4.21 通过根 `buildscript` classpath 抬升。
- 建好第 3 节的全部模块。除 `:app` 和 `:core:contracts` 外，每个模块只有 `build.gradle.kts` 和一个空的包占位，保证 `include` 能通过编译。
- `:core:contracts` 放上第 4 节和第 14 节的接口，以及 turn / 工具 / 事件的最小类型。接口方法可以先抛 `NotImplemented`，但签名要够 WP-07 和各 feature 编译。
- CI：JDK 21，跑 `./gradlew test assembleDebug`，并跑依赖方向检查。不启动模拟器。
- `android/README.md` 用十行说明如何构建。这是 Android 工程自己的说明，不改仓库根的 `README.md`。

**拥有**

- 上面的冻结文件。
- `android/app/src/main` 里除了 `graph/` 以外的骨架：`AndroidManifest.xml`、`NuumApplication`、空 `MainActivity`、备份和网络安全 XML、字符串名 `app_name`。
- `android/core/contracts/**`
- 各模块的 `build.gradle.kts`。功能包不改构建脚本；缺依赖走脚手架后续。

**交出的契约**

- `ModelPort`、`KernelPort`、`ToolExecutor`、`ToolBackend`、`SecretStore`、`AgentStore`（文件端口，不是 Room DAO）、`Clock`、`IdentityContext`、`SyncPort`、`TurnSupervisor`、`ProactiveSource`。
- `SettingsPort`、`SecretWriter`、`AgentPort`、`WorkPort`、`ProactivePort`、`DesktopPort`。
- `HostEvent` 密封类，名字与 `HostEvents` 一致。
- `NuumException(code, message)`。
- 依赖方向检查任务，失败即 CI 失败。

**依赖**

- 无。设计包可以并行写文档，因为它不编译。

**完成**

- 干净树里 `./gradlew :app:assembleDebug test` 通过。
- debug APK 能安装到 API 36 模拟器并画出 `MainActivity`。这一步由做脚手架的人在本机或本环境做一次，CI 不跑模拟器。
- `allowBackup=false`，存在 `dataExtractionRules`，cleartext 关闭。
- 契约里没有 Android UI 类型，`:core:protocol` 的构建脚本没有 `com.android.library`，它是纯 JVM。

## WP-D 设计

给一位 UI 设计师。不写 Kotlin，不改资源 XML。工程师按这份规格在自己的 feature 模块里实现。

**范围**

- 设计系统：颜色、字号、间距、圆角、暗色。来源是现有 sand token 和 `packages/ui/src/theme/runtime-theme-token-installer.ts`，不是一套新的 Material 主题命名。规格里写明每个 token 对应的现有 CSS 变量名。
- 屏幕规格，每屏一张：侧栏、空会话、有转录的会话、审批条、widget、附件、创建 Nunu、2D 开箱、资料、设置（通用 / 模型）、Room、NunuBar 泳道、能力目录、Proactive 面板。
- 每屏列出状态：空、加载、流式、错误、无 key、权限被拒、讨论中断。
- 手机宽度与大于 840 dp 的分栏。Mac 是 1200×800 的单窗口；Android 规格要说明抽屉如何替代侧栏，而不是把 1200 px 布局缩小。
- 动效：开箱在 `prefers-reduced-motion` 下直接到终态。不要求 3D。
- 资源预算：矢量优先。若必须要位图，单张 webp < 200 KB，并说明替代的是 `packages/ui/src/assets/nunu/` 里的哪一张。不要把那 9.4 MB 原样放进规格的「切图」里。
- 文案以 `packages/ui/src/i18n/messages.ts` 为准，规格引用 key，不另写一套产品名。

**拥有**

- `android/docs/design/**` 仅此目录。

**依赖**

- 无代码依赖。阅读分析文档即可开工，可与 WP-00 并行。

**交出**

- 工程师能按规格实现而不再问「这个按钮在哪」。每个交互都指回 Mac 上的一个现有行为，或者明确写成「Mac 上没有，Android 也不做」。

**完成**

- 上面的屏幕都有规格。
- 没有要求 PoC 做 3D、shell、菜单栏常驻、登录或同步。
- 不修改 `android/` 下除 `docs/design` 以外的路径。

## WP-01 protocol

**范围**

把 `packages/protocol/src` 里 PoC 会用到的 Zod 类型和纯函数搬成 Kotlin。包括 `domain.ts`、`transcript.ts`、`work.ts`、`product-tools.ts` 的参数校验、`context-budget.ts`、`permission-rules.ts` 的数据形状、`proactive.ts`、`attachments.ts` 的限额、`errors.ts` 的数字码。不包括桌面窗口方法。

**拥有**

- `android/core/protocol/src/**`

**依赖**

- WP-00 的模块。不依赖其他实现。

**交出**

- 可序列化的数据类型，JSON 字段名与现有文件一致。
- `estimateModelTokens`、`resolveAvailableModel`、`secretForProvider`、`discussionLimits` 若它被视作协议常量则放在 agent 包；协议包至少交出限额数字的单一来源。讨论限额今天在 `room-discussion.ts`，不在 protocol。协议包不要把它挪走就当已经存在。WP-07 拥有那三个数字。这里只拥有 protocol 文件里已经有的常量，例如附件限额、proactive 间隔上下界、`MAX_ATTACHMENTS`。
- SendMessage 的校验错误字符串保持英文，和现在回给模型的句子一致。

**完成**

- JVM 测试覆盖：provider 回退顺序、附件限额、侧栏组织的唯一性约束、任务状态枚举、`actionsAvailable` 只能是 false、token 估算对一张图加 8192。
- 模块没有 `android.*` import。

## WP-02 security

**范围**

`KeystoreSecretStore`。AES-256-GCM，alias `nuum.secrets`，文件在 `noBackupFilesDir/secrets.bin`。加密不可用时抛 `3001`，不写明文。

**拥有**

- `android/core/security/src/**`

**依赖**

- `SecretStore` 契约。

**交出**

- `SecretStore` 的实现类，构造函数接收 `Context`。

**完成**

- `androidTest`：写入后文件内容不是 JSON 明文；读回相等；`filesDir` 下不出现 `secrets.bin`。
- 单元测试里一个包装过的 writer，断言异常 message 不含测试 key。真 Keystore 不放在 JVM 测试里充数。

## WP-03 storage

**范围**

文件布局按架构文档第 6 节。原子写 JSON，append-only JSONL，坏尾行可恢复。Room 只存列表投影，并能从文件重建。DataStore 只存 UI 偏好：侧栏宽度、`nuum-identity-edited` 的等价物。

记忆文件的读写规则属于 WP-07 的领域；本包提供按路径读写字节和文本的 `AgentStore`，不解释 Markdown。

**拥有**

- `android/core/storage/src/**`

**依赖**

- `AgentStore` 契约、protocol 类型。

**交出**

- `FileAgentStore`。路径函数公开，测试可以对照 Mac 的相对路径。

**完成**

- 测试：原子写中途失败不损坏旧文件；JSONL 最后一行截断只丢该行；投影删除后能从 `profile.json` 重建列表；`settings.json` 往返不含任何 key 字段。

## WP-04 model

**范围**

OkHttp SSE。三个 provider 的请求和响应形状按 `packages/kernel/src/model/openai.ts` 与 `anthropic.ts`。DeepSeek 不上传图片。认证头可剥离。

**拥有**

- `android/core/model/src/**`

**依赖**

- `ModelPort`。不依赖 Kernel。

**交出**

- `OkHttpModelPort`，或三个类加一个 `selectModel` 函数，签名与 `router.ts` 相同：给 `ModelRef` 和 `Secrets`，返回端口和 key。缺 key 抛 `1007`。

**完成**

- `MockWebServer` 测试：OpenAI 工具调用增量拼接、`reasoning_content`、Anthropic `thinking_delta` 与 `input_json_delta`、非 200 变成 `1004` 且 message 里没有 key、取消后连接关闭。
- 日志夹具断言 `Authorization` 和 `x-api-key` 不出现。

## WP-05 kernel

**范围**

移植 `packages/kernel/src/loop.ts` 和 `summarize.ts` 的控制流。`MAX_ROUNDS = 16`，三种静默提醒的阈值和英文句子保持原样，取消不发 error，压缩水位 0.9 的失败句子保持原样。工具执行通过 `ToolExecutor`，不读文件系统。

**拥有**

- `android/core/kernel/src/**`

**依赖**

- `ModelPort`、`ToolExecutor`、`KernelPort`。用测试假对象，不等 WP-04。

**交出**

- `Kernel` 类，实现 `KernelPort`。

**完成**

- 移植 `loop.test.ts` 和 `summarize.test.ts` 里已经覆盖的情形：无工具则结束、委派工具等待结果、`endTurn`、轮数用尽的提示、取消、缺 key。不发网络。

## WP-06 tools

**范围**

范围内的文件工具和 `grep`。路径判定移植 `create-sandbox.ts` 的顺序：denied、readOnly、必须在 home 或 scratch 下、project 与 scratch 预批准、agent 目录只读、其余 `always | ask | never`。`shell`、`request_network`、`external_operation` 注册进表，但执行返回固定的「PoC 未实现」句子，不 spawn 进程。

SAF 的 `DocumentFile` 适配放在这个模块。没有 URI 权限时按「路径在允许根之外」拒绝。

**拥有**

- `android/core/tools/src/**`

**依赖**

- `ToolBackend` / `ToolExecutor` 契约。不依赖 agent。

**交出**

- `LocalToolBackend`。

**完成**

- 测试：`always` 仍读不到 secrets 路径；scratch 可写；agent memory 路径不可写；`grep` 遵守输出上限且不调用外部程序；`shell` 不创建进程（测试用一个会失败的 `ProcessBuilder` 探测器，或简单地断言实现类没有 `ProcessBuilder` 引用，由架构检查完成）。

## WP-07 agent

**范围**

Host 的领域行为：调度、wake、prompt 组装、记忆规则、压缩触发、转录投影、委派工具（除 `RunWorkCLI`）、Room 讨论限额、NunuBar 状态迁移、执行结果认领、proactive 的 snapshot 计算。系统提示词改掉「Mac / real shell」的环境句，其余段落保持。

`RunWorkCLI` 返回未实现。`actionsAvailable` 恒为 false。不注册 `ProactiveSource`。

**拥有**

- `android/core/agent/src/**`

**依赖**

- 契约：`KernelPort`、`AgentStore`、`SecretStore`、`ToolBackend`、`Clock`。不 import 那些实现类。

**交出**

- `HostRuntime`，实现 `SettingsPort`、`AgentPort`、`WorkPort`、`ProactivePort`。它不实现 `SecretWriter` 的界面逻辑；它在 turn 开始时向 `SecretStore` 要 `Secrets`，没有 key 就抛 `2004`。

**完成**

- 用内存版 `AgentStore` 和假 Kernel 测：并发上限 3、同 agent 不重叠、讨论轮数、记忆去重与 profile 100 条、压缩在 0.75 处触发且不直接 new 模型客户端、重启后 status 不是 running、wake 限额、`CreateAgent` 受 `MAX_AGENTS` 约束。

## WP-08 shell

**范围**

单 Activity 的导航结构、侧栏、抽屉、主题安装、创建 Nunu、2D 开箱、资料页里的身份展示。资料页里的执行偏好表单如果和设置共享控件，控件放在本模块的公开 Composable，由 WP-11 不重复实现；执行偏好的保存调用 `AgentPort`。为避免两个 feature 互相依赖，执行偏好 UI 放在本模块，设置模块不要引用它。

**拥有**

- `android/feature/shell/src/**`

**依赖**

- `AgentPort`、`SettingsPort`、`DesktopPort`、`WorkPort` 的只读列表（侧栏要显示 work）。假的 Port 放在本模块的 test fixture，不放进 contracts。

**交出**

- `NuumShell(ports, content)` Composable。中心槽由 `:app` 填入会话或 NunuBar。本模块不导航到那些屏幕的内部。

**完成**

- UI 测试：空侧栏、置顶、分组重名被协议拒绝时的展示、创建时只提交颜色加上一次随机外观、reduced motion 不开启动画时钟。
- 不读取 `filesDir`。

## WP-09 conversation

**范围**

一对一转录、输入框、停止、附件选择（调用 `DesktopPort` 选文件，字节交给 `AgentPort.send`）、审批条、widget、peer 抽屉、工具活动分组。pending 带 `workId` 时不在这里画审批条。

**拥有**

- `android/feature/conversation/src/**`

**依赖**

- `AgentPort`、`DesktopPort`。

**交出**

- `ConversationScreen(agentId, ports)`。

**完成**

- UI 测试：空状态、delta 追加、审批三个按钮的回调参数是 `deny` / `once` / `always`、widget 选项变成一次 `answerWidget`、超过 5 个附件时不调用 send。
- 不绘制 NunuBar。

## WP-10 work

**范围**

Room / NunuBar：创建、升级、共享聊天、成员、泳道、交付物、派发、状态迁移、中断后继续、目录的本地导入和禁用的发现页、成员自己的审批条。不提供用户建卡按钮。

**拥有**

- `android/feature/work/src/**`

**依赖**

- `WorkPort`、`AgentPort`（审批和打开成员）、`DesktopPort`（选 knowledge 根）。

**交出**

- `WorkScreen(workId, ports)` 和 `WorkCreation`。

**完成**

- UI 测试：room 升级请求的 kind 是 `work`；发现页不可点；导入只提交协议允许的四种 kind；blocked 迁移带 reason；界面上没有创建任务的控件。

## WP-11 settings

**范围**

设置两页：语言、主题、打开 Proactive 面板；默认 provider、DeepSeek 的两个模型、三把 key 的写入。key 输入框不从存储回填。Proactive：开关、暂停、Check setup、状态文案与 Mac 一致（行动未连接）。

**拥有**

- `android/feature/settings/src/**`

**依赖**

- `SettingsPort`、`SecretWriter`、`ProactivePort`。

**交出**

- `SettingsScreen`、`ProactiveScreen`。

**完成**

- UI 测试：切换 provider 时模型 id 用 `DEFAULT_MODEL_ID`；blur 空字符串调用删除；界面源码和测试输出都不出现从 Port 读回的 key（`SecretWriter` 测试假对象如果被读，测试失败）。
- `actionsAvailable` 的展示来自 snapshot，不在 UI 里写死一个会和协议打架的开关。

## WP-12 组合根

最后一个功能 PR。把实现装配起来，并让 `MainActivity` 使用 `NuumShell`。

**范围**

- `AppGraph` 按架构文档第 4 节 new 出全部对象。
- `InProcessTurnSupervisor`、`NoSync`、`LocalOnly` 若脚手架只留了接口，实现放在本包所拥有的 `graph/` 目录，保持一行就够的那些类不要散落到别的模块。
- 把 feature 屏幕放进 shell 的内容槽。
- 调试菜单不提供「打印 secrets」。

**拥有**

- `android/app/src/main/kotlin/**/graph/**`
- `android/app/src/main/kotlin/**/MainActivity.kt`（脚手架留下的空 Activity 由本包替换。为减少冲突，WP-00 把 `MainActivity.kt` 放在这个路径并在本文件头注释 `OWNED BY WP-12 AFTER SCAFFOLD`。其他人不要改它。）

WP-00 和 WP-12 会先后改 `MainActivity.kt`。这是唯一允许的交接：WP-00 合并时文件是占位，WP-12 整文件替换。两者不会并行编辑。

**依赖**

- WP-01 到 WP-11 的公开类型都已经在主干。

**完成**

- `assembleDebug` 的 APK 在 API 36 模拟器上能：创建一个 Nunu、在没有 key 时看到 `2004` 而不是崩溃、写入一把假 key 后对 Mock 不可用所以只验证 key 文件不是明文、打开 Room 并升级、打开设置和 Proactive 且行动状态为未连接。
- 真模型不进这次验收。假 `ModelPort` 可以由一个 debug 开关注入，默认关闭，开关不出现在 release。若这样做，开关的实现仍只在 `graph/`。

## WP-13 验收

**范围**

模拟器上的端到端场景和一份清单。修 bug 时不直接改功能模块来「让测试变绿」而不留记录；失败写成清单里的缺陷，修复回到拥有该模块的人。验收包只在测试代码无法表达意图时，才提出契约补充。

**拥有**

- `android/testing/acceptance/**`
- `android/docs/acceptance/**`（场景清单）

**依赖**

- WP-00 之后就可以提交仪器测试的空壳和清单。全量执行等 WP-12。

**场景**

1. 冷启动没有 running 的 Nunu。
2. 创建 Nunu：名字、颜色，形状和材质被写进 profile 且再次打开不变。
3. 无 key 发送，得到可理解的错误，转录里没有 key 字样。
4. 假模型流式返回一段文本加一次 `SendMessage`，界面只把 SendMessage 当正文，工具活动折叠。
5. 假模型请求 `write`，审批条出现；拒绝后模型收到拒绝；始终允许后下一次同类写不再询问，且仍然写不进 `secrets.bin`。
6. 附件超过限额时发送不发生。
7. Room 发言、升级为 NunuBar、泳道能看到模型 `CreateTask` 产生的卡。界面上没有手工建卡按钮。
8. 讨论中断后可以继续。
9. 杀掉进程再打开，状态不是 running；已完成的消息还在。
10. 设置切换语言和主题立即生效。Proactive 显示行动未连接。
11. `adb backup` 或备份规则检查：提取规则包含 secrets 排除。不在自动化里真正上传备份。
12. release 包体积 < 30 MB，且 `lib/` 下没有 `.so`。

**完成**

- 清单上每条都有一次模拟器记录：通过，或带日志的失败。
- 仪器测试至少覆盖 1、3、5、7、9 里能稳定自动化的部分。其余允许是脚本化的手工步骤，但必须写在 `android/docs/acceptance/`，不能只留在聊天里。
- 不修改 `packages/` 和 `apps/`。

## 冲突与接口变更

| 情况 | 做法 |
| --- | --- |
| 两个 feature 都要一个控件 | 控件留在先用到它的那个模块，另一个模块复制一小段，直到 WP-12 之后有单独的重构。不要新建 `:feature:common` 来共享，那会把所有 UI PR 串起来 |
| 契约少了一个方法 | 向 WP-00 的所有者提一个只改 `android/core/contracts` 的小 PR。功能 PR 不要夹带契约修改 |
| catalog 缺库 | 同样只改 `libs.versions.toml` 的小 PR |
| 设计规格和 Mac 行为不一致 | 以 Mac 代码为准，改规格，不改产品 |

## 不在任何包里的事

- 不移植 executor、`sandbox-runtime`、bash、`rg`。
- 不加登录、后端、同步、云端执行。
- 不实现 `TODO.md` 的三项。
- 不改 Mac 应用的任何文件。
