import NuumContracts

/// `messages.ts` columns. The lookup key is the object key. `en` is shown only when it differs from that key.
enum WorkCopy {
    static let roomResponseFailed = "A room response failed. Check the model settings and dispatch again."
    static let hostError = "Host error"
    static let importFailed = "Could not import. Check the path and try again."
    static let enterToolName = "Enter at least one tool name."
    static let noMessages = "No messages yet."
    static let noTasks = "No tasks"
    static let noDeliverables = "暂无产物"
    static let noDeliverableFiles = "该任务还没有交付文件。"
    static let deliverablesHint = "Agent 团队交付的文件会汇集在这里。"
    static let enableTaskBoard = "Enable task board"
    static let stopDiscussion = "Stop discussion"
    static let createWork = "Create Work"
    static let waitingForApproval = "Waiting for approval"

    static func text(_ key: String, language: Language, _ pairs: [String: String] = [:]) -> String {
        let line = table[key]
        var value: String
        switch language {
        case .zhCN:
            value = line?.zhCN ?? key
        case .en:
            value = line?.en ?? key
        }
        for (name, replacement) in pairs {
            value = value.replacingOccurrences(of: "{\(name)}", with: replacement)
        }
        return value
    }

    private struct Line {
        var zhCN: String
        var en: String?
    }

