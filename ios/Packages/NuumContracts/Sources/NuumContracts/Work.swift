public enum WorkKind: String, Sendable, Equatable, CaseIterable {
    case room
    case work
}

public enum WorkRole: String, Sendable, Equatable, CaseIterable {
    case coordinator
    case worker
    case observer
}

public enum WorkTaskState: String, Sendable, Equatable, CaseIterable {
    case proposed
    case ready
    case inProgress = "in_progress"
    case blocked
    case review
    case done
    case cancelled
}

public enum WorkTaskPriority: String, Sendable, Equatable, CaseIterable {
    case low
    case normal
    case high
}

public struct WorkProfile: Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var projectRoot: String?
    public var createdAt: Int64
    public var kind: WorkKind?
    public var avatar: String?
    public var workspaceId: String?

    public init(
        id: String,
        name: String,
        description: String,
        projectRoot: String?,
        createdAt: Int64,
        kind: WorkKind? = nil,
        avatar: String? = nil,
        workspaceId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.projectRoot = projectRoot
        self.createdAt = createdAt
        self.kind = kind
        self.avatar = avatar
        self.workspaceId = workspaceId
    }
}

public struct WorkListItem: Sendable, Equatable {
    public var profile: WorkProfile
    public var lastActivityAt: Int64
    public var preview: String?

    public init(profile: WorkProfile, lastActivityAt: Int64, preview: String? = nil) {
        self.profile = profile
        self.lastActivityAt = lastActivityAt
        self.preview = preview
    }
}

public struct WorkGrants: Sendable, Equatable {
    public var canPost: Bool
    public var canManageOwnTasks: Bool
    public var canAssignTasks: Bool
    public var canEditCatalog: Bool

    public init(canPost: Bool, canManageOwnTasks: Bool, canAssignTasks: Bool, canEditCatalog: Bool) {
        self.canPost = canPost
        self.canManageOwnTasks = canManageOwnTasks
        self.canAssignTasks = canAssignTasks
        self.canEditCatalog = canEditCatalog
    }
}

public struct WorkBinding: Sendable, Equatable {
    public var workId: String
    public var role: WorkRole
    public var joinedAt: Int64
    public var grants: WorkGrants

    public init(workId: String, role: WorkRole, joinedAt: Int64, grants: WorkGrants) {
        self.workId = workId
        self.role = role
        self.joinedAt = joinedAt
        self.grants = grants
    }
}

public struct WorkMembership: Sendable, Equatable {
    public var revision: Int
    public var binding: WorkBinding?

    public init(revision: Int, binding: WorkBinding?) {
        self.revision = revision
        self.binding = binding
    }
}

public struct AgentSettings: Sendable, Equatable {
    public var model: ModelRef
    public var execution: ExecutionPreferences?
    public var workspace: WorkspaceSettings?
    public var hiddenFromSidebar: Bool
    public var proactive: ProactivePolicy?
    public var workMembership: WorkMembership?

    public init(
        model: ModelRef,
        execution: ExecutionPreferences? = nil,
        workspace: WorkspaceSettings? = nil,
        hiddenFromSidebar: Bool = false,
        proactive: ProactivePolicy? = nil,
        workMembership: WorkMembership? = nil
    ) {
        self.model = model
        self.execution = execution
        self.workspace = workspace
        self.hiddenFromSidebar = hiddenFromSidebar
        self.proactive = proactive
        self.workMembership = workMembership
    }
}

public struct AgentView: Sendable, Equatable {
    public var profile: AgentProfile
    public var settings: AgentSettings
    public var runtime: AgentRuntime
    public var roomMemberships: [String: WorkMembership]

    public init(
        profile: AgentProfile,
        settings: AgentSettings,
        runtime: AgentRuntime,
        roomMemberships: [String: WorkMembership] = [:]
    ) {
        self.profile = profile
        self.settings = settings
        self.runtime = runtime
        self.roomMemberships = roomMemberships
    }
}

public struct AgentSnapshot: Sendable, Equatable {
    public var view: AgentView
    public var events: [TranscriptEvent]
    public var blocks: [ViewBlock]
    public var live: LiveAssistant?

    public init(view: AgentView, events: [TranscriptEvent], blocks: [ViewBlock], live: LiveAssistant?) {
        self.view = view
        self.events = events
        self.blocks = blocks
        self.live = live
    }
}

