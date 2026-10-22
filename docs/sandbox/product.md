# 工作区与授权产品规则

## 工作区归属

首次初始化建立系统文稿目录下的 `Nuum` 和 `Nuum/Rooms`。每个 Nunu 使用 `文稿/Nuum/<名称>`，房间成员执行房间任务时共享 `文稿/Nuum/Rooms/<房间名称>`。房间执行不自动获得个人目录权限。

目录绑定稳定身份，名称只用于首次目录命名。重名加后缀；改名不会自动移动目录。升级时已有 Nunu 统一使用新分配目录，原文件保留，不自动搬移或删除。共享目录不共享授权：同房间不同 Nunu 分别申请、分别保存规则。

资料卡下方的「工作区与权限」组件展示个人路径、打开目录、命令执行偏好、网络目标和本机操作授权，支持撤销。客户端设置不再维护当前 Nunu 的项目目录。NunuBar 不再包含 goal、独立设置菜单或右上角工作中计数；其他会话的运行状态显示不受此删除项影响。

## 审批交互

工作区内正常文件、搜索和 shell 执行无需逐条确认，仍受 OS 文件与网络限制。用户可以在资料卡禁用命令执行；禁用同时影响普通 shell 和外部 shell。

超出当前能力的操作由模型提供 `justification`，说明目的和必要性。界面突出理由；实际命令、cwd、路径及规则在可展开详情中展示。模型理由仅用于解释，不决定权限。

| 用户选择 | 行为 |
|---|---|
| 单次允许 | 批准当前外部操作，不保存长期规则 |
| 始终允许 | 保存当前 Nunu 的具体资源与操作规则，后续满足全部条件才复用 |
| 拒绝 | 结束当前请求；当前任务相同操作不重复询问，不形成永久黑名单 |

**网络单次授权的实际范围不同：** `request_network` 的单次允许会给当前执行上下文加入目标，直到上下文撤销，不是只允许一个 HTTP 请求。长期允许则保存该 Nunu、该 workspaceId 的网络目标。外部 shell 自带的 networkTargets 随其临时上下文结束，不反向扩大普通 shell 的网络权限。

## 外部文件与命令

模型使用 `external_operation`，将申请理由与实际操作字段分开。

| operation | 功能与限制 |
|---|---|
| read | 读取一个普通文件，输出上限 100 KB |
| import | 从外部复制单个普通文件到当前工作区 |
| export | 从当前工作区复制单个普通文件到外部目标 |
| shell | 在声明的 cwd、额外 readPaths/writePaths 和网络目标内运行一次命令 |

文件复制默认排他创建，不覆盖已有目标；精确文件申请可显式请求 overwrite。目录范围通过 `resourceRoot` 明确申请，不会由某次文件批准自动扩大；目录 export 只允许新增文件，不包含覆盖或删除。实际执行仍使用本次文件路径，不因目录授权就批量操作目录。

例如导出报告到桌面：模型提交 export、源文件、桌面目标和理由；用户单次允许后仅执行这次复制。若明确申请桌面某个报告目录并长期允许，则之后可向该目录导出不同新文件，但不能据此覆盖文件、删除桌面内容或读取其他桌面文件。

## 「始终允许」的判定

授权存于 Host 私有数据中的每 Nunu `settings.json.execution`，而非工具可写的工作区。`externalGrants` 保存本机操作，`networkGrants` 保存网络目标。旧 `commandGrants` 保留兼容，不转换成更宽的外部权限。

每次请求都重新生成规则，并同时检查：

1. 当前 Nunu 自己持有该授权；environment 为 local，workspaceId 相同。
2. 操作类别相同。读不能转写，import/export/shell 不能互换。
3. 精确文件的源与目标相同；明确的目录规则允许其子路径。请求不能自行从文件升级到目录。
4. cwd、读写路径集合、overwrite 语义及可执行文件/脚本摘要符合批准规则。
5. 请求网络目标属于规则已批准目标的子集；不因命令匹配而获得任意联网能力。
6. 命令规则匹配，且该请求可安全记忆。否则重新申请或仅支持单次批准。

长期命令规则不是根命令名单，也不保证换一个无害参数一定免审批：