    private static let table: [String: Line] = [
        "A place for the job, not another chat": Line(zhCN: "一起完成工作的地方", en: nil),
        "Create a Work": Line(zhCN: "创建 NunuBar", en: "Create a NunuBar"),
        "Keep tasks, shared discussion, Agents, capabilities, and deliverables together.": Line(
            zhCN: "汇集任务、团队讨论、Nunu、能力和产物。",
            en: "Keep tasks, shared discussion, Nunu, capabilities, and deliverables together."
        ),
        "Local room": Line(zhCN: "本地群聊", en: nil),
        "Name": Line(zhCN: "名称", en: nil),
        "e.g. Product launch": Line(zhCN: "例如：产品发布", en: nil),
        "Cancel": Line(zhCN: "取消", en: nil),
        "Create Work": Line(zhCN: "创建 NunuBar", en: "Create NunuBar"),
        "Name cannot be empty.": Line(zhCN: "名称不能为空。", en: nil),
        "Enable task board": Line(zhCN: "升级为 NunuBar", en: nil),
        "Stop discussion": Line(zhCN: "停止讨论", en: nil),
        "Blocked": Line(zhCN: "阻塞中", en: nil),
        "Shared room": Line(zhCN: "团队聊天", en: nil),
        "Close shared room": Line(zhCN: "收起团队聊天", en: nil),
        "Shared room messages": Line(zhCN: "团队聊天消息", en: nil),
        "No messages yet.": Line(zhCN: "暂无消息。", en: nil),
        "Agent": Line(zhCN: "Nunu", en: "Nunu"),
        "Agents": Line(zhCN: "Nunu", en: "Nunu"),
        "Message the Work": Line(zhCN: "给 NunuBar 发消息", en: "Message the NunuBar"),
        "Message the Work…": Line(zhCN: "给 NunuBar 发消息…", en: "Message the NunuBar…"),
        "Post message": Line(zhCN: "发送消息", en: nil),
        "Continue": Line(zhCN: "继续", en: nil),
        "Use less room history": Line(zhCN: "选择较短的群聊上下文", en: nil),
        "Only include the most recent messages": Line(zhCN: "仅包含最近的消息条数", en: nil),
        "Continue with this history": Line(zhCN: "仅用这些消息继续", en: nil),
        "Remove {name}": Line(zhCN: "移除 {name}", en: nil),
        "Status of {name}": Line(zhCN: "{name} 的当前状态", en: nil),
        "Working on card": Line(zhCN: "正在处理卡片", en: nil),
        "Idle": Line(zhCN: "空闲", en: nil),
        "Run failed": Line(zhCN: "执行出错", en: nil),
        "Discussing": Line(zhCN: "正在讨论", en: nil),
        "Working in another session": Line(zhCN: "正在其他会话工作", en: nil),
        "拖到此处以添加Nunu到当前NunuBar": Line(zhCN: "拖到此处以添加Nunu到当前NunuBar", en: "Drop here to add the Nunu to this NunuBar"),
        "Release to add Agent": Line(zhCN: "松开以添加 Nunu", en: "Release to add Nunu"),
        "Drop outside to remove": Line(zhCN: "拖出此区域即可移除", en: nil),
        "Discussion interrupted. Continue starts a new bounded discussion.": Line(zhCN: "讨论已中断。点击继续将开启新一轮讨论。", en: nil),
        "Execution interrupted. Check tools and published results before continuing.": Line(zhCN: "执行已中断。请核对已执行的操作和已发布的结果，再继续。", en: nil),
        "Execution failed. Check the result before continuing.": Line(zhCN: "执行失败，请检查结果后继续。", en: nil),
        "Card execution ended without a handoff. Continue or cancel the card.": Line(zhCN: "本轮执行已结束，但尚未提交卡片结果。可继续执行或取消卡片。", en: nil),
        "Legacy execution requires confirmation before continuing.": Line(zhCN: "旧版本执行记录已保留，确认后才能继续。", en: nil),
        "Previous room history is preserved. Continue only if this discussion still needs a response.": Line(zhCN: "旧房间记录已保留。如仍需回应，可点击继续。", en: nil),
        "Room context is too large. No new room input was consumed; narrow the history range before continuing.": Line(zhCN: "群聊上下文过长，尚未加入新的历史。请选择较短的群聊上下文后继续。", en: nil),
        "A room response failed. Check the model settings and dispatch again.": Line(zhCN: "有一轮房间回应失败，请检查模型设置后重新派工。", en: nil),
        "This card is paused until you confirm how to proceed.": Line(zhCN: "卡片已暂停，等待你确认后继续。", en: nil),
        "切换到产物": Line(zhCN: "切换到产物", en: "Switch to deliverables"),
        "切换到 Tasks": Line(zhCN: "切换到任务", en: "Switch to tasks"),
        "Tasks": Line(zhCN: "任务", en: nil),
        "产物": Line(zhCN: "产物", en: "Deliverables"),
        "Proposed": Line(zhCN: "待确认", en: nil),
        "Ready": Line(zhCN: "待开始", en: nil),
        "In progress": Line(zhCN: "进行中", en: nil),
        "Review": Line(zhCN: "待验收", en: nil),
        "Done": Line(zhCN: "已完成", en: nil),
        "Cancelled": Line(zhCN: "已取消", en: nil),
        "{state} tasks": Line(zhCN: "{state}的任务", en: nil),
        "No tasks": Line(zhCN: "暂无任务", en: nil),
        "Task states": Line(zhCN: "任务状态", en: nil),
        "Open task: {title}": Line(zhCN: "打开任务：{title}", en: nil),
        "Unassigned": Line(zhCN: "未分配", en: nil),
        "{count} files": Line(zhCN: "{count} 个文件", en: nil),
        "暂无产物": Line(zhCN: "暂无产物", en: "No deliverables yet"),
        "该任务还没有交付文件。": Line(zhCN: "该任务还没有交付文件。", en: "This task has no delivered files yet."),
        "Agent 团队交付的文件会汇集在这里。": Line(zhCN: "Nunu 团队交付的文件会汇集在这里。", en: "Files delivered by the Nunu team will appear here."),
        "File": Line(zhCN: "文件", en: nil),
        "复制路径": Line(zhCN: "复制路径", en: "Copy path"),
        "已复制": Line(zhCN: "已复制", en: "Copied"),
        "无法复制，请选择上方路径手动复制。": Line(zhCN: "无法复制，请选择上方路径手动复制。", en: "Could not copy. Select the path above and copy it manually."),
        "Close dialog": Line(zhCN: "关闭窗口", en: nil),
        "Card owner": Line(zhCN: "卡片负责人", en: nil),
        "Workers": Line(zhCN: "执行成员", en: nil),
        "Priority": Line(zhCN: "优先", en: nil),
        "Low": Line(zhCN: "低", en: nil),
        "Normal": Line(zhCN: "普通", en: nil),
        "High": Line(zhCN: "高", en: nil),
        "Urgent": Line(zhCN: "紧急", en: nil),
        "Acceptance criteria": Line(zhCN: "验收标准", en: nil),
        "Blocked:": Line(zhCN: "阻塞原因：", en: nil),
        "Confirm and resume": Line(zhCN: "确认并恢复", en: nil),
        "Cancel task": Line(zhCN: "取消卡片", en: nil),
        "Request changes": Line(zhCN: "退回修改", en: nil),
        "Accept delivery": Line(zhCN: "验收通过", en: nil),
        "Execution history": Line(zhCN: "执行记录", en: nil),
        "No execution history yet.": Line(zhCN: "还没有执行记录。", en: nil),
        "Load earlier": Line(zhCN: "加载更早记录", en: nil),
        "Choose worker": Line(zhCN: "选择执行 Nunu", en: nil),
        "Instruction for the Agent": Line(zhCN: "给 Nunu 的指令", en: "Instruction for the Nunu"),
        "Run": Line(zhCN: "开始执行", en: nil),
        "Capabilities": Line(zhCN: "能力", en: nil),
        "Add capability": Line(zhCN: "添加能力", en: nil),
        "Local tool": Line(zhCN: "本地工具", en: nil),
        "Resize Work inspector": Line(zhCN: "调整 NunuBar 信息栏宽度", en: "Resize NunuBar inspector"),
        "Resize capabilities and agents": Line(zhCN: "调整能力与 Nunu 区域", en: "Resize capabilities and Nunu"),
        "Skills, tools and knowledge for this Work.": Line(
            zhCN: "为这个 NunuBar 配置技能、工具和知识。",
            en: "Skills, tools and knowledge for this NunuBar."
        ),
        "Capability source": Line(zhCN: "能力来源", en: nil),
        "Discover": Line(zhCN: "发现", en: nil),
        "Import local": Line(zhCN: "本地导入", en: nil),
        "THE COLLECTION": Line(zhCN: "能力商店", en: nil),
        "Coming soon": Line(zhCN: "即将上线", en: nil),
        "KNOW-HOW": Line(zhCN: "工作方法", en: nil),
        "Skills": Line(zhCN: "技能", en: nil),
        "Thoughtful workflows.": Line(zhCN: "精心设计的工作流程。", en: nil),
        "Ready for your next task.": Line(zhCN: "为下一项任务做好准备。", en: nil),
        "Presets on the way": Line(zhCN: "预设即将上线", en: nil),
        "HANDS-ON": Line(zhCN: "动手执行", en: nil),
        "CLI tools": Line(zhCN: "命令行工具", en: nil),
        "Familiar tools.": Line(zhCN: "熟悉的工具。", en: nil),
        "A little more possibility.": Line(zhCN: "更多工作可能。", en: nil),
        "Already have something in mind?": Line(zhCN: "已经有想用的工具？", en: nil),
        "Bring a local Skill, CLI or knowledge folder.": Line(zhCN: "导入本地技能、命令行工具或知识目录。", en: nil),
        "Skill": Line(zhCN: "技能", en: nil),
        "CLI": Line(zhCN: "命令行工具", en: nil),
        "Knowledge": Line(zhCN: "知识库", en: nil),
        "Local tools": Line(zhCN: "本地工具", en: nil),
        "Enter at least one tool name.": Line(zhCN: "请至少输入一个工具名称。", en: nil),
        "Could not import. Check the path and try again.": Line(zhCN: "导入失败，请检查路径后重试。", en: nil),
        "e.g. Design review": Line(zhCN: "例如：设计评审", en: nil),
        "A short, recognizable name": Line(zhCN: "简短易辨识的名称", en: nil),
        "Skill manifest": Line(zhCN: "技能说明文件", en: nil),
        "Executable": Line(zhCN: "可执行文件", en: nil),
        "Knowledge folder": Line(zhCN: "知识目录", en: nil),
        "Tool names": Line(zhCN: "工具名称", en: nil),
        "Tool names, separated by commas": Line(zhCN: "工具名称，以逗号分隔", en: nil),
        "Allowed subcommands": Line(zhCN: "允许的子命令", en: nil),
        "e.g. status, diff, log": Line(zhCN: "例如：status, diff, log", en: nil),
        "Agents can read this folder. The source files stay in place.": Line(
            zhCN: "Nunu 可以读取此目录，源文件仍保留在原处。",
            en: "Nunu can read this folder. The source files stay in place."
        ),
        "Choose the folder containing SKILL.md, or enter its full path.": Line(zhCN: "选择包含 SKILL.md 的目录，或输入完整路径。", en: nil),
        "Use an installed executable. List the subcommands this Work can use.": Line(
            zhCN: "使用已安装的可执行文件，并列出此 NunuBar 允许使用的子命令。",
            en: "Use an installed executable. List the subcommands this NunuBar can use."
        ),
        "Add tools already registered in Nuum.": Line(zhCN: "添加已在 Nuum 注册的工具。", en: nil),
        "Importing…": Line(zhCN: "导入中…", en: nil),
        "Add to Work": Line(zhCN: "添加到 NunuBar", en: "Add to NunuBar"),
        "Browse": Line(zhCN: "浏览", en: nil),
        "Deny": Line(zhCN: "拒绝", en: nil),
        "Allow once": Line(zhCN: "单次允许", en: nil),
        "Always allow": Line(zhCN: "始终允许", en: nil),
        "Execution details": Line(zhCN: "执行详情", en: nil),
        "Allow {action}?": Line(zhCN: "允许{action}？", en: nil),
        "Dynamic commands require one-time approval": Line(zhCN: "此动态命令需要单次确认", en: nil),
        "read-file": Line(zhCN: "读取文件", en: nil),
        "list-directory": Line(zhCN: "列出目录", en: nil),
        "write-file": Line(zhCN: "写入文件", en: nil),
        "run-command": Line(zhCN: "执行命令", en: nil),
        "network": Line(zhCN: "工具联网", en: "tool network access"),
        "Waiting for approval": Line(zhCN: "等待确认", en: nil),
        "Host error": Line(zhCN: "服务出现错误", en: nil),
    ]
}