public struct WorkDeliverable: Sendable, Equatable {
    public var id: String
    public var name: String
    public var uri: String
    public var createdAt: Int64
    public var mimeType: String?

    public init(id: String, name: String, uri: String, createdAt: Int64, mimeType: String? = nil) {
        self.id = id
        self.name = name
        self.uri = uri
        self.createdAt = createdAt
        self.mimeType = mimeType
    }
}

public struct WorkBlocker: Sendable, Equatable {
    public var reason: String
    public var ownerId: String?
    public var resumeCondition: String?
    public var createdAt: Int64?

    public init(reason: String, ownerId: String? = nil, resumeCondition: String? = nil, createdAt: Int64? = nil) {
        self.reason = reason
        self.ownerId = ownerId
        self.resumeCondition = resumeCondition
        self.createdAt = createdAt
    }
}

public struct WorkTask: Sendable, Equatable {
    public var id: String
    public var title: String
    public var description: String
    public var acceptanceCriteria: [String]
    public var state: WorkTaskState
    public var assigneeIds: [String]
    public var dependencyIds: [String]
    public var priority: WorkTaskPriority
    public var revision: Int
    public var deliverables: [WorkDeliverable]
    public var createdAt: Int64
    public var updatedAt: Int64
    public var ownerAgentId: String?
    public var blocker: WorkBlocker?

    public init(
        id: String,
        title: String,
        description: String,
        acceptanceCriteria: [String],
        state: WorkTaskState,
        assigneeIds: [String],
        dependencyIds: [String],
        priority: WorkTaskPriority,
        revision: Int,
        deliverables: [WorkDeliverable],
        createdAt: Int64,
        updatedAt: Int64,
        ownerAgentId: String? = nil,
        blocker: WorkBlocker? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.acceptanceCriteria = acceptanceCriteria
        self.state = state
        self.assigneeIds = assigneeIds
        self.dependencyIds = dependencyIds
        self.priority = priority
        self.revision = revision
        self.deliverables = deliverables
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ownerAgentId = ownerAgentId
        self.blocker = blocker
    }
}

public struct WorkTaskView: Sendable, Equatable {
    public var task: WorkTask
    public var allowedTransitions: [WorkTaskState]

    public init(task: WorkTask, allowedTransitions: [WorkTaskState]) {
        self.task = task
        self.allowedTransitions = allowedTransitions
    }
}

public struct SkillCatalogEntry: Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var enabled: Bool
    public var manifestPath: String

    public init(id: String, name: String, description: String, enabled: Bool, manifestPath: String) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.manifestPath = manifestPath
    }
}

public struct CliCatalogEntry: Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var enabled: Bool
    public var executable: String
    public var allowedSubcommands: [String]

    public init(
        id: String,
        name: String,
        description: String,
        enabled: Bool,
        executable: String,
        allowedSubcommands: [String]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.executable = executable
        self.allowedSubcommands = allowedSubcommands
    }
}

public struct KnowledgeCatalogEntry: Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var enabled: Bool
    public var roots: [String]
    public var readOnly: Bool

    public init(
        id: String,
        name: String,
        description: String,
        enabled: Bool,
        roots: [String],
        readOnly: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.roots = roots
        self.readOnly = readOnly
    }
}

public struct LocalToolCatalogEntry: Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var enabled: Bool
    public var toolNames: [String]

    public init(id: String, name: String, description: String, enabled: Bool, toolNames: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.toolNames = toolNames
    }
}

public enum WorkCatalogEntry: Sendable, Equatable {
    case skill(SkillCatalogEntry)
    case cli(CliCatalogEntry)
    case knowledge(KnowledgeCatalogEntry)
    case localTool(LocalToolCatalogEntry)

    public var id: String {
        switch self {
        case .skill(let entry): entry.id
        case .cli(let entry): entry.id
        case .knowledge(let entry): entry.id
        case .localTool(let entry): entry.id
        }
    }

    public var name: String {
        switch self {
        case .skill(let entry): entry.name
        case .cli(let entry): entry.name
        case .knowledge(let entry): entry.name
        case .localTool(let entry): entry.name
        }
    }

    public var enabled: Bool {
        switch self {
        case .skill(let entry): entry.enabled
        case .cli(let entry): entry.enabled
        case .knowledge(let entry): entry.enabled
        case .localTool(let entry): entry.enabled
        }
    }
}

public struct WorkCatalog: Sendable, Equatable {
    public var revision: Int
    public var entries: [WorkCatalogEntry]

