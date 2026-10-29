package com.nuum.storage

/** Agent list row. The file `agents/<id>/profile.json` is the source; this is a projection. */
data class AgentListEntry(
    val id: String,
    val name: String,
    val description: String,
    val createdAt: Long,
    val tags: List<String>,
    val avatarColor: String?,
    val avatarShape: String?,
    val avatarMaterial: String?,
    val hiddenFromSidebar: Boolean,
    val lastActivityAt: Long
)

/** Work list row projected from `works/<id>/profile.json` plus the timeline tail. */
data class WorkListEntry(
    val id: String,
    val name: String,
    val description: String,
    val projectRoot: String?,
    val createdAt: Long,
    val kind: String?,
    val avatar: String?,
    val workspaceId: String?,
    val lastActivityAt: Long,
    val preview: String?
)

/** Task list row folded from `works/<id>/timeline.jsonl`. The timeline stays the source. */
data class TaskListEntry(
    val workId: String,
    val taskId: String,
    val title: String,
    val state: String,
    val updatedAt: Long,
    val assigneeIds: List<String>,
    val ownerAgentId: String?,
    val revision: Int
)

/** Sidebar group projected from global `settings.json`, not from DataStore. */
data class SidebarSectionEntry(
    val id: String,
    val name: String,
    val agentIds: List<String>,
    val isCollapsed: Boolean
)