| 命令类型 | 当前匹配方式 |
|---|---|
| git status | 仅识别 --short、--porcelain（含 =v1/=v2）、--branch、-s、-b 这些参数；符合语法时归一为 git status 规则 |
| gh pr view | 仅识别数字 PR、--comments、--json 的字段列表、--repo owner/repo；其余参数不泛化 |
| git log | --oneline、--graph、--all、--reverse、--no-merges、--first-parent、--no-decorate；-n/--max-count 的 1–9999 数量；不接受 -p、自定义格式、输出文件、revision/path 参数 |
| git diff | 必须同时有 --no-ext-diff 和 --no-textconv；可变 --stat、--name-only、--name-status、--numstat、--shortstat、--cached、--staged、--check；不接受额外路径、revision、外部 diff 或输出文件 |
| gh issue view | 一个正整数编号、--comments、--json、--repo |
| gh pr list / gh issue list | --limit（1–9999）、--state、--json、--repo；state 为 open/closed/all，PR 额外允许 merged |
| gh run list / gh run view | list 支持 --limit、--json、--repo；view 要求一个正整数编号，支持 --verbose、--json、--repo，不包含 --log/--web |
| 其他静态命令 | 保留完整命令精确匹配 |
| 简单 &&、\|\|、分号、管道链 | 每段形成规则；段数、顺序、连接符及各段规则均须一致 |
| 重定向、展开、命令替换等动态语法 | 不生成长期规则；「始终允许」不可用，只能单次批准 |

新增的有值选项支持 `--option value` 和 `--option=value`；不接受未知参数、缺失值或额外位置参数。既有精确命令授权保持精确，不因规则扩充自动迁移为命令族授权。

参数语义核对来源：[Git log](https://git-scm.com/docs/git-log)、[Git diff](https://git-scm.com/docs/git-diff)、[GitHub CLI 手册](https://cli.github.com/manual/)。Nuum 仅支持上表子集。

识别前缀并不单独构成授权：可执行文件必须可解析，直接文件参数和可执行文件需通过摘要检查。无法解析或无法建立摘要的调用可能只能单次批准。外部 shell 的 PATH 固定为系统路径；例如 Homebrew 的 gh 通常需要明确使用可执行文件绝对路径，并满足原有读取权限，规则识别不会自动安装或开放该程序。摘要不递归覆盖所有导入依赖；不将其描述为完整代码身份保证。

网络只接受精确主机和 80/443 端口。允许某主机不代表允许其他域名；跳转或其他服务目标需要相应权限。授权不提供关闭沙箱选项。

## 拒绝与撤销

拒绝按 Host 确定的用户任务隔离：私聊使用本次用户指令身份，讨论使用讨论身份，卡片使用卡片和最近一次用户明确派发/继续事件。模型自动重试或 agent 派发不会自行重置这个身份。

同一任务的同一操作即使换申请理由、调整对象字段顺序或普通静态命令的等价引号，也不会重新弹窗。新用户任务可重新申请。这里是规范化操作匹配，不是对任意改写命令进行语义等价证明。

拒绝结果与 permissionTaskKey 写入既有 JSONL，Host 恢复时重建当前任务拒绝记录。没有新增第二份会话日志或永久拒绝名单。

资料卡撤销长期规则会使旧执行上下文失效，后续请求重新检查。撤销不是仅隐藏 UI 条目，也不会回滚已经完成的文件修改。

## Tool 与提示词变化

- 新增 `external_operation`：operation、justification，以及操作所需的 source/destination、resourceRoot、command/cwd、readPaths/writePaths、networkTargets、overwrite。
- `request_network` 使用 target 和 justification，将理由与目标分离。
- 提示词说明工作区内自主执行、外部资源结构化申请、默认断网及拒绝后不得在同任务反复申请。
- `update_state` 不允许修改安全配置或工作区。
- 文件、搜索、普通 shell 与 RunWorkCLI 的执行位置统一经过 daemon；模型不持 Host 管理凭证。

本期没有让模型通过理由文本、tool 参数或提示词自行批准权限的路径。

## 验证与已知限制

现有验收覆盖 311 项包测试、Host 冒烟、类型与依赖检查、Desktop 构建；真实 Electron 中验证长期允许、导出、撤销、拒绝和重复请求拦截。Electron 模型响应使用确定性 fixture，执行链路与 OS 沙箱为真实实现，未使用正式用户数据做迁移验收。

当前仅本地 macOS；不支持全主目录授权、任意网络端口、动态命令长期批准或任意脱离进程组后代必然销毁。具体技术限制与恢复语义见[技术架构](architecture.md)。