    public init(revision: Int, entries: [WorkCatalogEntry]) {
        self.revision = revision
        self.entries = entries
    }
}

public struct SkillCatalogInput: Sendable, Equatable {
    public var name: String
    public var description: String
    public var manifestPath: String

    public init(name: String, description: String = "", manifestPath: String) {
        self.name = name
        self.description = description
        self.manifestPath = manifestPath
    }
}

public struct CliCatalogInput: Sendable, Equatable {
    public var name: String
    public var description: String
    public var executable: String
    public var allowedSubcommands: [String]

    public init(name: String, description: String = "", executable: String, allowedSubcommands: [String] = []) {
        self.name = name
        self.description = description
        self.executable = executable
        self.allowedSubcommands = allowedSubcommands
    }
}

public struct KnowledgeCatalogInput: Sendable, Equatable {
    public var name: String
    public var description: String
    public var roots: [String]
    public var readOnly: Bool

    public init(name: String, description: String = "", roots: [String], readOnly: Bool = true) {
        self.name = name
        self.description = description
        self.roots = roots
        self.readOnly = readOnly
    }
}

public struct LocalToolCatalogInput: Sendable, Equatable {
    public var name: String
    public var description: String
    public var toolNames: [String]

    public init(name: String, description: String = "", toolNames: [String]) {
        self.name = name
        self.description = description
        self.toolNames = toolNames
    }
}

public enum WorkCatalogInput: Sendable, Equatable {
    case skill(SkillCatalogInput)
    case cli(CliCatalogInput)
    case knowledge(KnowledgeCatalogInput)
    case localTool(LocalToolCatalogInput)

    public var name: String {
        switch self {
        case .skill(let input): input.name
        case .cli(let input): input.name
        case .knowledge(let input): input.name
        case .localTool(let input): input.name
        }
    }
}

public struct UserActor: Sendable, Equatable {
    public var id: String
    public init(id: String) { self.id = id }
}

public struct AgentActor: Sendable, Equatable {
    public var id: String
    public init(id: String) { self.id = id }
}

public struct SystemActor: Sendable, Equatable {
    public var id: String
    public init(id: String) { self.id = id }
}

public enum WorkActor: Sendable, Equatable {
    case user(UserActor)
    case agent(AgentActor)
    case system(SystemActor)

    public var id: String {
        switch self {
        case .user(let actor): actor.id
        case .agent(let actor): actor.id
        case .system(let actor): actor.id
        }
    }
}

public struct ChatPostedBody: Sendable, Equatable {
    public var messageId: String
    public var body: String
    public var mentionedAgentIds: [String]
    public var inputAfterSeq: Int?
    public var sourceSessionId: String?
    public var taskId: String?

    public init(
        messageId: String,
        body: String,
        mentionedAgentIds: [String],
        inputAfterSeq: Int? = nil,
        sourceSessionId: String? = nil,
        taskId: String? = nil
    ) {
        self.messageId = messageId
        self.body = body
        self.mentionedAgentIds = mentionedAgentIds
        self.inputAfterSeq = inputAfterSeq
        self.sourceSessionId = sourceSessionId
        self.taskId = taskId
    }
}

public struct TaskTransitionedBody: Sendable, Equatable {
    public var taskId: String
    public var from: WorkTaskState
    public var to: WorkTaskState
    public var revision: Int
    public var blocker: WorkBlocker?

    public init(
        taskId: String,
        from: WorkTaskState,
        to: WorkTaskState,
        revision: Int,
        blocker: WorkBlocker? = nil
    ) {
        self.taskId = taskId
        self.from = from
        self.to = to
        self.revision = revision
        self.blocker = blocker
    }
}

public struct MemberAttachedBody: Sendable, Equatable {
    public var membershipOperationId: String
    public var agentId: String
    public var role: WorkRole
    public var membershipRevision: Int

    public init(membershipOperationId: String, agentId: String, role: WorkRole, membershipRevision: Int) {
        self.membershipOperationId = membershipOperationId
        self.agentId = agentId
        self.role = role
        self.membershipRevision = membershipRevision
    }
}

public struct MemberDetachedBody: Sendable, Equatable {
    public var membershipOperationId: String
    public var agentId: String
    public var membershipRevision: Int

    public init(membershipOperationId: String, agentId: String, membershipRevision: Int) {
        self.membershipOperationId = membershipOperationId
        self.agentId = agentId
        self.membershipRevision = membershipRevision
    }
}

