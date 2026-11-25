import NuumContracts

/// One line the shell can show. Catalog keys are translated. Host sentences are not in the catalog, so they pass through in English.
public struct CopyLine: Equatable, Sendable {
    public var key: String
    public var values: [String: String]

    public init(key: String, values: [String: String] = [:]) {
        self.key = key
        self.values = values
    }
}

/// Shell copy. Keys match `packages/ui/src/i18n/messages.ts`.
public struct ShellCopy: Equatable, Sendable {
    public var language: Language

    public init(language: Language) {
        self.language = language
    }

    public static let fallback = ShellCopy(language: .zhCN)

    public func text(_ key: String, _ values: [String: any CustomStringConvertible] = [:]) -> String {
        let row = ShellCatalog.messages[key]
        let template: String
        if let row {
            template = language == .en ? row.en : row.zh
        } else {
            template = key
        }
        var result = template
        for (name, value) in values {
            result = result.replacingOccurrences(of: "{\(name)}", with: String(describing: value))
        }
        return result
    }

    public func text(_ line: CopyLine) -> String {
        var values: [String: any CustomStringConvertible] = [:]
        for (name, value) in line.values {
            values[name] = value
        }
        return text(line.key, values)
    }
}

struct CatalogRow: Sendable {
    var zh: String
    var en: String
}

