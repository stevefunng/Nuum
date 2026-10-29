package com.nuum.feature.shell.i18n

import com.nuum.contracts.Language

/**
 * Shell copy. Keys match `packages/ui/src/i18n/messages.ts`.
 * Unknown keys pass through, so a host sentence stays in English.
 */
internal class Copy(val language: Language) {
    fun t(key: String, vararg values: Pair<String, Any>): String {
        val row = MESSAGES[key]
        val template = when (language) {
            Language.EN -> row?.en ?: key
            Language.ZH_CN -> row?.zh ?: key
        }
        var text = template
        for ((name, value) in values) text = text.replace("{$name}", value.toString())
        return text
    }
}

private class Row(val zh: String, val en: String)

private fun r(zh: String, en: String) = Row(zh, en)

private val MESSAGES: Map<String, Row> = mapOf(
    "Nunu color" to r("Nunu 颜色", "Nunu color"),
    "Create" to r("创建", "Create"),
    "Creating…" to r("创建中…", "Creating…"),
    "Honey" to r("蜂蜜", "Honey"),
    "Rose" to r("柔粉", "Rose"),
    "Mist blue" to r("雾蓝", "Mist blue"),
    "Lilac" to r("淡紫", "Lilac"),
    "Peach" to r("杏桃", "Peach"),
    "Sage" to r("鼠尾草绿", "Sage"),
    "Cream" to r("奶油", "Cream"),
    "Give your Nunu a name" to r("给你的 Nunu 起个名字", "Give your Nunu a name"),
    "Nunu name" to r("Nunu 名称", "Nunu name"),
    "Remembered commands ({count})" to r("已记住的命令（{count}）", "Remembered commands ({count})"),
    "Network access requires your approval." to r("需要联网时会请求你的允许。", "Network access requires your approval."),
    "Denied by default" to r("默认禁止", "Denied by default"),
    "Tool network" to r("工具网络", "Tool network"),
    "Revoke" to r("撤销", "Revoke"),
    "Former room" to r("已离开的房间", "Former room"),
    "Allow inside sandbox" to r("沙箱内允许", "Allow inside sandbox"),
    "Command execution" to r("命令执行", "Command execution"),
    "Room tasks use the shared room workspace." to r("房间任务使用对应房间的共享目录。", "Room tasks use the shared room workspace."),
    "Open folder" to r("打开文件夹", "Open folder"),
    "Personal workspace" to r("个人工作区", "Personal workspace"),
    "Workspace and permissions" to r("工作区与权限", "Workspace and permissions"),
    "Permission applies only to this Nunu and workspace." to r(
        "授权仅适用于这个 Nunu 和当前工作区。",
        "Permission applies only to this Nunu and workspace."
    ),
    "Greet {name}" to r("和 {name} 打招呼", "Greet {name}"),
    "Created on" to r("创建日期", "Created on"),
    "Could not save. Please try again." to r("保存失败，请重试。", "Could not save. Please try again."),
    "Saving…" to r("保存中…", "Saving…"),
    "Nunu identity" to r("Nunu 身份", "Nunu identity"),
    "Recommended templates" to r("推荐模板", "Recommended templates"),
    "Research, sources" to r("研究、资料", "Research, sources"),
    "Projects, follow-ups" to r("项目、跟进", "Projects, follow-ups"),
    "Daily tasks, reminders" to r("日常事务、提醒", "Daily tasks, reminders"),
    "Edit profile" to r("编辑资料", "Edit profile"),
    "Click to edit profile" to r("点击编辑资料", "Click to edit profile"),
    "Finish" to r("完成", "Finish"),
    "Close profile" to r("收起资料栏", "Close profile"),
    "Open {name} profile" to r("打开 {name} 的资料", "Open {name} profile"),
    "Name" to r("名称", "Name"),
    "Name cannot be empty." to r("名称不能为空。", "Name cannot be empty."),
    "Tags (optional)" to r("标签（可选）", "Tags (optional)"),
    "Research, design, operations" to r("研究、设计、运营", "Research, design, operations"),
    "Description" to r("描述", "Description"),
    "What should this Agent do?" to r("这个 Nunu 负责什么？", "What should this Nunu do?"),
    "Sidebar actions" to r("侧栏操作", "Sidebar actions"),
    "Create new Nunu" to r("创建新 Nunu", "Create new Nunu"),
    "Create NunuBar" to r("创建 NunuBar", "Create NunuBar"),
    "Close group dialog" to r("关闭分组窗口", "Close group dialog"),
    "Group name" to r("分组名称", "Group name"),
    "Cancel" to r("取消", "Cancel"),
    "Save" to r("保存", "Save"),
    "Resize sidebar" to r("调整侧栏宽度", "Resize sidebar"),
    "Could not save sidebar changes. Please try again." to r(
        "侧栏设置保存失败，请重试。",
        "Could not save sidebar changes. Please try again."
    ),
    "Back" to r("返回", "Back"),
    "Unassigned" to r("未分配", "Unassigned"),
    "New group…" to r("新建分组…", "New group…"),
    "Unpin" to r("取消置顶", "Unpin"),
    "Pin" to r("置顶", "Pin"),
    "Move to group" to r("移至分组", "Move to group"),
    "Move to new group" to r("移至新分组", "Move to new group"),
    "Copy Agent ID" to r("复制 Nunu ID", "Copy Nunu ID"),
    "Could not copy Agent ID." to r("无法复制 Nunu ID。", "Could not copy Nunu ID."),
    "Rename group…" to r("重命名分组…", "Rename group…"),
    "Move up" to r("上移", "Move up"),
    "Move down" to r("下移", "Move down"),
    "Ungroup agents" to r("解散分组", "Ungroup Nunu"),
    "New Agent" to r("新 Nunu", "New Nunu"),
    "Working" to r("工作中", "Working"),
    "Agents" to r("Nunu", "Nunu"),
    "New" to r("新建", "New"),
    "New agent" to r("新建 Nunu", "New Nunu"),
    "Search" to r("搜索", "Search"),
    "拖到此处置顶" to r("拖到此处置顶", "Drop here to pin"),
    "Agent list" to r("Nunu 列表", "Nunu list"),
    "Pinned Agents" to r("置顶 Nunu", "Pinned Nunu"),
    "Drag an Agent here" to r("将 Nunu 拖到此处", "Drag a Nunu here"),
    "No agents yet" to r("还没有 Nunu", "No Nunu yet"),
    "No matching agents" to r("未找到匹配的 Nunu", "No matching Nunu"),
    "New Work" to r("新建 NunuBar", "New NunuBar"),
    "Settings" to r("设置", "Settings"),
    "Rename group" to r("重命名分组", "Rename group"),
    "New group" to r("新建分组", "New group"),
    "Deny" to r("拒绝", "Deny"),
    "Close dialog" to r("关闭窗口", "Close dialog"),
    "No workspace selected" to r("未选择工作目录", "No workspace selected"),
    "Actions for {name}" to r("{name} 的操作", "Actions for {name}"),
    "now" to r("刚刚", "now"),
    "{count}m" to r("{count} 分钟", "{count}m"),
    "{count}h" to r("{count} 小时", "{count}h"),
    "{count}d" to r("{count} 天", "{count}d"),
    "Track a topic, read sources, and bring back concise findings." to r(
        "跟进主题、查阅资料，并提炼研究结果。",
        "Track a topic, read sources, and bring back concise findings."
    ),
    "Stay with one project, remember decisions, and help move it forward." to r(
        "持续跟进项目，记住决策，协助推进。",
        "Stay with one project, remember decisions, and help move it forward."
    ),
    "Handle recurring local tasks and keep an eye on follow-ups." to r(
        "处理日常本地任务，跟进待办事项。",
        "Handle recurring local tasks and keep an eye on follow-ups."
    ),
    "Researcher" to r("研究伙伴", "Researcher"),
    "Project partner" to r("项目伙伴", "Project partner"),
    "Daily operator" to r("日常助手", "Daily operator"),
    "black" to r("黑", "black")
)