public struct DiscussionStartedBody: Sendable, Equatable {
    public var triggerEventIds: [String]
    public init(triggerEventIds: [String]) { self.triggerEventIds = triggerEventIds }
}

public struct DiscussionFinishedBody: Sendable, Equatable {
    public var discussionId: String
    public var status: String
    public var error: String?

    public init(discussionId: String, status: String, error: String? = nil) {
        self.discussionId = discussionId
        self.status = status
        self.error = error
    }
}

public struct WorkRequestedBody: Sendable, Equatable {
    public var agentId: String
    public var instruction: String
    public var membershipRevision: Int
    public var taskId: String?
    public var inputAfterSeq: Int?

    public init(
        agentId: String,
        instruction: String,
        membershipRevision: Int,
        taskId: String? = nil,
        inputAfterSeq: Int? = nil
    ) {
        self.agentId = agentId
        self.instruction = instruction
        self.membershipRevision = membershipRevision
        self.taskId = taskId
        self.inputAfterSeq = inputAfterSeq
    }
}

public struct ExecutionFinishedBody: Sendable, Equatable {
    public var executionId: String
    public var sourceEventId: String
    public var agentId: String
    public var status: String
    public var taskId: String?
    public var error: String?

    public init(
        executionId: String,
        sourceEventId: String,
        agentId: String,
        status: String,
        taskId: String? = nil,
        error: String? = nil
    ) {
        self.executionId = executionId
        self.sourceEventId = sourceEventId
        self.agentId = agentId
        self.status = status
        self.taskId = taskId
        self.error = error
    }
}

public enum WorkEventBody: Sendable, Equatable {
    case chatPosted(ChatPostedBody)
    case taskCreated(WorkTask)
    case taskTransitioned(TaskTransitionedBody)
    case memberAttached(MemberAttachedBody)
    case memberDetached(MemberDetachedBody)
    case discussionStarted(DiscussionStartedBody)
    case discussionFinished(DiscussionFinishedBody)
    case workRequested(WorkRequestedBody)
    case executionFinished(ExecutionFinishedBody)
}

public struct WorkEvent: Sendable, Equatable {
    public var type: String
    public var id: String
    public var workId: String
    public var seq: Int
    public var createdAt: Int64
    public var actor: WorkActor
    public var body: WorkEventBody
    public var causationId: String?
    public var correlationId: String?
    public var clientEventId: String?

    public init(
        type: String,
        id: String,
        workId: String,
        seq: Int,
        createdAt: Int64,
        actor: WorkActor,
        body: WorkEventBody,
        causationId: String? = nil,
        correlationId: String? = nil,
        clientEventId: String? = nil
    ) {
        self.type = type
        self.id = id
        self.workId = workId
        self.seq = seq
        self.createdAt = createdAt
        self.actor = actor
        self.body = body
        self.causationId = causationId
        self.correlationId = correlationId
        self.clientEventId = clientEventId
    }
}

public struct WorkInterruption: Sendable, Equatable {
    public var eventId: String
    public var error: String
    public var kind: String
    public var agentId: String?
    public var taskId: String?

    public init(eventId: String, error: String, kind: String, agentId: String? = nil, taskId: String? = nil) {
        self.eventId = eventId
        self.error = error
        self.kind = kind
        self.agentId = agentId
        self.taskId = taskId
    }
}

public struct WorkSnapshot: Sendable, Equatable {
    public var discussionRunning: Bool
    public var interruptions: [WorkInterruption]
    public var throughSeq: Int
    public var profile: WorkProfile
    public var members: [AgentView]
    public var catalog: WorkCatalog
    public var events: [WorkEvent]
    public var tasks: [WorkTaskView]
    public var chat: [WorkEvent]

    public init(
        discussionRunning: Bool,
        interruptions: [WorkInterruption],
        throughSeq: Int,
        profile: WorkProfile,
        members: [AgentView],
        catalog: WorkCatalog,
        events: [WorkEvent],
        tasks: [WorkTaskView],
        chat: [WorkEvent]
    ) {
        self.discussionRunning = discussionRunning
        self.interruptions = interruptions
        self.throughSeq = throughSeq
        self.profile = profile
        self.members = members
        self.catalog = catalog
        self.events = events
        self.tasks = tasks
        self.chat = chat
    }
}

public struct WorkCreateParams: Sendable, Equatable {
    public var name: String
    public var kind: WorkKind?