enum ShellCatalog {
    static let messages: [String: CatalogRow] = [
        "Nunu color": .init(zh: "Nunu 颜色", en: "Nunu color"),
        "Create": .init(zh: "创建", en: "Create"),
        "Creating…": .init(zh: "创建中…", en: "Creating…"),
        "Honey": .init(zh: "蜂蜜", en: "Honey"),
        "Rose": .init(zh: "柔粉", en: "Rose"),
        "Mist blue": .init(zh: "雾蓝", en: "Mist blue"),
        "Lilac": .init(zh: "淡紫", en: "Lilac"),
        "Peach": .init(zh: "杏桃", en: "Peach"),
        "Sage": .init(zh: "鼠尾草绿", en: "Sage"),
        "Cream": .init(zh: "奶油", en: "Cream"),
        "Give your Nunu a name": .init(zh: "给你的 Nunu 起个名字", en: "Give your Nunu a name"),
        "Nunu name": .init(zh: "Nunu 名称", en: "Nunu name"),
        "Remembered commands ({count})": .init(zh: "已记住的命令（{count}）", en: "Remembered commands ({count})"),
        "Network access requires your approval.": .init(zh: "需要联网时会请求你的允许。", en: "Network access requires your approval."),
        "Denied by default": .init(zh: "默认禁止", en: "Denied by default"),
        "Tool network": .init(zh: "工具网络", en: "Tool network"),
        "Revoke": .init(zh: "撤销", en: "Revoke"),
        "Former room": .init(zh: "已离开的房间", en: "Former room"),
        "Allow inside sandbox": .init(zh: "沙箱内允许", en: "Allow inside sandbox"),
        "Command execution": .init(zh: "命令执行", en: "Command execution"),
        "Room tasks use the shared room workspace.": .init(zh: "房间任务使用对应房间的共享目录。", en: "Room tasks use the shared room workspace."),
        "Open folder": .init(zh: "打开文件夹", en: "Open folder"),
        "Personal workspace": .init(zh: "个人工作区", en: "Personal workspace"),
        "Workspace and permissions": .init(zh: "工作区与权限", en: "Workspace and permissions"),
        "Permission applies only to this Nunu and workspace.": .init(zh: "授权仅适用于这个 Nunu 和当前工作区。", en: "Permission applies only to this Nunu and workspace."),
        "Local computer permissions": .init(zh: "本机访问授权", en: "Local computer permissions"),
        "Greet {name}": .init(zh: "和 {name} 打招呼", en: "Greet {name}"),
        "Created on": .init(zh: "创建日期", en: "Created on"),
        "Could not save. Please try again.": .init(zh: "保存失败，请重试。", en: "Could not save. Please try again."),
        "Saving…": .init(zh: "保存中…", en: "Saving…"),
        "Nunu identity": .init(zh: "Nunu 身份", en: "Nunu identity"),
        "Recommended templates": .init(zh: "推荐模板", en: "Recommended templates"),
        "Research, sources": .init(zh: "研究、资料", en: "Research, sources"),
        "Projects, follow-ups": .init(zh: "项目、跟进", en: "Projects, follow-ups"),
        "Daily tasks, reminders": .init(zh: "日常事务、提醒", en: "Daily tasks, reminders"),
        "Edit profile": .init(zh: "编辑资料", en: "Edit profile"),
        "Click to edit profile": .init(zh: "点击编辑资料", en: "Click to edit profile"),
        "Finish": .init(zh: "完成", en: "Finish"),
        "Close profile": .init(zh: "收起资料栏", en: "Close profile"),
        "Open {name} profile": .init(zh: "打开 {name} 的资料", en: "Open {name} profile"),
        "Name": .init(zh: "名称", en: "Name"),
        "Name cannot be empty.": .init(zh: "名称不能为空。", en: "Name cannot be empty."),
        "Tags (optional)": .init(zh: "标签（可选）", en: "Tags (optional)"),
        "Research, design, operations": .init(zh: "研究、设计、运营", en: "Research, design, operations"),
        "Description": .init(zh: "描述", en: "Description"),
        "What should this Agent do?": .init(zh: "这个 Nunu 负责什么？", en: "What should this Nunu do?"),
        "Sidebar actions": .init(zh: "侧栏操作", en: "Sidebar actions"),
        "Create new Nunu": .init(zh: "创建新 Nunu", en: "Create new Nunu"),
        "Create NunuBar": .init(zh: "创建 NunuBar", en: "Create NunuBar"),
        "Close group dialog": .init(zh: "关闭分组窗口", en: "Close group dialog"),
        "Group name": .init(zh: "分组名称", en: "Group name"),
        "Cancel": .init(zh: "取消", en: "Cancel"),
        "Save": .init(zh: "保存", en: "Save"),
        "Resize sidebar": .init(zh: "调整侧栏宽度", en: "Resize sidebar"),
        "Could not save sidebar changes. Please try again.": .init(zh: "侧栏设置保存失败，请重试。", en: "Could not save sidebar changes. Please try again."),
        "Back": .init(zh: "返回", en: "Back"),
        "Unassigned": .init(zh: "未分配", en: "Unassigned"),
        "New group…": .init(zh: "新建分组…", en: "New group…"),
        "Unpin": .init(zh: "取消置顶", en: "Unpin"),
        "Pin": .init(zh: "置顶", en: "Pin"),
        "Move to group": .init(zh: "移至分组", en: "Move to group"),
        "Move to new group": .init(zh: "移至新分组", en: "Move to new group"),
        "Copy Agent ID": .init(zh: "复制 Nunu ID", en: "Copy Nunu ID"),
        "Could not copy Agent ID.": .init(zh: "无法复制 Nunu ID。", en: "Could not copy Nunu ID."),
        "Rename group…": .init(zh: "重命名分组…", en: "Rename group…"),
        "Move up": .init(zh: "上移", en: "Move up"),
        "Move down": .init(zh: "下移", en: "Move down"),
        "Ungroup agents": .init(zh: "解散分组", en: "Ungroup Nunu"),
        "New Agent": .init(zh: "新 Nunu", en: "New Nunu"),
        "New Work": .init(zh: "新建 NunuBar", en: "New NunuBar"),
        "Working": .init(zh: "工作中", en: "Working"),
        "Agents": .init(zh: "Nunu", en: "Nunu"),
        "Agent list": .init(zh: "Nunu 列表", en: "Nunu list"),
        "New": .init(zh: "新建", en: "New"),
        "New agent": .init(zh: "新建 Nunu", en: "New Nunu"),
        "Search": .init(zh: "搜索", en: "Search"),
        "拖到此处置顶": .init(zh: "拖到此处置顶", en: "Drop here to pin"),
        "Pinned Agents": .init(zh: "置顶 Nunu", en: "Pinned Nunu"),
        "Drag an Agent here": .init(zh: "将 Nunu 拖到此处", en: "Drag a Nunu here"),
        "No agents yet": .init(zh: "还没有 Nunu", en: "No Nunu yet"),
        "No matching agents": .init(zh: "未找到匹配的 Nunu", en: "No matching Nunu"),
        "Settings": .init(zh: "设置", en: "Settings"),
        "Rename group": .init(zh: "重命名分组", en: "Rename group"),
        "New group": .init(zh: "新建分组", en: "New group"),
        "Deny": .init(zh: "拒绝", en: "Deny"),
        "Close dialog": .init(zh: "关闭窗口", en: "Close dialog"),
        "No workspace selected": .init(zh: "未选择工作目录", en: "No workspace selected"),
        "Actions for {name}": .init(zh: "{name} 的操作", en: "Actions for {name}"),
        "now": .init(zh: "刚刚", en: "now"),
        "{count}m": .init(zh: "{count} 分钟", en: "{count}m"),
        "{count}h": .init(zh: "{count} 小时", en: "{count}h"),
        "{count}d": .init(zh: "{count} 天", en: "{count}d"),
        "Track a topic, read sources, and bring back concise findings.": .init(zh: "跟进主题、查阅资料，并提炼研究结果。", en: "Track a topic, read sources, and bring back concise findings."),
        "Stay with one project, remember decisions, and help move it forward.": .init(zh: "持续跟进项目，记住决策，协助推进。", en: "Stay with one project, remember decisions, and help move it forward."),
        "Handle recurring local tasks and keep an eye on follow-ups.": .init(zh: "处理日常本地任务，跟进待办事项。", en: "Handle recurring local tasks and keep an eye on follow-ups."),
        "Researcher": .init(zh: "研究伙伴", en: "Researcher"),
        "Project partner": .init(zh: "项目伙伴", en: "Project partner"),
        "Daily operator": .init(zh: "日常助手", en: "Daily operator"),
        "black": .init(zh: "黑", en: "black"),
    ]
}
