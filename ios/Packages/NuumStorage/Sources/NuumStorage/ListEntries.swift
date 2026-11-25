/// Agent list row. `agents/<id>/profile.json` is the source; this is a projection.
public struct AgentListEntry: Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var createdAt: Int64
    public var tags: [String]
    public var avatarColor: String?
    public var avatarShape: String?
    public var avatarMaterial: String?
    public var hiddenFromSidebar: Bool
    public var lastActivityAt: Int64

    public init(
        id: String,
        name: String,
        description: String,
        createdAt: Int64,
        tags: [String],
        avatarColor: String?,
        avatarShape: String?,
        avatarMaterial: String?,
        hiddenFromSidebar: Bool,
        lastActivityAt: Int64
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.tags = tags
        self.avatarColor = avatarColor
        self.avatarShape = avatarShape
        self.avatarMaterial = avatarMaterial
        self.hiddenFromSidebar = hiddenFromSidebar
        self.lastActivityAt = lastActivityAt
    }
}

/// Work list row projected from `works/<id>/profile.json` plus the timeline.
public struct WorkListEntry: Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var projectRoot: String?
    public var createdAt: Int64
    public var kind: String?
    public var avatar: String?
    public var workspaceId: String?
    public var lastActivityAt: Int64
    public var preview: String?

    public init(
        id: String,
        name: String,
        description: String,
        projectRoot: String?,
        createdAt: Int64,
        kind: String?,
        avatar: String?,
        workspaceId: String?,
        lastActivityAt: Int64,
        preview: String?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.projectRoot = projectRoot
        self.createdAt = createdAt
        self.kind = kind
        self.avatar = avatar
        self.workspaceId = workspaceId
        self.lastActivityAt = lastActivityAt
        self.preview = preview
    }
}

/// Task list row folded from `works/<id>/timeline.jsonl`. The timeline stays the source.
public struct TaskListEntry: Sendable, Equatable {
    public var workId: String
    public var taskId: String
    public var title: String
    public var state: String
    public var updatedAt: Int64
    public var assigneeIds: [String]
    public var ownerAgentId: String?
    public var revision: Int

    public init(
        workId: String,
        taskId: String,
        title: String,
        state: String,
        updatedAt: Int64,
        assigneeIds: [String],
        ownerAgentId: String?,
        revision: Int
    ) {
        self.workId = workId
        self.taskId = taskId
        self.title = title
        self.state = state
        self.updatedAt = updatedAt
        self.assigneeIds = assigneeIds
        self.ownerAgentId = ownerAgentId
        self.revision = revision
    }
}

/// Sidebar group projected from global `settings.json`, not from UserDefaults.
public struct SidebarSectionEntry: Sendable, Equatable {
    public var id: String
    public var name: String
    public var agentIds: [String]
    public var isCollapsed: Bool

    public init(id: String, name: String, agentIds: [String], isCollapsed: Bool) {
        self.id = id
        self.name = name
        self.agentIds = agentIds
        self.isCollapsed = isCollapsed
    }
}