    public init(name: String, kind: WorkKind? = nil) {
        self.name = name
        self.kind = kind
    }
}

public struct WorkUpdateParams: Sendable, Equatable {
    public var id: String
    public var kind: WorkKind?
    public var name: String?

    public init(id: String, kind: WorkKind? = nil, name: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
    }
}

public struct WorkPostMessageParams: Sendable, Equatable {
    public var workId: String
    public var body: String
    public var mentionedAgentIds: [String]
    public var clientEventId: String?
    public var inputAfterSeq: Int?

    public init(
        workId: String,
        body: String,
        mentionedAgentIds: [String] = [],
        clientEventId: String? = nil,
        inputAfterSeq: Int? = nil
    ) {
        self.workId = workId
        self.body = body
        self.mentionedAgentIds = mentionedAgentIds
        self.clientEventId = clientEventId
        self.inputAfterSeq = inputAfterSeq
    }
}

public struct WorkMemberAttachParams: Sendable, Equatable {
    public var workId: String
    public var agentId: String
    public var expectedRevision: Int
    public var role: WorkRole

    public init(workId: String, agentId: String, expectedRevision: Int, role: WorkRole = .worker) {
        self.workId = workId
        self.agentId = agentId
        self.expectedRevision = expectedRevision
        self.role = role
    }
}

public struct WorkMemberDetachParams: Sendable, Equatable {
    public var workId: String
    public var agentId: String
    public var expectedRevision: Int

    public init(workId: String, agentId: String, expectedRevision: Int) {
        self.workId = workId
        self.agentId = agentId
        self.expectedRevision = expectedRevision
    }
}

public struct WorkMemberMoveParams: Sendable, Equatable {
    public var fromWorkId: String
    public var toWorkId: String
    public var agentId: String
    public var expectedRevision: Int
    public var role: WorkRole

    public init(
        fromWorkId: String,
        toWorkId: String,
        agentId: String,
        expectedRevision: Int,
        role: WorkRole = .worker
    ) {
        self.fromWorkId = fromWorkId
        self.toWorkId = toWorkId
        self.agentId = agentId
        self.expectedRevision = expectedRevision
        self.role = role
    }
}

public struct WorkTaskTranscriptParams: Sendable, Equatable {
    public var workId: String
    public var taskId: String
    public var sessionId: String?
    public var beforeSeq: Int?

    public init(workId: String, taskId: String, sessionId: String? = nil, beforeSeq: Int? = nil) {
        self.workId = workId
        self.taskId = taskId
        self.sessionId = sessionId
        self.beforeSeq = beforeSeq
    }
}

public struct WorkTaskTransitionParams: Sendable, Equatable {
    public var workId: String
    public var taskId: String
    public var to: WorkTaskState
    public var expectedRevision: Int
    public var blocker: WorkBlocker?

    public init(
        workId: String,
        taskId: String,
        to: WorkTaskState,
        expectedRevision: Int,
        blocker: WorkBlocker? = nil
    ) {
        self.workId = workId
        self.taskId = taskId
        self.to = to
        self.expectedRevision = expectedRevision
        self.blocker = blocker
    }
}

public struct WorkDispatchParams: Sendable, Equatable {
    public var workId: String
    public var agentId: String
    public var instruction: String
    public var taskId: String?

    public init(workId: String, agentId: String, instruction: String, taskId: String? = nil) {
        self.workId = workId
        self.agentId = agentId
        self.instruction = instruction
        self.taskId = taskId
    }
}

public struct WorkCatalogAddParams: Sendable, Equatable {
    public var workId: String
    public var expectedRevision: Int
    public var entry: WorkCatalogInput

    public init(workId: String, expectedRevision: Int, entry: WorkCatalogInput) {
        self.workId = workId
        self.expectedRevision = expectedRevision
        self.entry = entry
    }
}

public struct WorkCatalogRemoveParams: Sendable, Equatable {
    public var workId: String
    public var entryId: String
    public var expectedRevision: Int

    public init(workId: String, entryId: String, expectedRevision: Int) {
        self.workId = workId
        self.entryId = entryId
        self.expectedRevision = expectedRevision
    }
}

public struct WorkContinueParams: Sendable, Equatable {
    public var workId: String
    public var eventId: String
    public var inputAfterSeq: Int?

    public init(workId: String, eventId: String, inputAfterSeq: Int? = nil) {
        self.workId = workId
        self.eventId = eventId
        self.inputAfterSeq = inputAfterSeq
    }
}
