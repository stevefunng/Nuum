# Room / NunuBar 架构

> 2026-10-15。按已审阅的简化方案实施；替换旧版接收水位、递归补派及 outbox 方案。实际验证及边界见 [implementation.md](./implementation.md)，设计理由见 [v2-redesign-plan.md](./v2-redesign-plan.md)。跨用户留到 V3。

## 领域与会话

Room 是本地讨论底座；升级为 NunuBar 保留房间 ID、成员和历史，增加卡片工作能力。成员关系由 Room 保存，同一 Nunu 可加入多个房间。

执行卡片的仍是同一个 Nunu。私聊、Room 和 NunuBar 普通讨论复用主 session；卡片按房间、卡片、参与 Nunu 和成员代际建立独立可恢复 session，位于 `work-sessions/<room hash>/<sessionId>/`。卡片 JSONL、压缩记录及工具审批不进入私人历史；公开摘要进入房间，主 session 下次收到它。

所有 session 共用该 Nunu 的一个执行槽。不同 Nunu 可并行，但活动 run 的共享 project root（包括父子目录）串行。这个约束不等于后台进程或任意外部资源锁；未知副作用不自动重放。

## 三个独立问题

| 问题 | 真源及实现 |
|---|---|
| 气泡顺序与客户端同步 | Host 串行追加 Work timeline 并分配连续 `seq`；客户端 `RoomSnapshotReplica` 保存完整快照和 `appliedThroughSeq` |
| 模型收到哪些房间内容 | session JSONL 中的房间来源、输入范围与 compact epoch；连续性从有效历史派生 |
| 谁接着执行 | 普通有界 async 循环及现有 `AgentScheduler`；只记录业务来源和执行开始／结束证据 |

同步水位只表示客户端已完整应用的日志前缀，不是 agent 已读、已回应或任务完成。没有第二套持久讨论状态机，不保存轮次／成员下标，不建设 outbox/inbox。

## 顺序与同步水位

- 房间权威 Host 按追加顺序分配 `seq`，时间戳不参与排序。卡片、聊天和执行记录共用序列。
- `workGet` 的 `throughSeq` 来自同一次读取的日志前缀。聊天只是投影，因此气泡序号有间隔正常。
- 每个 renderer 是独立 replica，以 roomId 保存快照及水位。接收路径验证完整连续前缀、同序号事件身份、版本及当前房间归属；旧快照不能回退新投影，另一房间的响应不能覆盖当前房间。
- 当前没有持久客户端缓存，水位随快照保存在内存，重开重新拉完整快照。禁止只保存水位数字。
- `clientEventId` 用于请求重试；同身份同内容返回原事件，不同内容报冲突。
- 完整坏行报错；撕裂尾行先备份再恢复有效追加边界，不跳过坏行继续分配序号。

未来 V3 仍由一个房间权威写入点排序；每台设备有独立 replica 水位，增量只应用连续前缀，遇缺口补齐。远端传输、权限过滤覆盖证明与增量重排没有在 V2 实现。

## Grokbot 式本地讨论

依据本地参考仓 `source/host/groups/group-chat.ts` 与 `source/host/extensions/transcript/group-chat-orchestrator.ts`，策略集中在 `packages/host/src/room-discussion.ts`，Runtime 只负责顺序 await 和执行入口。

| 输入 | 行为 |
|---|---|
| Room 或 NunuBar 用户无 @ | 全体有发言权限成员参与 |
| 用户提及 | 选择被提及成员；`@all` / `@everyone` 为全员 |
| 当前讨论的 agent 提及 | 下一轮按累计提及重算成员，不递归派发 |
| 卡片摘要 | 按序公开，不另开全员讨论、不增加讨论预算 |
| worker 回报 | 只接续固定负责人卡片 session |

最多三轮、全场十条公开消息、每成员每次两条；每轮轮换起点，整轮沉默结束。pass 不公开，公开入口在写入前检查额度。失败成员本场不重试，错误通过中断提示可见；重名歧义要求完整名字或结构化成员选择。

新用户补充使尚未开始的旧步骤失效；正在执行的成员可完成并公开，然后切换到合并的新输入。尚未开始任何成员的旧批次合入下一批，避免丢掉先前提及。显式停止则取消后续步骤并拒绝当前执行迟到公开写入。

重启不恢复循环位置。已开始但无确定结果的讨论显示中断，用户继续开启一场新的有界讨论；从未开始的有效输入可排队。

## 群聊 context 与 compact

群聊输入持久进入 Nunu 主 session，成为其参与经历。取最新 user/wake 来源而不是 JSONL 最后一条工具或 assistant 记录：同一房间、成员 revision 相同、compact epoch 未改变才视为连续群聊，只追加上次输入之后的新增公开消息。首次进入、经过私聊或其他房间、compact 后、旧记录缺少 epoch 时，提供最近 24 条公开背景；本次触发的用户消息即使落在窗口外也补入。历史背景与当前触发明确区分，不假装读过窗口外全部消息。

卡片使用独立 session，不打断主 session 连续性。输入准备期间发生 compact 时重新构造背景。输入正文和来源标记在同一 JSONL 记录中提交，取消旧的永久接收索引；`cursors.json` 不再读写，旧 compact.roomInputs 仅兼容解析，不能阻止重新提供历史。客户端同步水位不受影响。

主 session、卡片共用通用压缩机制。Host 在启动前预检，Kernel 在每次模型请求前等待 Host 检查并在安全边界更新 context。压缩以固定前缀、session 和 epoch 为依据，保留期间新增事件；近期请求及长 run 的当前请求原文保留。摘要按房间区分决定、承诺、待办和消息引用，不承诺无损记忆。超预算且压缩失败时停止模型请求，不自动重跑工具。具体边界、阈值和验证见 [compact 管线](./compact-pipeline.md)。

个人会话只显示“参与群聊：房间名”，内部 Trigger prompt 不公开显示；完整输入和来源仍保存在 JSONL。群聊重新提供背景会有意重复历史正文，但不会重复追加公开气泡。

## 卡片与恢复

创建卡片的 Nunu 固定负责；用户创建的卡片沿用现有负责人认领能力。用户或获准 Nunu 可派 worker；一张卡片最多一个未结清委派。派工不转移负责人。

worker 用 SendMessage 提交结果：公开摘要、卡片变化和回报关系在同一事件中提交，再接续负责人独立 session。worker review 保持进行中，负责人 review 进入人工验收。blocked 只能由用户确认解除。派工、交付或每次发言达到上限后 Kernel 结束当前 turn，释放槽位。

业务事件就是执行来源。`execution.started` 在调用模型／工具前持久化，`execution.finished` 记录结论。启动时一次核对：未开始且仍有效的来源可执行；已开始但不确定、失败或卡片没有交付则显示继续入口；取消、过期来源和已提交结果不自动重跑。用户继续复用原卡片 session，并创建明确的新请求。公开结果使用版本及当前来源校验，迟到旧结果不能覆盖新卡片。

迁移备份旧 timeline 和 cursor 文件，记录一次 `history.imported`；旧不确定输入要求用户继续。旧 dispatch 事件仅兼容读取，不再写新 dispatch 链；旧 cursor 不迁成客户端同步水位。旧私人混合历史不自动拆分或删除。
